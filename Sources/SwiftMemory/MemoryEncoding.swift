// MemoryEncoding.swift
// Concept Protocol — interprets input and produces MemoryBatch

/// The Concept Protocol.
///
/// Implementations (LLM, VLM, rules, etc.) are provided by the **client**.
/// Given raw input, the encoding interprets it and produces a `MemoryBatch`
/// containing Givens (raw materials), Entities (@OWLClass records),
/// and Statements (RDF triples).
///
/// ```swift
/// struct MyEncoding: MemoryEncoding {
///     func encode(_ input: String) async throws -> MemoryBatch {
///         let analysis = await llm.analyze(input)
///         var batch = MemoryBatch()
///         batch.given(input, source: "chat")
///         batch.entity(Person(name: analysis.personName))
///         batch.triple(personIRI, "ex:worksAt", orgIRI)
///         return batch
///     }
/// }
/// ```
public protocol MemoryEncoding: Sendable {

    /// Interpret input and produce a batch of materials to persist.
    func encode(_ input: String) async throws -> MemoryBatch
}
