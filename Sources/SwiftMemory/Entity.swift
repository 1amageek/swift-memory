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
/// **Storage Layout**:
/// ```
/// [memory/entities]/R/[typeCode]/[id]                                   -> protobuf
/// [memory/entities]/I/Entity_vector_embedding/[vector]/[typeCode]/[id]  -> empty
/// ```
///
/// **Dual-Write Behavior**:
/// Each conforming type writes to both its own directory
/// (e.g., "bob/persons") and the shared polymorphic directory ("memory/entities").
///
/// **Usage**:
/// ```swift
/// @Persistable @OWLClass("ex:Person")
/// struct Person: Entity {
///     #Directory<Person>("bob", "persons")
///     var id: String = ULID().ulidString
///     var name: String
///     var embedding: [Float] = []
///     var label: String { name }
/// }
/// ```
public protocol Entity: Polymorphable {

    /// Canonical label used for entity resolution.
    ///
    /// Typically the entity's primary name (e.g., person name, organization name).
    /// Used to construct the embedding text and as the resolved label.
    var label: String { get }

    /// Entity class key (e.g., "organizations", "persons").
    ///
    /// Used as the first token of the embedding text and for class-level
    /// pre-filtering during resolution.
    var entityType: String { get }

    /// Additional discriminating context appended to the embedding text.
    ///
    /// Override to include properties that help distinguish entities with
    /// similar names (domain, email, role, etc.). Default is empty.
    var resolutionContext: String { get }

    /// Embedding vector for similarity-based entity resolution.
    ///
    /// Generated from `resolutionEmbeddingText`. Populated by `Memory.store()`
    /// on first insert.
    var embedding: [Float] { get set }

    /// Creation timestamp. Set on first insert.
    var created: Date { get set }

    /// Last update timestamp. Refreshed when a resolution match is detected.
    var updated: Date { get set }
}

// MARK: - Shared Constants

extension Entity {
    /// Embedding vector dimensions for the shared Entity index.
    ///
    /// This is the single source of truth for Entity embedding dimensions.
    /// All conforming types must produce embeddings of this size.
    /// Mismatch causes index corruption.
    public static var embeddingDimensions: Int { 256 }
}

// MARK: - Defaults

extension Entity {

    /// Default: no additional context.
    public var resolutionContext: String { "" }

    /// Text used to compute the entity's embedding vector.
    ///
    /// Format: `"{entityType} {label}"` or `"{entityType} {label} {context}"`
    /// depending on whether `resolutionContext` is empty.
    public var resolutionEmbeddingText: String {
        let trimmedContext = resolutionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContext.isEmpty {
            return "\(entityType) \(label)"
        }
        return "\(entityType) \(label) \(trimmedContext)"
    }
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
