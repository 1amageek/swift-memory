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
    /// Must conform to `Entity` so `Memory.store()` can resolve and dedup them
    /// via embedding similarity. OntologyIndex auto-syncs rdf:type +
    /// @OWLDataProperty triples on insert.
    public var entities: [any Persistable & Entity & Sendable]

    /// Explicit relationship triples beyond what OntologyIndex generates.
    /// e.g. ("Alice", "ex:worksAt", "Acme") — inter-entity relationships.
    public var statements: [StatementRecord]

    public static let empty = MemoryBatch(entities: [], statements: [])

    public init(
        entities: [any Persistable & Entity & Sendable] = [],
        statements: [StatementRecord] = []
    ) {
        self.entities = entities
        self.statements = statements
    }

    // MARK: - Builder Methods

    /// Add a typed @OWLClass entity.
    public mutating func entity(_ entity: some Persistable & Entity & Sendable) {
        entities.append(entity)
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
        MemoryBatch(
            entities: entities + other.entities,
            statements: statements + other.statements
        )
    }
}

// MARK: - MemoryBatchConvertible

extension MemoryBatch: MemoryBatchConvertible {
    public func toBatch() -> MemoryBatch { self }
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
