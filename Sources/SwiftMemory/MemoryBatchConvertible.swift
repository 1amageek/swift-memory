// MemoryBatchConvertible.swift
// Protocol for types that can convert to MemoryBatch

/// A type that can convert itself into a MemoryBatch for persistence.
///
/// Clients define their store input type (typically @Generable)
/// and implement this protocol to convert it to a MemoryBatch.
///
/// ```swift
/// @Generable
/// struct MemoryStoreInput: MemoryBatchConvertible {
///     var persons: [Person] = []
///     var organizations: [Organization] = []
///     var relationships: [Relationship] = []
///
///     func toBatch() -> MemoryBatch {
///         var batch = MemoryBatch()
///         for p in persons { batch.entity(p) }
///         for o in organizations { batch.entity(o) }
///         for r in relationships { batch.triple(r.subject, r.predicate, r.object) }
///         return batch
///     }
/// }
/// ```
public protocol MemoryBatchConvertible: Sendable {
    /// Convert to MemoryBatch.
    ///
    /// Given→Statement provenance is handled automatically by Memory via Trace records.
    /// Implementations do not need to manage givenID.
    func toBatch() -> MemoryBatch
}
