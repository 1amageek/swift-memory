/// Cross-layer recall grouped by Base-backed layer.
///
/// Results are intentionally not flattened because equal logical entity IDs
/// in different Bases have distinct identities and provenance.
public struct LayeredRecallResult: Sendable {
    public let layers: [MemoryLayerRecallResult]

    public init(layers: [MemoryLayerRecallResult]) {
        self.layers = layers
    }
}
