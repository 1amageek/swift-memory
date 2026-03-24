// RecallResult.swift
// Result of a recall operation

/// The result of a recall query.
///
/// Contains scored entities from spreading activation
/// and optionally similar givens from vector search.
public struct RecallResult: Sendable {

    /// Entities recalled via spreading activation, sorted by score.
    public var entities: [RecalledEntity]

    /// Givens recalled via vector similarity search.
    public var givens: [Given]

    public static let empty = RecallResult(entities: [], givens: [])

    public init(entities: [RecalledEntity] = [], givens: [Given] = []) {
        self.entities = entities
        self.givens = givens
    }
}
