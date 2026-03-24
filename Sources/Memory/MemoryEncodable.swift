// MemoryEncodable.swift
// Types that know how to convert themselves into Given + Knowledge

import Foundation

/// A type that can encode itself into Memory's storable formats.
///
/// Analogous to `Encodable` in Swift's standard library.
/// Conforming types know how to present their content to a `MemoryEncoding`
/// destination, which provides containers for Given Store and Knowledge Store.
///
/// ```swift
/// struct ChatMessage: MemoryEncodable {
///     var text: String
///     var sender: String
///
///     func encode(to encoding: some MemoryEncoding) async throws {
///         var givens = encoding.givenContainer()
///         givens.encode(text, source: "chat")
///
///         var knowledge = encoding.knowledgeContainer()
///         knowledge.encode(subject: "memory:given/\(id)", predicate: "ex:sentBy", object: "ex:\(sender)")
///     }
/// }
/// ```
public protocol MemoryEncodable: Sendable {
    func encode(to encoding: some MemoryEncoding) async throws
}

// MARK: - Default Conformances

extension String: MemoryEncodable {
    public func encode(to encoding: some MemoryEncoding) async throws {
        var givens = encoding.givenContainer()
        givens.encode(self, source: "text")
    }
}

extension URL: MemoryEncodable {
    public func encode(to encoding: some MemoryEncoding) async throws {
        var givens = encoding.givenContainer()
        givens.encode(absoluteString, source: "url")
    }
}
