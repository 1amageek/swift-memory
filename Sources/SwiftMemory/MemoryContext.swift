// MemoryContext.swift
// Context for Memory operations

import Database

/// Context providing FDB access for Memory operations.
public struct MemoryContext: Sendable {

    /// FDB context for persistence operations.
    public let fdbContext: FDBContext

    /// Named graph for this memory instance.
    public let graphName: String

    /// Optional embedding provider for vector-based recall.
    public let embeddingProvider: (any EmbeddingProvider)?

    /// Default ontology IRI prefix.
    public static let ontologyIRI = "memory:"

    /// Generate ontology IRI for a specific graph.
    public static func ontologyIRI(for graph: String) -> String {
        "memory:\(graph)"
    }

    public init(
        fdbContext: FDBContext,
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil
    ) {
        self.fdbContext = fdbContext
        self.graphName = graphName
        self.embeddingProvider = embeddingProvider
    }
}

/// Memory-specific errors.
public enum MemoryError: Error, Sendable {
    case recallFailed(String)
    case invalidQuery(String)

    /// Thrown when `store()` is called with entities but no embedding provider
    /// has been configured. Stored entities need embeddings for later vector
    /// resolve and recall paths.
    case embeddingProviderRequired

    /// Thrown when an embedding provider returns fewer or more vectors than
    /// requested by a batch call.
    case embeddingBatchCountMismatch(expected: Int, actual: Int)

    /// Thrown when an embedding vector cannot be written to the configured
    /// vector index because its dimension differs from the schema.
    case embeddingDimensionMismatch(expected: Int, actual: Int)

    /// WASI builds do not include SQLite file storage. Provide a custom
    /// `StorageEngine` when durable host storage is required.
    case pathBackedStorageUnavailableOnWASI
}
