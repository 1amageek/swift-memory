// Statement.swift
// RDF Triple persistence model

import DatabaseKit

/// An RDF triple stored in the knowledge graph.
///
/// Named `Statement` to avoid conflict with `Hoot.RDFTriple`.
@Persistable
public struct Statement: Hashable {

    #Directory<Statement>("memory", "triples")

    #Index(
        .graph(
            name: "Statement_graph_subject_predicate_object_graph",
            definition: .rdf(
                subject: \Statement.subject,
                predicate: \Statement.predicate,
                object: \Statement.object,
                graph: \Statement.graph
            )
        )
    )

    /// Unique identifier.
    public var id: String = ""

    /// Named graph IRI.
    public var graph: RDFTerm = .iri(.xsdString)

    /// Subject IRI.
    public var subject: RDFTerm = .iri(.xsdString)

    /// Predicate IRI.
    public var predicate: RDFTerm = .iri(.xsdString)

    /// Object IRI or literal value.
    public var object: RDFTerm = .iri(.xsdString)

    /// Generate a content-addressable ID from triple components.
    ///
    /// Same triple content always produces the same ID,
    /// enabling upsert semantics and deduplication.
    public static func contentID(
        graph: String, subject: String, predicate: String, object: String
    ) -> String {
        "\(graph)|\(subject)|\(predicate)|\(object)"
    }
}

extension Statement: SecurityPolicy {
    public static func permitsRead(
        of resource: borrowing Statement,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsCreate(
        _ newResource: borrowing Statement,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsUpdate(
        from resource: borrowing Statement,
        to newResource: borrowing Statement,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsDelete(
        _ resource: borrowing Statement,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }
}
