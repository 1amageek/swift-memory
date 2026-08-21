import Database

/// A knowledge layer backed by one Database Framework Base.
///
/// Base identity, rather than a field on each record, provides the durable
/// transaction, authorization, and provenance boundary for the layer.
public struct MemoryLayer: Sendable, Hashable, Comparable {
    public let baseID: Base.ID
    public let name: String

    public init(
        id: String,
        name: String? = nil
    ) throws {
        try self.init(baseID: Base.ID(id), name: name)
    }

    public init(
        baseID: Base.ID,
        name: String? = nil
    ) throws {
        if let name, name.isEmpty {
            throw MemoryLayerError.emptyName(baseID)
        }
        self.baseID = baseID
        self.name = name ?? baseID.value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.baseID == rhs.baseID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseID)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.baseID < rhs.baseID
    }
}
