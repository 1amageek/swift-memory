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
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil
    ) async throws {
        self.ontologyPolicy = ontologyPolicy

        let allTypes: [any Persistable.Type] = [Given.self, Statement.self, Trace.self] + entityTypes
        let schema = Schema(allTypes, version: Schema.Version(2, 0, 0))

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

        self.context = MemoryContext(
            fdbContext: fdbContext,
            graphName: graphName,
            embeddingProvider: embeddingProvider
        )
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

        // Save Given (raw material) with embedding if provider is available
        let embedding: [Float]
        if let provider = context.embeddingProvider {
            embedding = try await provider.embed(given.payloadRef)
        } else {
            embedding = [Float](repeating: 0, count: Given.embeddingDimensions)
        }
        var givenRecord = Given(
            modality: given.modality,
            payloadRef: given.payloadRef,
            embedding: embedding,
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

        let embedding: [Float]
        if let provider = context.embeddingProvider {
            embedding = try await provider.embed(given.payloadRef)
        } else {
            embedding = [Float](repeating: 0, count: Given.embeddingDimensions)
        }
        var givenRecord = Given(
            modality: given.modality,
            payloadRef: given.payloadRef,
            embedding: embedding,
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

    // MARK: - Resolve

    /// Resolve entity candidates against existing knowledge.
    ///
    /// For each candidate, embeds its triple text ("{type} {label} {context}"),
    /// fetches all existing entities from the shared Entity polymorphic group,
    /// and returns the best match above the similarity threshold.
    ///
    /// **SubAgent Flow**:
    /// ```
    /// 1. ontology()  -> schema
    /// 2. resolve([{ type: "organizations", label: "Creww Corp", context: "creww.me" }])
    ///    -> [{ inputLabel: "Creww Corp", matchedLabel: "Creww", similarity: 0.92 }]
    /// 3. store(given, knowledge with matchedLabel)
    /// ```
    ///
    /// - Parameters:
    ///   - candidates: Entity candidates with type, label, and optional context.
    ///   - witness: Any concrete Entity type (used to satisfy Swift generics;
    ///     the polymorphic fetch returns ALL Entity types regardless).
    ///   - threshold: Minimum similarity score to consider a match (default: 0.8).
    /// - Returns: Resolution results for each candidate.
    public func resolve<T: Persistable & Entity>(
        _ candidates: [ResolveCandidate],
        witness: T.Type,
        threshold: Float = 0.8
    ) async throws -> [ResolvedEntity] {
        guard let provider = context.embeddingProvider else {
            logger.info("[resolve] no embedding provider — returning all unresolved")
            return candidates.map {
                ResolvedEntity(inputLabel: $0.label, inputType: $0.type)
            }
        }

        guard !candidates.isEmpty else { return [] }

        // Fetch all existing entities from the polymorphic Entity group
        let existingItems = try await context.fdbContext.fetchPolymorphic(T.self)

        // Build lookup: extract (id, label, embedding) from each entity
        var entityIDs: [String] = []
        var entityLabels: [String] = []
        var entityEmbeddings: [[Float]] = []

        for item in existingItems {
            guard let entity = item as? any Entity else { continue }
            entityIDs.append(String(describing: item.id))
            entityLabels.append(entity.label)
            entityEmbeddings.append(entity.embedding)
        }

        // Resolve each candidate
        var results: [ResolvedEntity] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let queryEmbedding = try await provider.embed(candidate.embeddingText)

            var bestIndex: Int?
            var bestSimilarity: Float = 0

            for i in 0..<entityIDs.count {
                let emb = entityEmbeddings[i]
                guard !emb.isEmpty, emb.count == queryEmbedding.count else { continue }
                let sim = Self.cosineSimilarity(queryEmbedding, emb)
                if sim >= threshold && sim > bestSimilarity {
                    bestIndex = i
                    bestSimilarity = sim
                }
            }

            if let idx = bestIndex {
                results.append(ResolvedEntity(
                    inputLabel: candidate.label,
                    inputType: candidate.type,
                    matchedID: entityIDs[idx],
                    matchedLabel: entityLabels[idx],
                    similarity: bestSimilarity
                ))
            } else {
                results.append(ResolvedEntity(
                    inputLabel: candidate.label,
                    inputType: candidate.type
                ))
            }
        }

        let resolvedCount = results.filter(\.isResolved).count
        logger.info("[resolve] \(candidates.count) candidates -> \(resolvedCount) resolved")
        return results
    }

    // MARK: - Entity Embedding Update

    /// Update embeddings for entities in a batch.
    ///
    /// Called after store() to populate embedding vectors on newly inserted entities.
    /// Entities with non-empty embeddings are re-embedded if their label/context changed.
    ///
    /// - Parameters:
    ///   - entries: Entity metadata for embedding generation.
    public func updateEntityEmbeddings(_ entries: [EntityEmbeddingEntry]) async throws {
        guard let provider = context.embeddingProvider else {
            logger.info("[updateEntityEmbeddings] no embedding provider — skipping")
            return
        }

        guard !entries.isEmpty else { return }

        for entry in entries {
            let text = entry.embeddingText
            let embedding = try await provider.embed(text)

            // Fetch the entity, update its embedding, and re-save
            try await entry.applyEmbedding(embedding, context.fdbContext)
        }

        try await context.fdbContext.save()
        logger.info("[updateEntityEmbeddings] updated \(entries.count) entity embeddings")
    }

    // MARK: - Cosine Similarity

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
