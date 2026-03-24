// MemoryBatch.swift
// Atomic unit returned by MemoryEncoder

import Foundation
import Hoot

/// The result of encoding or recalling memory — a set of Givens and Knowledge.
///
/// Written atomically to FDB in a single transaction.
public struct MemoryBatch: Sendable {

    /// Sensory data with embeddings.
    public var givens: [Given]

    /// Structured relationships extracted from givens.
    public var knowledge: [Statement]

    public static let empty = MemoryBatch(givens: [], knowledge: [])

    public init(givens: [Given] = [], knowledge: [Statement] = []) {
        self.givens = givens
        self.knowledge = knowledge
    }

    public func merging(_ other: MemoryBatch) -> MemoryBatch {
        MemoryBatch(
            givens: givens + other.givens,
            knowledge: knowledge + other.knowledge
        )
    }

    /// Convert knowledge to HOOT compact format for LLM context.
    ///
    /// Reduces token count to ~1/3 of Turtle representation.
    public func asHOOT(namespace: String = "http://example.org/") -> String {
        guard !knowledge.isEmpty else { return "" }

        var turtleLines: [String] = []
        turtleLines.append("@prefix ex: <\(namespace)> .")
        turtleLines.append("@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")
        turtleLines.append("@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .")
        turtleLines.append("@prefix owl: <http://www.w3.org/2002/07/owl#> .")
        turtleLines.append("@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .")
        turtleLines.append("")

        for statement in knowledge {
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
