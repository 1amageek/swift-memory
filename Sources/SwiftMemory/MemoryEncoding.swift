// MemoryEncoding.swift
// Concept Protocol — interprets raw materials and produces structured knowledge

/// The Concept Protocol — interprets raw materials and produces structured knowledge.
///
/// Memory delegates interpretation to this protocol. The client
/// implements it by calling an LLM or other analysis system.
///
/// Receives raw materials (not yet persisted). Returns a MemoryBatch.
/// If the batch is non-empty, Memory saves both the materials as Given
/// and the extracted knowledge. If empty, materials are discarded.
public protocol MemoryEncoding: Sendable {
    /// Interpret raw materials and return structured knowledge.
    ///
    /// - Parameter materials: Raw materials from MemoryEncodable.encode(to:).
    ///   These are NOT yet saved — Memory decides based on the result.
    /// - Returns: MemoryBatch with entities + statements.
    ///   Empty batch → materials discarded (nothing worth remembering).
    ///   Non-empty → materials saved as Given + knowledge persisted.
    func interpret(_ materials: [GivenContainer.Material]) async throws -> MemoryBatch
}
