// ResolveTypes.swift
// Input/output types for entity resolution

/// Candidate entity to resolve against existing knowledge.
///
/// The embedding text is constructed as: "{type} {label} {context}".
/// This triple-based approach enables:
/// - Same label, different type: "Organization Apple" != "Food Apple"
/// - Different label, same entity: "Creww" ≈ "Creww Corporation"
public struct ResolveCandidate: Sendable {

    /// Entity type key (e.g., "organizations", "persons").
    public var type: String

    /// Entity name to resolve.
    public var label: String

    /// Additional discriminating properties (domain, email, etc.).
    /// Empty string if no extra context is available.
    public var context: String

    public init(type: String, label: String, context: String = "") {
        self.type = type
        self.label = label
        self.context = context
    }

    /// Embedding text constructed from the triple.
    public var embeddingText: String {
        context.isEmpty ? "\(type) \(label)" : "\(type) \(label) \(context)"
    }
}

/// Result of resolving a single candidate against existing entities.
public struct ResolvedEntity: Sendable {

    /// Original candidate label.
    public var inputLabel: String

    /// Original candidate type.
    public var inputType: String

    /// Stable ID of the matched existing entity (nil if no match).
    public var matchedID: String?

    /// Canonical label of the matched entity (nil if no match).
    public var matchedLabel: String?

    /// Similarity score (0.0 = no match, 1.0 = identical).
    public var similarity: Float

    public init(
        inputLabel: String,
        inputType: String,
        matchedID: String? = nil,
        matchedLabel: String? = nil,
        similarity: Float = 0
    ) {
        self.inputLabel = inputLabel
        self.inputType = inputType
        self.matchedID = matchedID
        self.matchedLabel = matchedLabel
        self.similarity = similarity
    }

    /// Whether this candidate resolved to an existing entity.
    public var isResolved: Bool { matchedID != nil }
}
