// MemoryEncoder.swift
// Encoder that collects Given data from MemoryEncodable types

/// Encoder that MemoryEncodable types write their content to.
///
/// Provides a GivenContainer for collecting raw materials.
/// Used internally by Memory during the store flow.
public protocol MemoryEncoder {
    func givenContainer() -> GivenContainer
}
