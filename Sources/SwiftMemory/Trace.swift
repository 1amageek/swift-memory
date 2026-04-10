// Trace.swift
// Memory trace linking Given (episode) to Statement (fact)

import Foundation
import Database

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

    #Index(ScalarIndexKind<Trace>(fields: [\.givenID]))
    #Index(ScalarIndexKind<Trace>(fields: [\.statementID]))

    /// Unique identifier (content-addressable: givenID|statementID).
    public var id: String = UUID().uuidString

    /// The Given (episode) that produced this fact.
    public var givenID: String = ""

    /// The Statement (fact) that was learned.
    public var statementID: String = ""
}
