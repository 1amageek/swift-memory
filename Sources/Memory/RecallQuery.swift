// RecallQuery.swift
// Query parameters for memory recall

import Foundation

/// Parameters for recalling relevant Given and Knowledge from memory.
///
/// Pure data retrieval — no LLM interpretation.
public struct RecallQuery: Sendable {

    /// Embedding vector for semantic nearest-neighbor search on Given.
    public var embedding: [Float]?

    /// Raw SPARQL query to execute directly on the knowledge graph.
    public var sparql: String?

    /// Starting IRI for graph traversal.
    public var anchor: String?

    /// Graph traversal depth (default: 2).
    public var depth: Int

    /// Maximum number of results to return.
    public var limit: Int

    public init(
        embedding: [Float]? = nil,
        sparql: String? = nil,
        anchor: String? = nil,
        depth: Int = 2,
        limit: Int = 10
    ) {
        self.embedding = embedding
        self.sparql = sparql
        self.anchor = anchor
        self.depth = depth
        self.limit = limit
    }
}
