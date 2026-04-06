// MemoryBatch.swift
// Result of MemoryEncoding interpretation

import Foundation
import Database

/// The result of MemoryEncoding interpretation.
///
/// Contains typed @OWLClass entities and explicit relationship statements.
/// NOT Codable — MemoryEncoding implementation handles JSON decode internally.
public struct MemoryBatch: Sendable {

    /// Typed @OWLClass entities to insert.
    /// OntologyIndex auto-syncs rdf:type + @OWLDataProperty triples on insert.
    public var entities: [any Persistable & Sendable]

    /// Entity IDs collected during `entity()` calls.
    /// Used by `Memory.store()` to create Trace records.
    public var entityIDs: [String]

    /// Explicit relationship triples beyond what OntologyIndex generates.
    /// e.g. ("Alice", "ex:worksAt", "Acme") — inter-entity relationships.
    public var statements: [StatementRecord]

    public static let empty = MemoryBatch(entities: [], statements: [])

    public init(
        entities: [any Persistable & Sendable] = [],
        statements: [StatementRecord] = []
    ) {
        self.entities = entities
        self.entityIDs = []
        self.statements = statements
    }

    // MARK: - Builder Methods

    /// Add a typed @OWLClass entity.
    public mutating func entity(_ entity: some Persistable & Sendable) {
        entities.append(entity)
        entityIDs.append("\(entity.id)")
    }

    /// Add an explicit relationship triple.
    public mutating func triple(
        _ subject: String,
        _ predicate: String,
        _ object: String
    ) {
        statements.append(StatementRecord(subject: subject, predicate: predicate, object: object))
    }

    // MARK: - Merge

    public func merging(_ other: MemoryBatch) -> MemoryBatch {
        var merged = MemoryBatch(
            entities: entities + other.entities,
            statements: statements + other.statements
        )
        merged.entityIDs = entityIDs + other.entityIDs
        return merged
    }
}

// MARK: - Statement Record

/// Explicit relationship triple (subject, predicate, object).
///
/// Used for inter-entity relationships that OntologyIndex
/// does not auto-generate (e.g. "Alice worksAt Acme").
public struct StatementRecord: Sendable, Codable, Hashable {
    public var subject: String
    public var predicate: String
    public var object: String

    public init(subject: String, predicate: String, object: String) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}
