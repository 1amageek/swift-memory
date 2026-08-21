// Trace.swift
// Memory trace linking Given (episode) to Statement (fact)

import DatabaseKit

/// A memory trace links a Given (sensory episode) to a Statement (fact).
///
/// Traces record provenance: which specific facts were learned from which
/// experience. One Given can produce many Statements, and one Statement
/// can be confirmed by many different Givens.
///
/// Traces use content-addressable IDs (givenID|statementID) for idempotency.
@Persistable
public struct Trace {

    #Directory<Trace>("memory", "traces")

    #Index(.ordered(name: "Trace_givenID", keys: [.ascending(\Trace.givenID)]))
    #Index(.ordered(name: "Trace_statementID", keys: [.ascending(\Trace.statementID)]))

    /// Unique identifier (content-addressable: givenID|statementID).
    public var id: String = ""

    /// The Given (episode) that produced this fact.
    public var givenID: String = ""

    /// The Statement (fact) that was learned.
    public var statementID: String = ""
}

extension Trace: SecurityPolicy {
    public static func permitsRead(
        of resource: borrowing Trace,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsCreate(
        _ newResource: borrowing Trace,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsUpdate(
        from resource: borrowing Trace,
        to newResource: borrowing Trace,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    public static func permitsDelete(
        _ resource: borrowing Trace,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }
}
