// MemoryBatch.swift
// Atomic unit produced by MemoryEncoding — fully Codable for LLM JSON output

import Foundation

/// The result of encoding input — Givens, Entities, and Statements.
///
/// Fully `Codable` so it can be decoded directly from LLM JSON output.
/// `Memory` converts these records into `@Persistable` objects and
/// RDF triples during persistence.
public struct MemoryBatch: Sendable, Codable {

    /// Raw sensory materials.
    public var givens: [GivenRecord]

    /// Entity records (type + name + properties).
    /// Memory converts these to @OWLClass records + rdf:type/rdfs:label triples.
    public var entities: [EntityRecord]

    /// Relationship triples (subject, predicate, object).
    public var statements: [StatementRecord]

    public static let empty = MemoryBatch(givens: [], entities: [], statements: [])

    public init(
        givens: [GivenRecord] = [],
        entities: [EntityRecord] = [],
        statements: [StatementRecord] = []
    ) {
        self.givens = givens
        self.entities = entities
        self.statements = statements
    }

    // MARK: - Builder Methods

    /// Add raw text as Given material.
    public mutating func given(_ text: String, source: String = "text") {
        givens.append(GivenRecord(text: text, source: source))
    }

    /// Add an entity.
    public mutating func entity(
        type: String,
        name: String,
        properties: [String: String] = [:]
    ) {
        entities.append(EntityRecord(type: type, name: name, properties: properties))
    }

    /// Add a relationship triple.
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
            givens: givens + other.givens,
            entities: entities + other.entities,
            statements: statements + other.statements
        )
    }
}

// MARK: - Records

/// Raw sensory material record.
public struct GivenRecord: Sendable, Codable, Hashable {
    /// Text content.
    public var text: String
    /// Source identifier (e.g. "chat", "mail", "file").
    public var source: String

    public init(text: String, source: String = "text") {
        self.text = text
        self.source = source
    }
}

/// Entity record — describes an entity to create or update.
///
/// LLM outputs this directly:
/// ```json
/// {"type": "Person", "name": "Alice", "properties": {"email": "alice@acme.com"}}
/// ```
public struct EntityRecord: Sendable, Codable, Hashable {
    /// OWL class name (e.g. "Person", "Organization").
    public var type: String
    /// Entity display name (becomes rdfs:label).
    public var name: String
    /// Additional properties as key-value pairs (e.g. {"email": "alice@acme.com"}).
    public var properties: [String: String]

    public init(type: String, name: String, properties: [String: String] = [:]) {
        self.type = type
        self.name = name
        self.properties = properties
    }
}

/// Relationship triple record.
///
/// LLM outputs this directly:
/// ```json
/// {"subject": "Alice", "predicate": "ex:worksAt", "object": "Acme Corp"}
/// ```
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
