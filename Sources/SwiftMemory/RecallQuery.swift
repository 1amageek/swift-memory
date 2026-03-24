// RecallQuery.swift
// Query parameters for memory recall

import Foundation

/// Parameters for recalling relevant entities from memory.
///
/// Supports two recall strategies:
/// - **Keywords**: Spreading activation from label-matched seed entities
/// - **Embedding**: Vector similarity search on Given Store
public struct RecallQuery: Sendable {

    /// Keywords for spreading activation recall.
    ///
    /// Each keyword is matched against rdfs:label via substring search.
    /// Matched entities become seeds for bidirectional graph traversal.
    /// Entities reached by multiple keywords score higher (convergence).
    public var keywords: [String]

    /// Embedding vector for semantic nearest-neighbor search on Given.
    public var embedding: [Float]?

    /// Maximum hops from seed entities (default: 2).
    public var maxHops: Int

    /// Maximum number of results to return.
    public var limit: Int

    public init(
        keywords: [String] = [],
        embedding: [Float]? = nil,
        maxHops: Int = 2,
        limit: Int = 20
    ) {
        self.keywords = keywords
        self.embedding = embedding
        self.maxHops = maxHops
        self.limit = limit
    }
}
