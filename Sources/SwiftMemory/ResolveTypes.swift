// ResolveTypes.swift
// Input/output types for entity resolution

/// Candidate entity to resolve against existing knowledge.
///
/// The `assertion` is an RDF/Turtle class assertion. Its embedding is used to
/// search the shared polymorphic vector index for candidate entities. The
/// caller should use returned context to make the final identity decision.
public struct ResolveCandidate: Sendable {

    /// RDF/Turtle class assertion for this entity.
    public var assertion: String

    public init(assertion: String) {
        self.assertion = assertion
    }
}

/// One graph statement adjacent to a resolved candidate.
public struct ResolvedContextStatement: Sendable, Codable, Hashable {

    public enum Direction: String, Sendable, Codable, Hashable {
        case outgoing
        case incoming
    }

    public var direction: Direction
    public var subject: String
    public var predicate: String
    public var object: String

    public init(
        direction: Direction,
        subject: String,
        predicate: String,
        object: String
    ) {
        self.direction = direction
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

/// A single persisted entity returned by `resolve` as a possible match.
///
/// The caller is expected to judge whether any of the candidates truly refer
/// to the same entity as the input. To dedupe against a chosen candidate, use
/// its `id` in subsequent statements and omit the duplicate entity from the
/// `store` payload.
public struct ResolvedMatch: Sendable {

    /// Stable ID of the persisted entity.
    public var id: String

    /// Canonical assertion of the persisted entity.
    public var assertion: String

    /// Human-facing label resolved from the graph when available.
    public var label: String

    /// RDF type resolved from the graph when available.
    public var type: String

    /// Cosine similarity to the input candidate (0.0 = unrelated, 1.0 = identical).
    public var similarity: Float

    /// One-hop incoming and outgoing graph context for caller judgment.
    public var context: [ResolvedContextStatement]

    public init(
        id: String,
        assertion: String,
        similarity: Float,
        label: String = "",
        type: String = "",
        context: [ResolvedContextStatement] = []
    ) {
        self.id = id
        self.assertion = assertion
        self.similarity = similarity
        self.label = label
        self.type = type
        self.context = context
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
