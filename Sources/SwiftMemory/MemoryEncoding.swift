// MemoryEncoding.swift
// Concept Protocol — interprets GivenRepresentable input via LLM

/// The Concept Protocol — interprets input and produces structured knowledge.
///
/// Memory delegates interpretation to this protocol. The client
/// implements it by calling an LLM or other analysis system.
///
/// Receives the raw input as `GivenRepresentable`.
/// Returns a MemoryBatch with entities and statements.
/// If the batch is non-empty, Memory also saves the input as Given.
public protocol MemoryEncoding: Sendable {
    func interpret(_ input: any GivenRepresentable) async throws -> MemoryBatch
}
