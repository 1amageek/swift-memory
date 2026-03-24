// GivenContainer.swift
// Collects raw materials during MemoryEncodable encoding

import Foundation
import Synchronization

/// Container for collecting Given materials during encoding.
///
/// Thread-safe via Mutex. Used by MemoryEncodable.encode(to:)
/// to submit raw materials (text, image refs, audio refs).
public final class GivenContainer: Sendable {

    /// Raw material submitted during encoding. Not yet persisted.
    public struct Material: Sendable {
        public var text: String
        public var modality: String
        public var source: String
    }

    private let state = Mutex<[Material]>([])

    /// Encode text content.
    public func encode(_ text: String, modality: String = "text", source: String = "text") {
        state.withLock { $0.append(Material(text: text, modality: modality, source: source)) }
    }

    /// Encode an image reference.
    public func encode(imageRef: String, source: String) {
        state.withLock { $0.append(Material(text: imageRef, modality: "image", source: source)) }
    }

    /// Encode an audio reference.
    public func encode(audioRef: String, source: String) {
        state.withLock { $0.append(Material(text: audioRef, modality: "audio", source: source)) }
    }

    /// Collect all submitted materials. Clears the container.
    func collectMaterials() -> [Material] {
        state.withLock {
            let result = $0
            $0.removeAll()
            return result
        }
    }
}
