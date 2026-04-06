// Trace.swift
// Memory trace linking Given (episode) to Entity (concept)

import Foundation
import Database

/// A memory trace records that a concept (Entity) was activated
/// during a specific experience (Given).
///
/// In cognitive science, a memory trace is the residual record
/// linking episodic memory to semantic memory. Traces accumulate
/// over time — the same entity can have traces from many different
/// Givens, and one Given can leave traces on many entities.
///
/// Traces are append-only. Entity upserts do not affect existing traces.
@Persistable
public struct Trace {

    #Directory<Trace>("memory", "traces")

    #Index(ScalarIndexKind<Trace>(fields: [\.givenID]))
    #Index(ScalarIndexKind<Trace>(fields: [\.entityID]))

    /// Unique identifier.
    public var id: String = UUID().uuidString

    /// The Given (episode) that activated this entity.
    public var givenID: String = ""

    /// The Entity (concept) that was activated.
    public var entityID: String = ""
}
