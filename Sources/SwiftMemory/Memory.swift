// Memory.swift
// Knowledge persistence and recall

import Foundation
import Database
import MemoryOntology
import os.log

private let logger = Logger(subsystem: "com.memory", category: "Memory")

/// Knowledge persistence system for LLM agents.
///
/// Memory stores and recalls knowledge. It does **not** interpret raw input.
///
/// Interpretation is the responsibility of an external agent:
/// - A nested agent (e.g. haiku) analyzes conversation and structures knowledge
/// - The agent calls `store(batch)` with entities and relationships
/// - Memory persists them and enables recall via spreading activation
///
/// This separation ensures:
/// - Memory's context is clean — no LLM prompts or interpretation logic
/// - The interpreting agent can use a cheaper model (cost optimization)
/// - Interpretation logic lives in a Skill definition, not in code
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     entityTypes: [Person.self, Organization.self]
/// )
///
/// // Store (called by the interpreting agent via MCP tool)
/// var batch = MemoryBatch()
/// batch.entity(person)
/// batch.triple("ex:alice", "ex:worksAt", "ex:acme")
/// try await memory.store(batch)
///
/// // Recall (called by Claude via MCP tool)
/// let result = try await memory.recall(keywords: ["Alice"])
/// ```
public actor Memory {

    private let context: MemoryContext
    private let container: DBContainer
    private let recallEngine: RecallEngine

    public nonisolated let ontologyPolicy: any OntologyPolicy

    public init(
        path: String?,
        entityTypes: [any Persistable.Type] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default"
    ) async throws {
        self.ontologyPolicy = ontologyPolicy

        let allTypes: [any Persistable.Type] = [Given.self, Statement.self, Trace.self] + entityTypes
        let schema = Schema(allTypes, version: Schema.Version(1, 0, 0))

        if let path {
            self.container = try await DBContainer.sqlite(
                for: schema, path: path, security: .disabled
            )
        } else {
            self.container = try await DBContainer.inMemory(
                for: schema, security: .disabled
            )
        }

        let fdbContext = container.newContext()
        try await fdbContext.ontology.load(ontologyPolicy.buildOntology())

        self.context = MemoryContext(fdbContext: fdbContext, graphName: graphName)
        self.recallEngine = RecallEngine(context: context)
    }

    // MARK: - Store

    /// Store Given + Knowledge atomically.
    ///
    /// Given is the raw material. Knowledge is the structured interpretation.
    /// Given is saved only when knowledge is non-empty.
    /// Trace records link each Statement back to its source Given.
    public func store(given: any Memorable, knowledge: some MemoryBatchConvertible) async throws {
        let givenID = ULID().ulidString
        let batch = knowledge.toBatch()

        guard !batch.entities.isEmpty || !batch.statements.isEmpty else {
            logger.info("[store] empty knowledge — nothing saved")
            return
        }

        // Save Given (raw material)
        var givenRecord = Given(
            modality: given.modality,
            payloadRef: given.payloadRef,
            embedding: [Float](repeating: 0, count: 384),
            timestamp: Date(),
            source: "given"
        )
        givenRecord.id = givenID
        context.fdbContext.insert(givenRecord)

        // Save entities (OntologyIndex auto-generates triples)
        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }

        // Save explicit relationship statements and create Trace records
        for record in batch.statements {
            let statementID = Statement.contentID(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            var statement = Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            statement.id = statementID
            context.fdbContext.insert(statement)

            var trace = Trace()
            trace.id = "\(givenID)|\(statementID)"
            trace.givenID = givenID
            trace.statementID = statementID
            context.fdbContext.insert(trace)
        }

        try await context.fdbContext.save()
        logger.info("[store] given=\(givenID) entities=\(batch.entities.count) traces=\(batch.statements.count) statements=\(batch.statements.count)")
    }

    /// Store Given + Knowledge from raw data and a decode closure.
    /// Used by MCP tool handler where knowledge comes as JSON Data.
    public func store(given: any Memorable, knowledgeData: Data, decode: @Sendable (Data) throws -> MemoryBatch) async throws {
        let givenID = ULID().ulidString
        let batch = try decode(knowledgeData)

        guard !batch.entities.isEmpty || !batch.statements.isEmpty else {
            logger.info("[store] empty knowledge — nothing saved")
            return
        }

        var givenRecord = Given(
            modality: given.modality,
            payloadRef: given.payloadRef,
            embedding: [Float](repeating: 0, count: 384),
            timestamp: Date(),
            source: "given"
        )
        givenRecord.id = givenID
        context.fdbContext.insert(givenRecord)

        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }
        for record in batch.statements {
            let statementID = Statement.contentID(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            var statement = Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            statement.id = statementID
            context.fdbContext.insert(statement)

            var trace = Trace()
            trace.id = "\(givenID)|\(statementID)"
            trace.givenID = givenID
            trace.statementID = statementID
            context.fdbContext.insert(trace)
        }

        try await context.fdbContext.save()
        logger.info("[store] given=\(givenID) entities=\(batch.entities.count) traces=\(batch.statements.count) statements=\(batch.statements.count)")
    }

    /// Store a batch directly (without Given).
    /// No Trace records are created because there is no Given to link from.
    public func store(_ batch: MemoryBatch) async throws {
        guard !batch.entities.isEmpty || !batch.statements.isEmpty else { return }
        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }
        for record in batch.statements {
            var statement = Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            statement.id = Statement.contentID(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            )
            context.fdbContext.insert(statement)
        }
        try await context.fdbContext.save()
    }

    // MARK: - Recall

    /// Recall from keywords — spreading activation.
    public func recall(keywords: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recallEngine.execute(RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit))
    }

    /// Recall with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
