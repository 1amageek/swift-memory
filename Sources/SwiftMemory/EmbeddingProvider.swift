// EmbeddingProvider.swift
// Protocol for text embedding generation

import Foundation

/// Abstraction for generating vector embeddings from text.
///
/// Implementations wrap specific ML backends (MLX, CoreML, etc.)
/// without leaking framework dependencies into the memory layer.
public protocol EmbeddingProvider: Sendable {

    /// Embedding vector dimensionality.
    var dimensions: Int { get }

    /// Generate a normalized embedding vector for a single text input.
    func embed(_ text: String) async throws -> [Float]

    /// Generate normalized embedding vectors for multiple text inputs.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

public extension EmbeddingProvider {
    func embed(_ texts: [String]) async throws -> [[Float]] {
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for text in texts {
            vectors.append(try await embed(text))
        }
        return vectors
    }
}

/// Embedding provider backed by a host-supplied async function.
///
/// WASM hosts such as browsers and Cloudflare Workers should keep platform
/// APIs on the host side, then inject embeddings through this provider.
public actor HostEmbeddingProvider: EmbeddingProvider {
    public typealias Embed = @Sendable (String) async throws -> [Float]
    public typealias EmbedBatch = @Sendable ([String]) async throws -> [[Float]]

    public nonisolated let dimensions: Int

    private let normalizesOutput: Bool
    private let embedBatch: EmbedBatch

    public init(
        dimensions: Int = Given.embeddingDimensions,
        normalizesOutput: Bool = true,
        embed: @escaping Embed
    ) {
        self.dimensions = dimensions
        self.normalizesOutput = normalizesOutput
        self.embedBatch = { texts in
            var vectors: [[Float]] = []
            vectors.reserveCapacity(texts.count)
            for text in texts {
                vectors.append(try await embed(text))
            }
            return vectors
        }
    }

    public init(
        dimensions: Int = Given.embeddingDimensions,
        normalizesOutput: Bool = true,
        embedBatch: @escaping EmbedBatch
    ) {
        self.dimensions = dimensions
        self.normalizesOutput = normalizesOutput
        self.embedBatch = embedBatch
    }

    public func embed(_ text: String) async throws -> [Float] {
        let vectors = try await embed([text])
        guard let vector = vectors.first else {
            throw HostEmbeddingProviderError.invalidBatchCount(expected: 1, actual: 0)
        }
        return vector
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        try validate(texts)
        let vectors = try await embedBatch(texts)
        guard vectors.count == texts.count else {
            throw HostEmbeddingProviderError.invalidBatchCount(
                expected: texts.count,
                actual: vectors.count
            )
        }
        return try vectors.map { vector in
            try Self.preparedVector(
                vector,
                dimensions: dimensions,
                normalizesOutput: normalizesOutput
            )
        }
    }

    private func validate(_ texts: [String]) throws {
        for text in texts {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw HostEmbeddingProviderError.emptyText
            }
        }
    }

    private static func preparedVector(
        _ vector: [Float],
        dimensions: Int,
        normalizesOutput: Bool
    ) throws -> [Float] {
        guard vector.count == dimensions else {
            throw HostEmbeddingProviderError.invalidDimensions(
                expected: dimensions,
                actual: vector.count
            )
        }
        guard normalizesOutput else {
            return vector
        }

        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else {
            throw HostEmbeddingProviderError.zeroVector
        }
        return vector.map { $0 / norm }
    }
}

public enum HostEmbeddingProviderError: Error, Sendable, Equatable {
    case emptyText
    case invalidBatchCount(expected: Int, actual: Int)
    case invalidDimensions(expected: Int, actual: Int)
    case zeroVector
}
