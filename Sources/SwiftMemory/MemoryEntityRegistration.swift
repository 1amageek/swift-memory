import Database

/// A statically compiled entity schema and its matching database runtime.
///
/// Register every concrete `Entity` type that a `Memory` instance stores.
/// The registration keeps schema compilation, runtime decoding, vector-index
/// dimensions, and the model's `SecurityPolicy` handler aligned.
public struct MemoryEntityRegistration: Sendable {
    let runtime: EntityRuntimeRegistration
    let authorizationPolicy: AuthorizationPolicyHandler

    public init<Model: Persistable & Entity>(
        _ model: Model.Type
    ) throws {
        try Self.validateEmbeddingDimensions(model)
        self.runtime = try DatabaseFrameworkRuntime.entity(model)
        self.authorizationPolicy = AuthorizationPolicyHandler(model)
    }

    public init<Model: OWLClassEntity & Entity>(
        _ model: Model.Type
    ) throws {
        try Self.validateEmbeddingDimensions(model)
        self.runtime = try DatabaseFrameworkRuntime.entity(model)
        self.authorizationPolicy = AuthorizationPolicyHandler(model)
    }

    private static func validateEmbeddingDimensions<Model: Entity>(
        _ model: Model.Type
    ) throws {
        guard model.embeddingDimensions == 768 else {
            throw MemoryError.embeddingDimensionMismatch(
                expected: 768,
                actual: model.embeddingDimensions
            )
        }
    }
}
