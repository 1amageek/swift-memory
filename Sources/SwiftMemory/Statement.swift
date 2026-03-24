// Statement.swift
// RDF Triple persistence model (adapted from AURORA)

import Foundation
import Database

/// An RDF triple stored in the knowledge graph.
///
/// Named `Statement` to avoid conflict with `Hoot.RDFTriple`.
/// Adapted from AURORA's RDFTriple with memory-specific directory and graph defaults.
@Persistable
public struct Statement: Hashable {

    #Directory<Statement>("memory", "triples")

    #Index(GraphIndexKind<Statement>(
        from: \.subject,
        edge: \.predicate,
        to: \.object,
        graph: \.graph,
        strategy: .tripleStore
    ))

    /// Unique identifier.
    public var id: String = UUID().uuidString

    /// Named graph IRI.
    public var graph: String = "memory:default"

    /// Subject IRI.
    public var subject: String = ""

    /// Predicate IRI.
    public var predicate: String = ""

    /// Object IRI or literal value.
    public var object: String = ""
}
