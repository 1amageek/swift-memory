// Memorable.swift
// Protocol for types that can be stored as Given

import Foundation

/// A type that can be stored as raw sensory data (Given) in Memory.
///
/// Memorable types represent the raw material before interpretation:
/// text, images, audio, or any data that was "given" to a memory pipeline.
///
/// Given is only saved when the caller extracts knowledge worth preserving.
/// If nothing is extracted, the Given is discarded.
public protocol Memorable: Sendable {
    /// The modality of this content ("text", "image", "audio", etc.)
    var modality: String { get }

    /// The payload as a string reference (inline text, URL, or base64).
    var payloadRef: String { get }
}

// MARK: - Default Conformances

extension String: Memorable {
    public var modality: String { "text" }
    public var payloadRef: String { self }
}

extension Data: Memorable {
    public var modality: String { "data" }
    public var payloadRef: String { base64EncodedString() }
}

extension URL: Memorable {
    public var modality: String { "url" }
    public var payloadRef: String { absoluteString }
}
