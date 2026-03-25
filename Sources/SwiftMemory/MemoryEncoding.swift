// MemoryEncoding.swift
// Concept Protocol — LLM delegate for store and recall

/// The Concept Protocol — LLM delegate for interpreting and querying knowledge.
///
/// Memory delegates both interpretation (store) and query extraction (recall)
/// to this protocol. The client implements it by calling an LLM.
public protocol MemoryEncoding: Sendable {
    /// Interpret input and extract structured knowledge (store).
    func interpret(_ input: any GivenRepresentable) async throws -> MemoryBatch

    /// Extract a recall query from input (recall).
    func extractQuery(_ input: any GivenRepresentable) async throws -> RecallQuery
}
