// GivenRepresentable.swift
// Types that can present themselves as raw sensory input for Memory

import Foundation

/// Raw sensory content for Memory — multimodal (text, image, audio).
///
/// Same pattern as Prompt: a sequence of typed components.
public struct GivenContent: Sendable, Equatable {

    public struct Text: Sendable, Equatable {
        public let value: String

        public init(value: String) {
            self.value = value
        }
    }

    public struct Image: Sendable, Equatable {
        public enum Source: Sendable, Equatable {
            case base64(data: String, mediaType: String)
            case url(URL)
        }
        public let source: Source

        public init(source: Source) {
            self.source = source
        }
    }

    public struct Audio: Sendable, Equatable {
        public enum Source: Sendable, Equatable {
            case base64(data: String, format: String)
            case url(URL)
        }
        public let source: Source

        public init(source: Source) {
            self.source = source
        }
    }

    public enum Component: Sendable, Equatable {
        case text(Text)
        case image(Image)
        case audio(Audio)
    }

    public let components: [Component]

    public init(_ content: String) {
        self.components = [.text(Text(value: content))]
    }

    public init(components: [Component]) {
        self.components = components
    }

    public init(@GivenBuilder _ content: () throws -> GivenContent) rethrows {
        let built = try content()
        self.components = built.components
    }

    public var givenRepresentation: GivenContent {
        return self
    }
}

/// A type that can present itself as raw sensory input for Memory.
public protocol GivenRepresentable: Sendable {
    var givenRepresentation: GivenContent { get }
}

// MARK: - Conformances

extension GivenContent: GivenRepresentable {}

extension String: GivenRepresentable {
    public var givenRepresentation: GivenContent {
        GivenContent(self)
    }
}

extension URL: GivenRepresentable {
    public var givenRepresentation: GivenContent {
        GivenContent(absoluteString)
    }
}
