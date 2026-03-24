// Memory.swift
// Public API: store / recall

import Foundation
import Database
import MemoryOntology

/// Knowledge persistence system for LLM agents.
///
/// Stores **Given** (raw materials), interprets them via **MemoryEncoding**
/// (LLM-powered), and persists structured knowledge as **@OWLClass entities**
/// and **Statement triples**.
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     encoding: MyEncoding(),
///     entityTypes: [Person.self, Organization.self]
/// )
///
/// // Bob passes conversation text — Memory handles the rest
/// try await memory.store("Alice works at Acme Corp")
///
/// // Recall by keywords
/// let result = try await memory.recall(keywords: ["Alice"])
/// ```
public actor Memory {

    private let context: MemoryContext
    private let container: DBContainer
    private let encoding: any MemoryEncoding
    private let recallEngine: RecallEngine

    /// The ontology policy governing class/property validation.
    public nonisolated let ontologyPolicy: any OntologyPolicy

    /// Initialize Memory with SQLite persistence.
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
    /// 1. `input.encode(to: encoder)` → Given records
    /// 2. Given records saved to DB
    /// 3. `encoding.interpret(givens)` → MemoryBatch (entities + statements)
    /// 4. Entities inserted → OntologyIndex auto-syncs triples
    /// 5. Explicit statements inserted
    /// 6. Atomic save
    public func store(_ input: any MemoryEncodable) async throws {
        // Step 1: Encode input to Given materials
        let encoder = DefaultMemoryEncoder()
        try input.encode(to: encoder)
        let materials = encoder.givenContainer().collectMaterials()

        // Step 2: Save Givens to DB
        var givens: [Given] = []
        for material in materials {
            let given = Given(
                modality: material.modality,
                payloadRef: material.text,
                embedding: [Float](repeating: 0, count: 384),
                timestamp: Date(),
                source: material.source
            )
            context.fdbContext.insert(given)
            givens.append(given)
        }

        // Step 3: Interpret via MemoryEncoding (LLM)
        let batch = try await encoding.interpret(givens)

        // Step 4: Persist entities (OntologyIndex auto-syncs triples)
        for entity in batch.entities {
            context.fdbContext.insert(entity)
        }

        // Step 5: Persist explicit relationship statements
        for record in batch.statements {
            context.fdbContext.insert(Statement(
                graph: context.graphName,
                subject: record.subject,
                predicate: record.predicate,
                object: record.object
            ))
        }

        // Step 6: Atomic save
        try await context.fdbContext.save()
    }

    /// Store a pre-built MemoryBatch directly (skip Given/interpret).
    public func store(_ batch: MemoryBatch) async throws {
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

    /// Recall relevant entities from memory by keywords.
    public func recall(keywords: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recallEngine.execute(RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit))
    }

    /// Recall with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
