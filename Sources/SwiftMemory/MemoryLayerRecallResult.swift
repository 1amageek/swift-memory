/// Recall output from one exact knowledge layer.
public struct MemoryLayerRecallResult: Sendable {
    public let layer: MemoryLayer
    public let result: RecallResult

    public init(layer: MemoryLayer, result: RecallResult) {
        self.layer = layer
        self.result = result
    }
}
