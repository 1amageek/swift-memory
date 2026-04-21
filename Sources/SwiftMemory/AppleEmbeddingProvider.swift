// AppleEmbeddingProvider.swift
// EmbeddingProvider backed by Apple's NLContextualEmbedding.

import Foundation
import NaturalLanguage

/// Errors thrown by `AppleEmbeddingProvider`.
public enum AppleEmbeddingError: Error, Sendable {
    /// No contextual embedding model is available for the requested language.
    case unsupportedLanguage(NLLanguage)
    /// Model assets could not be located or downloaded on-device.
    case assetsUnavailable(NLContextualEmbedding.AssetsResult)
    /// The input text is empty after trimming whitespace.
    case emptyInput
    /// The model produced zero token vectors for the input.
    case noTokens
    /// The aggregated embedding has zero magnitude and cannot be normalized.
    case zeroVector
}

/// EmbeddingProvider backed by `NLContextualEmbedding`.
///
/// Wraps `NLContextualEmbedding` to compute contextual transformer embeddings
/// locally. Per-token vectors are mean-pooled and L2-normalized to produce a
/// single vector per input string, matching the shape expected by
/// `Entity`'s vector index.
///
/// - Important: The embedding model is downloaded on first use. Construction
///   may take several seconds and requires network access if assets are
///   not yet cached on-device.
public actor AppleEmbeddingProvider: EmbeddingProvider {

    /// Embedding vector dimensionality produced by the underlying model.
    public nonisolated let dimensions: Int

    private let embedding: NLContextualEmbedding
    private let language: NLLanguage

    /// Creates a provider for the specified language and loads the model.
    ///
    /// Ensures model assets are present (downloading if needed) and calls
    /// `load()` before returning so that subsequent `embed(_:)` calls do not
    /// pay the first-load cost.
    ///
    /// - Parameter language: Source language for the embedding model.
    ///   Defaults to `.english`.
    public init(language: NLLanguage = .english) async throws {
        guard let model = NLContextualEmbedding(language: language) else {
            throw AppleEmbeddingError.unsupportedLanguage(language)
        }

        if !model.hasAvailableAssets {
            let result = try await model.requestAssets()
            guard result == .available else {
                throw AppleEmbeddingError.assetsUnavailable(result)
            }
        }

        try model.load()

        self.embedding = model
        self.language = language
        self.dimensions = model.dimension
    }

    public func embed(_ text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppleEmbeddingError.emptyInput
        }

        let result = try embedding.embeddingResult(for: trimmed, language: language)

        var sum = [Double](repeating: 0, count: dimensions)
        var count = 0

        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            let n = min(vector.count, sum.count)
            for i in 0..<n {
                sum[i] += vector[i]
            }
            count += 1
            return true
        }

        guard count > 0 else {
            throw AppleEmbeddingError.noTokens
        }

        let inv = 1.0 / Double(count)
        var mean = sum.map { Float($0 * inv) }

        var squaredNorm: Float = 0
        for value in mean {
            squaredNorm += value * value
        }
        let norm = squaredNorm.squareRoot()
        guard norm > 0 else {
            throw AppleEmbeddingError.zeroVector
        }

        for i in 0..<mean.count {
            mean[i] /= norm
        }
        return mean
    }
}
