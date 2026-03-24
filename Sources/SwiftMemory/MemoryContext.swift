// MemoryContext.swift
// Context for Memory operations

import Database

/// Context providing FDB access for Memory operations.
public struct MemoryContext: Sendable {

    /// FDB context for persistence operations.
    public let fdbContext: FDBContext

    /// Named graph for this memory instance.
    public let graphName: String

    /// Default ontology IRI prefix.
    public static let ontologyIRI = "memory:"

    /// Generate ontology IRI for a specific graph.
    public static func ontologyIRI(for graph: String) -> String {
        "memory:\(graph)"
    }

    public init(
        fdbContext: FDBContext,
        graphName: String = "memory:default"
    ) {
        self.fdbContext = fdbContext
        self.graphName = graphName
    }
}

/// Memory-specific errors.
public enum MemoryError: Error, Sendable {
    case recallFailed(String)
    case invalidQuery(String)
}
