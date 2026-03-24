// GivenEncodingContainer.swift
// Container for submitting materials to Given Store

import Synchronization

/// A raw material submitted for Given generation.
public struct RawMaterial: Sendable {
    /// Input modality: "text", "image", "audio".
    public var modality: String

    /// Text content or reference string.
    public var payload: String

    /// Identifier of the input source.
    public var source: String

    public init(modality: String, payload: String, source: String) {
        self.modality = modality
        self.payload = payload
        self.source = source
    }
}

/// Container that collects raw materials for the Given Store.
///
/// `MemoryEncodable` types submit their sensory content here.
/// The `MemoryEncoding` implementation later processes these materials
/// into `Given` objects (e.g., computing embeddings).
public final class GivenEncodingContainer: Sendable {

    private let materials: Mutex<[RawMaterial]> = Mutex([])

    public init() {}

    /// Submit text content.
    public func encode(_ text: String, source: String) {
        materials.withLock { $0.append(RawMaterial(modality: "text", payload: text, source: source)) }
    }

    /// Submit an image reference.
    public func encode(imageRef: String, source: String) {
        materials.withLock { $0.append(RawMaterial(modality: "image", payload: imageRef, source: source)) }
    }

    /// Submit an audio reference.
    public func encode(audioRef: String, format: String, source: String) {
        materials.withLock { $0.append(RawMaterial(modality: "audio", payload: audioRef, source: "\(source):\(format)")) }
    }

    /// Collect all submitted materials.
    public func collectMaterials() -> [RawMaterial] {
        materials.withLock { $0 }
    }
}
