import Database

/// A type-erased entity whose database insertion was specialized at capture.
///
/// This preserves heterogeneous memory batches without asking Embedded Swift
/// to open an `Entity` existential at the generic `DatabaseContext.insert`
/// boundary.
public struct MemoryEntityRecord: Sendable {
    public let id: String
    public let type: String
    public let label: String?
    public let assertion: String
    public let embeddingDimensions: Int

    private let insertValue: @Sendable (Vector, DatabaseContext) throws -> Void

    public init<E: Persistable & Entity & Sendable>(_ entity: E) {
        self.id = entity.memoryID
        self.type = E.memoryType
        self.label = entity.memoryLabel
        self.assertion = entity.assertion
        self.embeddingDimensions = E.embeddingDimensions
        self.insertValue = { embedding, context in
            var value = entity
            value.embedding = embedding
            try context.insert(value)
        }
    }

    func insert(embedding: Vector, into context: DatabaseContext) throws {
        try insertValue(embedding, context)
    }
}
