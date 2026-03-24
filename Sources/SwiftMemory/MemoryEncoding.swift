// MemoryEncoding.swift
// Concept Protocol — interprets Givens and produces structured knowledge

/// The Concept Protocol — interprets Givens and produces structured knowledge.
///
/// Memory delegates interpretation to this protocol. The client
/// implements it by calling an LLM or other analysis system.
///
/// ```swift
/// struct MyEncoding: MemoryEncoding {
///     func interpret(_ givens: [Given]) async throws -> MemoryBatch {
///         var batch = MemoryBatch()
///         for given in givens where given.modality == "text" {
///             let analysis = await llm.analyze(given.payloadRef)
///             batch.entity(Person(name: analysis.name))
///             batch.triple(personIRI, "ex:worksAt", orgIRI)
///         }
///         return batch
///     }
/// }
/// ```
public protocol MemoryEncoding: Sendable {
    /// Interpret saved Givens and return structured knowledge.
    ///
    /// Called by Memory after Givens are persisted.
    func interpret(_ givens: [Given]) async throws -> MemoryBatch
}
