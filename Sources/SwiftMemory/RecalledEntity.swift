// RecalledEntity.swift
// A single entity recalled via spreading activation

/// An entity recalled from the knowledge graph with convergence score.
///
/// Score represents how many independent paths reached this entity
/// during spreading activation. Higher score = more converging associations.
/// Paths provide human-readable explanations of WHY this entity was recalled.
public struct RecalledEntity: Sendable {

    /// Entity IRI.
    public let iri: String

    /// Human-readable label (from rdfs:label).
    public let label: String

    /// Entity type (from rdf:type).
    public let type: String

    /// Activation count — how many paths converged on this entity.
    public let score: Int

    /// Human-readable traversal paths explaining the recall.
    ///
    /// Example: `["ex:Alice --[ex:worksAt]--> ex:Acme"]`
    public let paths: [String]

    public init(iri: String, label: String, type: String, score: Int, paths: [String]) {
        self.iri = iri
        self.label = label
        self.type = type
        self.score = score
        self.paths = paths
    }
}
