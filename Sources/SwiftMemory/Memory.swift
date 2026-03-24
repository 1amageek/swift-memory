// Memory.swift
// Public API: store / recall

import Foundation
import FDBite

/// Knowledge persistence system for LLM agents.
///
/// Memory stores **Given** (selected sensory materials) and **Knowledge**
/// (structured statements). Concepts are not stored — LLM reconstructs
/// them at inference time.
///
/// The Concept Protocol (MemoryEncoding) is **external** — the client
/// provides an implementation that interprets input and produces
/// Given + Knowledge. Memory only persists and recalls.
///
/// ```swift
/// let schema = Schema([Given.self, Statement.self])
/// let container = try await DBContainer(for: schema)
/// let context = MemoryContext(fdbContext: container.newContext())
/// let memory = Memory(context: context, encoding: myEncoder)
///
/// // Store — input encodes itself via MemoryEncodable.encode(to:)
/// try await memory.store("Today I saw cherry blossoms in Shibuya")
///
/// // Recall — spreading activation from keywords
/// let result = try await memory.recall(RecallQuery(keywords: ["cherry blossoms"]))
/// for entity in result.entities {
///     print("\(entity.label) (score: \(entity.score))")
/// }
/// ```
public actor Memory {

    private let context: MemoryContext
    private let encoding: any MemoryEncoding
    private let recallEngine: RecallEngine

    public init(context: MemoryContext, encoding: any MemoryEncoding) {
        self.context = context
        self.encoding = encoding
        self.recallEngine = RecallEngine(context: context)
    }

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

    /// Recall relevant entities and givens from memory.
    ///
    /// Uses spreading activation for keyword-based recall
    /// and vector similarity for embedding-based recall.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
    }
}
