// MemoryEncoding.swift
// Concept Protocol — provides containers for Given Store and Knowledge Store

/// The Concept Protocol destination.
///
/// Analogous to `Encoder` in Swift's standard library.
/// Provides containers that `MemoryEncodable` types use to submit
/// their content for persistence in Given Store and Knowledge Store.
///
/// Implementations (LLM, VLM, rules, etc.) are provided by the **client**.
/// The implementation decides how to process submitted materials —
/// e.g., computing embeddings, extracting additional knowledge via LLM.
public protocol MemoryEncoding: Sendable {

    /// Returns a container for submitting Given materials.
    func givenContainer() -> GivenEncodingContainer

    /// Returns a container for submitting Knowledge (statements).
    func knowledgeContainer() -> KnowledgeEncodingContainer
}
