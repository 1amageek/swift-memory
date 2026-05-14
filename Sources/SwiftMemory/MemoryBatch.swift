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
    /// Must conform to `Entity` so `Memory.store()` can embed and persist them.
    /// Store also writes recall identity statements for rdf:type and rdfs:label
    /// under the inserted entity ID.
    public var entities: [any Persistable & Entity & Sendable]

    /// Explicit relationship triples beyond what OntologyIndex generates.
    /// e.g. ("Alice", "ex:worksAt", "Acme") — inter-entity relationships.
    public var statements: [StatementRecord]

    /// Human-facing endpoint aliases for entities in this batch.
    ///
    /// Keys are labels or names that an interpreting agent may use in a
    /// relationship endpoint. Values are entity assertions or explicit IDs.
    /// Store-time canonicalization rewrites matching endpoints to the inserted
    /// entity ID. Non-matching endpoints remain loose graph terms.
    public var aliases: [String: String]

    public static let empty = MemoryBatch(entities: [], statements: [])

    public init(
        entities: [any Persistable & Entity & Sendable] = [],
        statements: [StatementRecord] = [],
        aliases: [String: String] = [:]
    ) {
        self.entities = entities
        self.statements = statements
        self.aliases = aliases
    }

    // MARK: - Builder Methods

    /// Add a typed @OWLClass entity.
    public mutating func entity(_ entity: some Persistable & Entity & Sendable) {
        entities.append(entity)
    }

    /// Add an explicit relationship triple.
    ///
    /// Endpoints remain loose graph terms unless they match a resolved entity
    /// ID, assertion, or registered alias during `Memory.store()`.
    public mutating func triple(
        _ subject: String,
        _ predicate: String,
        _ object: String
    ) {
        statements.append(StatementRecord(subject: subject, predicate: predicate, object: object))
    }

    /// Register a human-facing alias for an entity assertion or ID.
    public mutating func alias(_ alias: String, for target: String) {
        aliases[alias] = target
    }

    // MARK: - Merge

    public func merging(_ other: MemoryBatch) -> MemoryBatch {
        MemoryBatch(
            entities: entities + other.entities,
            statements: statements + other.statements,
            aliases: aliases.merging(other.aliases) { _, new in new }
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
