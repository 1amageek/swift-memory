// EntityEmbeddingEntry.swift
// Type-erased entry for updating entity embeddings

import Database

/// Entry describing an entity whose embedding needs to be updated.
///
/// Created by the MCP layer (which knows concrete types) and passed to
/// `Memory.updateEntityEmbeddings()` (which only needs the embedding text
/// and a closure to apply the result).
public struct EntityEmbeddingEntry: Sendable {

    /// Entity type key (e.g., "organizations").
    public let entityType: String

    /// Canonical label.
    public let label: String

    /// Additional context for disambiguation (domain, email, etc.).
    public let context: String

    /// Closure that fetches the entity by ID, sets its embedding, and inserts it.
    /// The FDBContext is passed in so the closure can fetch + insert.
    public let applyEmbedding: @Sendable ([Float], FDBContext) async throws -> Void

    /// Text used to generate the embedding vector.
    public var embeddingText: String {
        context.isEmpty ? "\(entityType) \(label)" : "\(entityType) \(label) \(context)"
    }

    public init(
        entityType: String,
        label: String,
        context: String = "",
        applyEmbedding: @escaping @Sendable ([Float], FDBContext) async throws -> Void
    ) {
        self.entityType = entityType
        self.label = label
        self.context = context
        self.applyEmbedding = applyEmbedding
    }
}
