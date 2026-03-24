// Memory.swift
// Public API: store / recall

import Foundation
import Database
import MemoryOntology

/// Knowledge persistence system for LLM agents.
///
/// Memory stores **Given** (selected sensory materials), **Knowledge**
/// (structured statements), and **@OWLClass entities** (typed records).
/// Concepts are not stored — LLM reconstructs them at inference time.
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     encoding: myEncoder,
///     entityTypes: [Person.self, Organization.self]
/// )
///
/// // Store entity — persists as typed record + auto-synced triples + Given
/// try await memory.store(person)
///
/// // Recall — spreading activation from keywords
/// let result = try await memory.recall(RecallQuery(keywords: ["Alice"]))
/// ```
public actor Memory {

    private let context: MemoryContext
    private let container: DBContainer
    private let encoding: any MemoryEncoding
    private let recallEngine: RecallEngine

    /// The ontology policy governing class/property validation.
    public let ontologyPolicy: any OntologyPolicy

    /// Initialize Memory with SQLite persistence.
    ///
    /// - Parameters:
    ///   - path: SQLite file path. Pass `nil` for in-memory (testing).
    ///   - encoding: Concept Protocol implementation.
    ///   - entityTypes: `@OWLClass` Persistable types to register in the schema.
    ///   - ontologyPolicy: Ontology policy for class/property validation.
    ///     Defaults to `DefaultOntologyPolicy`.
    ///   - graphName: Named graph for this memory instance.
    public init(
        path: String?,
        encoding: any MemoryEncoding,
        entityTypes: [any Persistable.Type] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default"
    ) async throws {
        self.ontologyPolicy = ontologyPolicy

        // Build schema: Given + Statement + client entity types
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

        // Load ontology into OntologyStore
        try await fdbContext.ontology.load(ontologyPolicy.buildOntology())

        self.context = MemoryContext(fdbContext: fdbContext, graphName: graphName)
        self.encoding = encoding
        self.recallEngine = RecallEngine(context: context)
    }

    // MARK: - Store

    /// Store input through the Concept Protocol.
    ///
    /// 1. `input.encode(to: encoding)` — the type submits its materials
    /// 2. Containers collect Given materials and Knowledge statements
    /// 3. Memory persists both atomically
    public func store(_ input: any MemoryEncodable) async throws {

        // Input encodes itself to the MemoryEncoding destination
        try await input.encode(to: encoding)

        // Collect Given materials and build Given objects
        let givenContainer = encoding.givenContainer()
        for material in givenContainer.collectMaterials() {
            let given = Given(
                modality: material.modality,
                payloadRef: material.payload,
                embedding: [],
                timestamp: Date(),
                source: material.source
            )
            context.fdbContext.insert(given)
        }

        // Collect Knowledge statements
        let knowledgeContainer = encoding.knowledgeContainer()
        for raw in knowledgeContainer.collectStatements() {
            let statement = Statement(
                graph: context.graphName,
                subject: raw.subject,
                predicate: raw.predicate,
                object: raw.object
            )
            context.fdbContext.insert(statement)
        }

        // Persist atomically
        try await context.fdbContext.save()
    }

    /// Store a Persistable entity directly.
    ///
    /// Inserts the entity as a typed record. If the entity conforms to
    /// `OWLClassEntity`, OntologyIndex automatically syncs triples
    /// (rdf:type, rdfs:label, data/object properties) on save.
    public func store<T: Persistable>(_ entity: T) async throws {
        context.fdbContext.insert(entity)
        try await context.fdbContext.save()
    }

    /// Fetch entities of a given type.
    public func fetch<T: Persistable>(_ type: T.Type) async throws -> [T] {
        try await context.fdbContext.fetch(type).execute()
    }

    // MARK: - Recall

    /// Recall relevant entities and givens from memory.
    ///
    /// Uses spreading activation for keyword-based recall
    /// and vector similarity for embedding-based recall.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
