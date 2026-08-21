import Database

/// Ordered knowledge layers and the layer used by unscoped Memory calls.
public struct MemoryLayerSet: Sendable {
    public let layers: [MemoryLayer]
    public let defaultLayer: MemoryLayer

    public init(
        _ layers: [MemoryLayer],
        default defaultLayer: MemoryLayer? = nil
    ) throws {
        guard !layers.isEmpty else {
            throw MemoryLayerError.emptyLayerSet
        }

        var seen: Set<Base.ID> = []
        for layer in layers {
            guard seen.insert(layer.baseID).inserted else {
                throw MemoryLayerError.duplicateLayer(layer.baseID)
            }
        }

        let requestedDefault = defaultLayer ?? layers[0]
        guard let resolvedDefault = layers.first(where: {
            $0.baseID == requestedDefault.baseID
        }) else {
            throw MemoryLayerError.defaultLayerNotConfigured(
                requestedDefault.baseID
            )
        }
        self.layers = layers
        self.defaultLayer = resolvedDefault
    }

    public static func local() throws -> MemoryLayerSet {
        let layer = try MemoryLayer(id: "default", name: "Default")
        return try MemoryLayerSet([layer], default: layer)
    }

    public func contains(_ layer: MemoryLayer) -> Bool {
        layers.contains { $0.baseID == layer.baseID }
    }
}
