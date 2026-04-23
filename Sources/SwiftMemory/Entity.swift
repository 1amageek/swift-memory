// Entity.swift
// Polymorphic protocol for cross-type entity resolution

import Foundation
import Core
import Vector

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
/// The `assertion` field is a natural-language class assertion identifying the entity
/// (e.g., "Acme Inc is a company that provides cloud infrastructure services").
/// The embedding of `assertion` carries the entity's semantic identity and is what
/// drives cross-type resolution.
///
/// **Storage Layout**:
/// ```
/// [memory/entities]/R/[typeCode]/[id]                                   -> protobuf
/// [memory/entities]/I/Entity_vector_embedding/[vector]/[typeCode]/[id]  -> empty
/// ```
public protocol Entity: Polymorphable {

    /// Embedding vector dimensionality for the shared Entity index.
    ///
    /// All conforming types registered in the same `Memory` instance MUST
    /// agree on this value. A default of 768 is provided (EmbeddingGemma 300M
    /// native dim); override only when substituting an `EmbeddingProvider` whose
    /// output dimensionality differs.
    static var embeddingDimensions: Int { get }

    /// Natural-language class assertion identifying this entity.
    ///
    /// Example: `"Google is a company"`, `"Alice is a person who works at Anthropic"`.
    /// This text is what gets embedded; the embedding carries the entity's semantic
    /// identity for cross-type resolution.
    var assertion: String { get set }

    /// Embedding vector of `assertion`.
    ///
    /// Populated by `Memory.store()` on first insert.
    var embedding: [Float] { get set }
}

// MARK: - Shared Constants

extension Entity {
    /// Default embedding dimensions: 768 (EmbeddingGemma 300M native).
    public static var embeddingDimensions: Int { 768 }
}

// MARK: - Polymorphable Conformance

extension Entity {
    public static var polymorphableType: String { "Entity" }

    public static var polymorphicDirectoryPathComponents: [any DirectoryPathElement] {
        [Path("memory"), Path("entities")]
    }
}

// MARK: - Polymorphic Indexes

extension Entity where Self: Persistable {
    public static var polymorphicIndexDescriptors: [IndexDescriptor] {
        [
            IndexDescriptor(
                name: "Entity_vector_embedding",
                keyPaths: [\Self.embedding],
                kind: VectorIndexKind<Self>(
                    embedding: \Self.embedding,
                    dimensions: embeddingDimensions,
                    metric: .cosine
                )
            )
        ]
    }
}
