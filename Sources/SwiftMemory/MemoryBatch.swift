// MemoryBatch.swift
// Atomic unit produced by MemoryEncoding

import Foundation
import Database
import Hoot

/// The result of encoding input — a set of Givens, Entities, and Statements.
///
/// Written atomically to the database in a single transaction.
/// Memory handles deduplication: entities with matching label + type
/// are updated instead of duplicated.
public struct MemoryBatch: Sendable {

    /// Raw sensory data with embeddings.
    public var givens: [Given]

    /// Typed @OWLClass entity records.
    public var entities: [any Persistable]

    /// RDF triples (relationships between entities).
    public var statements: [Statement]

    public static let empty = MemoryBatch(givens: [], entities: [], statements: [])

    public init(
        givens: [Given] = [],
        entities: [any Persistable] = [],
        statements: [Statement] = []
    ) {
        self.givens = givens
        self.entities = entities
        self.statements = statements
    }

    // MARK: - Builder Methods

    /// Add raw text as Given material.
    public mutating func given(_ text: String, source: String) {
        givens.append(Given(
            modality: "text",
            payloadRef: text,
            embedding: [],
            timestamp: Date(),
            source: source
        ))
    }

    /// Add an @OWLClass entity.
    /// Memory will check for existing entity and upsert automatically.
    public mutating func entity(_ entity: some Persistable) {
        entities.append(entity)
    }

    /// Add a relationship triple.
    /// Graph name is filled by Memory on persist.
    public mutating func triple(
        _ subject: String,
        _ predicate: String,
        _ object: String
    ) {
        statements.append(Statement(
            graph: "",
            subject: subject,
            predicate: predicate,
            object: object
        ))
    }

    // MARK: - Merge

    public func merging(_ other: MemoryBatch) -> MemoryBatch {
        MemoryBatch(
            givens: givens + other.givens,
            entities: entities + other.entities,
            statements: statements + other.statements
        )
    }

    // MARK: - HOOT Export

    /// Convert statements to HOOT compact format for LLM context.
    public func asHOOT(namespace: String = "http://example.org/") -> String {
        guard !statements.isEmpty else { return "" }

        var turtleLines: [String] = []
        turtleLines.append("@prefix ex: <\(namespace)> .")
        turtleLines.append("@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")
        turtleLines.append("@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .")
        turtleLines.append("@prefix owl: <http://www.w3.org/2002/07/owl#> .")
        turtleLines.append("@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .")
        turtleLines.append("")

        for statement in statements {
            turtleLines.append("\(statement.subject) \(statement.predicate) \(statement.object) .")
        }

        let turtle = turtleLines.joined(separator: "\n")

        let parser = TurtleParser()
        do {
            let turtleDoc = try parser.parse(turtle)
            let hootDoc = HootCompiler().compile(turtleDoc)
            return HootEncoder(mode: .compact).encode(hootDoc)
        } catch {
            return turtle
        }
    }
}
