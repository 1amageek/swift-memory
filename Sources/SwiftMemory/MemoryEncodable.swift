// MemoryEncodable.swift
// Types that can be stored as Given in Memory

import Foundation

/// A type that can present itself as raw material (Given) for Memory.
///
/// Conforming types know how to express themselves as Given data.
/// Memory calls `encode(to:)` to collect Given records before
/// delegating interpretation to MemoryEncoding.
///
/// ```swift
/// extension String: MemoryEncodable {
///     public func encode(to encoder: some MemoryEncoder) throws {
///         encoder.givenContainer().encode(self, source: "text")
///     }
/// }
/// ```
public protocol MemoryEncodable: Sendable {
    func encode(to encoder: some MemoryEncoder) throws
}

// MARK: - Default Conformances

extension String: MemoryEncodable {
    public func encode(to encoder: some MemoryEncoder) throws {
        encoder.givenContainer().encode(self, source: "text")
    }
}

extension URL: MemoryEncodable {
    public func encode(to encoder: some MemoryEncoder) throws {
        encoder.givenContainer().encode(absoluteString, source: "url")
    }
}
