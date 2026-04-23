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

/// A single persisted entity returned by `resolve` as a possible match.
///
/// The caller (typically an LLM) is expected to judge whether any of the
/// candidates truly refer to the same entity as the input. To dedupe against
/// a chosen candidate, copy its `assertion` **verbatim** into the subsequent
/// `store` payload — identical assertion text produces an identical embedding
/// which the store-time safety net will collapse into the existing record.
public struct ResolvedMatch: Sendable {

    /// Stable ID of the persisted entity.
    public var id: String

    /// Canonical assertion of the persisted entity.
    public var assertion: String

    /// Cosine similarity to the input candidate (0.0 = unrelated, 1.0 = identical).
    public var similarity: Float

    public init(id: String, assertion: String, similarity: Float) {
        self.id = id
        self.assertion = assertion
        self.similarity = similarity
    }
}

/// Result of resolving a single candidate against existing entities.
///
/// `candidates` lists persisted entities whose similarity to the input
/// assertion exceeds the resolve threshold, sorted by similarity in
/// descending order and capped to the resolve limit. An empty list means
/// no persisted entity cleared the threshold — the caller can treat the
/// input as a new entity.
public struct ResolvedEntity: Sendable {

    /// Original candidate assertion.
    public var inputAssertion: String

    /// Candidates above the threshold, sorted by similarity descending.
    public var candidates: [ResolvedMatch]

    public init(inputAssertion: String, candidates: [ResolvedMatch] = []) {
        self.inputAssertion = inputAssertion
        self.candidates = candidates
    }

    /// Whether any candidate above the threshold was found.
    public var hasCandidates: Bool { !candidates.isEmpty }

    /// Top candidate ID (highest similarity), if any.
    public var topID: String? { candidates.first?.id }

    /// Top candidate similarity, if any.
    public var topSimilarity: Float? { candidates.first?.similarity }
}
