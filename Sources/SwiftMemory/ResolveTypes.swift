// ResolveTypes.swift
// Input/output types for entity resolution

/// Candidate entity to resolve against existing knowledge.
///
/// The `assertion` is a natural-language class assertion that identifies the
/// entity (e.g., "Alice is a person who works at Acme"). Its embedding is the
/// key used to search the shared polymorphic vector index.
public struct ResolveCandidate: Sendable {

    /// Natural-language class assertion identifying this entity.
    public var assertion: String

    public init(assertion: String) {
        self.assertion = assertion
    }
}

/// Result of resolving a single candidate against existing entities.
public struct ResolvedEntity: Sendable {

    /// Original candidate assertion.
    public var inputAssertion: String

    /// Stable ID of the matched existing entity (nil if no match).
    public var matchedID: String?

    /// Canonical assertion of the matched entity (nil if no match).
    public var matchedAssertion: String?

    /// Similarity score (0.0 = no match, 1.0 = identical).
    public var similarity: Float

    public init(
        inputAssertion: String,
        matchedID: String? = nil,
        matchedAssertion: String? = nil,
        similarity: Float = 0
    ) {
        self.inputAssertion = inputAssertion
        self.matchedID = matchedID
        self.matchedAssertion = matchedAssertion
        self.similarity = similarity
    }

    /// Whether this candidate resolved to an existing entity.
    public var isResolved: Bool { matchedID != nil }
}
