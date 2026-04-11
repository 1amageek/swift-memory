// EmbeddingProvider.swift
// Protocol for text embedding generation

/// Abstraction for generating vector embeddings from text.
///
/// Implementations wrap specific ML backends (MLX, CoreML, etc.)
/// without leaking framework dependencies into the memory layer.
public protocol EmbeddingProvider: Sendable {

    /// Embedding vector dimensionality.
    var dimensions: Int { get }

    /// Generate a normalized embedding vector for a single text input.
    func embed(_ text: String) async throws -> [Float]
}
