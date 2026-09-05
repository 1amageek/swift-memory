// Entity.swift
// Polymorphic protocol for cross-type entity resolution

import DatabaseKit

/// Polymorphic protocol enabling cross-type entity search and resolution.
///
/// All knowledge entities (Person, Organization, Place, etc.) conform to this protocol.
/// Conforming types share a polymorphic directory and VectorIndex, enabling:
/// - Cross-type similarity search via embedding vectors
/// - Entity resolution: detecting that "Creww" and "Creww Corporation" refer to the same entity
///
/// **Polymorphic Source Model**:
/// - Concrete types (`Person`, `Organization`) are storage units
/// - `Entity` protocol group is the logical source for cross-type queries
/// - Searches go through the shared polymorphic directory, returning `any Persistable`
///
/// **Shared Embedding Invariant**:
/// All conforming types MUST use the same embedding dimensions and metric.
/// The shared VectorIndex `Entity_vector_embedding` spans all conforming types.
/// Changing dimensions or metric requires rebuilding the entire polymorphic index.
///
/// **Class Assertion Embedding**:
/// The `assertion` field is an RDF/Turtle class assertion. The embedding of
/// `assertion` is used only for candidate retrieval; final identity judgment
/// should be made by the caller using returned candidates and graph context.
///
@Polymorphable(identifier: "Entity")
@PolymorphicDirectory("memory", "entities")
@PolymorphicIndex(
    .vector(
        name: "Entity_vector_embedding",
        embedding: "embedding",
        dimensions: 768,
        metric: .cosine
    )
)
public protocol Entity: Polymorphable<EntityPolymorphicGroup>, SecurityPolicy {

    /// Embedding vector dimensionality for the shared Entity index.
    ///
    /// All conforming types registered in the same `Memory` instance MUST use
    /// 768 dimensions, matching the statically compiled polymorphic index.
    /// Registration rejects any override with a different value.
    static var embeddingDimensions: Int { get }

    /// Canonical string identifier used in graph resources and recall output.
    var memoryID: String { get }

    /// Stable semantic type name used when the assertion omits `rdf:type`.
    static var memoryType: String { get }

    /// Human-readable label persisted as `rdfs:label` for recall results.
    ///
    /// Return `nil` when the entity has no stable display label. Memory then
    /// uses the persisted entity identifier instead of inferring a field via
    /// runtime reflection, which is unavailable on Embedded Swift targets.
    var memoryLabel: String? { get }

    /// RDF/Turtle class assertion for candidate retrieval.
    ///
    /// The assertion should not contain identity hints. Use ordinary typed
    /// fields and statements for disambiguating context.
    var assertion: String { get set }

    /// Embedding vector of `assertion`.
    ///
    /// Populated by `Memory.store()` on first insert.
    var embedding: Vector { get set }
}

// MARK: - Shared Constants

extension Entity {
    /// Default embedding dimensions: 768 (EmbeddingGemma 300M native).
    public static var embeddingDimensions: Int { 768 }

    /// Entities opt in to a human-readable label explicitly.
    public var memoryLabel: String? { nil }
}

extension Entity where Self: Persistable, Self.ID == String {
    /// String identifiers are already in Memory's canonical graph domain.
    public var memoryID: String { id }

    /// The statically generated persistable type is stable across platforms.
    public static var memoryType: String { persistableType }
}

extension Entity where Self: Persistable {
    static func persistedEmbeddingField() throws -> Field<Self, Vector> {
        guard let schema = try fieldSchemas.first(where: { $0.name == "embedding" }),
              schema.type == .vector,
              !schema.isOptional,
              !schema.isArray else {
            throw MemoryError.invalidQuery(
                "\(persistableType).embedding is not a required vector field"
            )
        }
        return Field(
            identity: FieldIdentity(
                name: schema.name,
                number: schema.fieldNumber
            ),
            type: schema.type
        )
    }
}
