// Memory.swift
// Public API: store / recall

import Foundation
import Database
import MemoryOntology
import os.log

private let logger = Logger(subsystem: "com.memory", category: "Memory")

/// Knowledge persistence system for LLM agents.
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     encoding: MyEncoding(),
///     entityTypes: [Person.self, Organization.self]
/// )
///
/// try await memory.store("Alice works at Acme Corp")
/// let result = try await memory.recall(keywords: ["Alice"])
/// ```
public actor Memory {

    private let context: MemoryContext
    private let container: DBContainer
    private let encoding: any MemoryEncoding
    private let recallEngine: RecallEngine

    public nonisolated let ontologyPolicy: any OntologyPolicy

    public init(
        path: String?,
        encoding: any MemoryEncoding,
        entityTypes: [any Persistable.Type] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default"
    ) async throws {
        self.ontologyPolicy = ontologyPolicy
        let allTypes: [any Persistable.Type] = [Given.self, Statement.self] + entityTypes
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
        self.encoding = encoding
        self.recallEngine = RecallEngine(context: context)
    }

    // MARK: - Store

    /// Store input through the full pipeline.
    ///
    /// 1. LLM interprets input via MemoryEncoding
    /// 2. If batch is empty → discard (nothing worth remembering)
    /// 3. Save input as Given (LLM found knowledge)
    /// 4. Insert entities → OntologyIndex auto-syncs triples
    /// 5. Insert explicit statements
    /// 6. Atomic save
    public func store(_ input: any GivenRepresentable) async throws {
        let batch = try await encoding.interpret(input)
        guard !batch.entities.isEmpty || !batch.statements.isEmpty else {
            logger.info("[store] empty batch — nothing saved")
            return
        }
        logger.info("[store] persisting \(batch.entities.count) entities, \(batch.statements.count) statements")

        // Save input as Given
        let content = input.givenRepresentation
        for component in content.components {
            let modality: String
            let payloadRef: String
            switch component {
            case .text(let text):
                modality = "text"
                payloadRef = text.value
            case .image(let image):
                modality = "image"
                switch image.source {
                case .base64(let data, _): payloadRef = data
                case .url(let url): payloadRef = url.absoluteString
                }
            case .audio(let audio):
                modality = "audio"
                switch audio.source {
                case .base64(let data, _): payloadRef = data
                case .url(let url): payloadRef = url.absoluteString
                }
            }
            context.fdbContext.insert(Given(
                modality: modality,
                payloadRef: payloadRef,
                embedding: [Float](repeating: 0, count: 384),
                timestamp: Date(),
                source: "given"
            ))
        }

        // Persist entities
        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }

        // Persist explicit statements
        for record in batch.statements {
            context.fdbContext.insert(Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            ))
        }

        try await context.fdbContext.save()
        logger.info("[store] saved to DB")
    }

    /// Store a pre-built MemoryBatch directly.
    public func store(_ batch: MemoryBatch) async throws {
        guard !batch.entities.isEmpty || !batch.statements.isEmpty else { return }
        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }
        for record in batch.statements {
            context.fdbContext.insert(Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            ))
        }
        try await context.fdbContext.save()
    }

    // MARK: - Recall

    // MARK: - Associate

    /// Associative recall — spreading activation from cues.
    ///
    /// The primary recall API. Given cues (keywords), finds seed entities
    /// by label match, spreads activation through the graph, and returns
    /// entities scored by convergence.
    public func associate(cues: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recallEngine.execute(RecallQuery(keywords: cues, maxHops: maxHops, limit: limit))
    }

    /// Associative recall from input — LLM extracts cues, then spreading activation.
    public func associate(_ input: any GivenRepresentable, maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        let query = try await encoding.extractQuery(input)
        guard !query.keywords.isEmpty else { return .empty }
        logger.info("[associate] cues=\(query.keywords)")
        return try await recallEngine.execute(RecallQuery(keywords: query.keywords, maxHops: maxHops, limit: limit))
    }

    /// Low-level recall with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
