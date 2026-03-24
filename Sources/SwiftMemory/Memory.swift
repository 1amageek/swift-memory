// Memory.swift
// Public API: store / recall

import Foundation
import Database
import MemoryOntology

/// Knowledge persistence system for LLM agents.
///
/// Stores **Given** (raw materials), **@OWLClass entities** (typed records),
/// and **Statements** (RDF triples). The Concept Protocol (`MemoryEncoding`)
/// is external — the client provides an LLM-powered implementation that
/// interprets input and produces a `MemoryBatch`.
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

    /// The ontology policy governing class/property validation.
    public nonisolated let ontologyPolicy: any OntologyPolicy

    /// Initialize Memory with SQLite persistence.
    ///
    /// - Parameters:
    ///   - path: SQLite file path. Pass `nil` for in-memory (testing).
    ///   - encoding: Concept Protocol implementation (LLM-powered).
    ///   - entityTypes: `@OWLClass` Persistable types to register.
    ///   - ontologyPolicy: Ontology policy for validation. Defaults to `DefaultOntologyPolicy`.
    ///   - graphName: Named graph for this memory instance.
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

    /// Store input through the Concept Protocol.
    ///
    /// 1. `encoding.encode(input)` — LLM interprets and produces MemoryBatch
    /// 2. Memory deduplicates entities (recall by label + type → upsert)
    /// 3. Persists Givens, Entities, and Statements atomically
    public func store(_ input: String) async throws {
        let batch = try await encoding.encode(input)
        try await persist(batch)
    }

    /// Store a pre-built MemoryBatch directly.
    ///
    /// Use when the caller has already constructed the batch
    /// (e.g. from parsed Claude output).
    public func store(_ batch: MemoryBatch) async throws {
        try await persist(batch)
    }

    private func persist(_ batch: MemoryBatch) async throws {

        // Givens → Given @Persistable records
        for record in batch.givens {
            var given = Given(
                modality: "text",
                payloadRef: record.text,
                embedding: [Float](repeating: 0, count: 384),
                timestamp: Date(),
                source: record.source
            )
            context.fdbContext.insert(given)
        }

        // Entities → rdf:type + rdfs:label + property triples
        for entity in batch.entities {
            let iri = "memory:\(entity.type.lowercased())/\(entity.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
            context.fdbContext.insert(Statement(
                graph: context.graphName, subject: iri, predicate: "rdf:type", object: "ex:\(entity.type)"
            ))
            context.fdbContext.insert(Statement(
                graph: context.graphName, subject: iri, predicate: "rdfs:label", object: entity.name
            ))
            for (key, value) in entity.properties {
                context.fdbContext.insert(Statement(
                    graph: context.graphName, subject: iri, predicate: key, object: value
                ))
            }
        }

        // Statements → Statement @Persistable records
        for record in batch.statements {
            let subject = resolveIRI(record.subject, entities: batch.entities)
            let object = resolveIRI(record.object, entities: batch.entities)
            context.fdbContext.insert(Statement(
                graph: context.graphName,
                subject: subject,
                predicate: record.predicate,
                object: object
            ))
        }

        try await context.fdbContext.save()
    }

    /// Resolve a name or IRI. If it matches an entity name, return its IRI.
    private func resolveIRI(_ value: String, entities: [EntityRecord]) -> String {
        // Already an IRI
        if value.contains(":") { return value }
        // Look up by name in entities
        if let entity = entities.first(where: { $0.name == value }) {
            return "memory:\(entity.type.lowercased())/\(value.lowercased().replacingOccurrences(of: " ", with: "_"))"
        }
        return value
    }

    // MARK: - Recall

    /// Recall relevant entities from memory by keywords.
    ///
    /// Uses spreading activation on the knowledge graph.
    public func recall(keywords: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recallEngine.execute(RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit))
    }

    /// Recall with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
