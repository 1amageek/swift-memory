// MemoryEncoding.swift
// Concept Protocol — LLM delegate for interpreting knowledge

/// The Concept Protocol — LLM delegate for interpreting input into knowledge.
///
/// Memory delegates interpretation to this protocol. The client
/// implements it by calling an LLM.
public protocol MemoryEncoding: Sendable {
    /// Interpret input and extract structured knowledge.
    func interpret(_ input: any GivenRepresentable) async throws -> MemoryBatch
}
