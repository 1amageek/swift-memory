// EntityRegistry.swift
// Type-safe decode registry for @OWLClass entities

import Foundation
import Database

/// Registry that decodes JSON into concrete @OWLClass Persistable types.
///
/// Maps type names (e.g. "Person") to decode closures built from
/// concrete types at registration time. Eliminates manual switch-case
/// factory methods — the LLM outputs JSON, the registry decodes it.
///
/// ```swift
/// let registry = EntityRegistry()
/// registry.register(Person.self)
/// registry.register(Organization.self)
///
/// // LLM outputs: {"type": "Person", "data": {"name": "Alice"}}
/// let person = try registry.decode(typeName: "Person", from: jsonData)
/// ```
public final class EntityRegistry: Sendable {

    private let decoders: [String: @Sendable (Data) throws -> any Persistable & Sendable]

    public init(_ types: [any (Persistable).Type]) {
        var map: [String: @Sendable (Data) throws -> any Persistable & Sendable] = [:]
        for type in types {
            Self.register(type, into: &map)
        }
        self.decoders = map
    }

    private static func register<T: Persistable>(
        _ type: T.Type,
        into map: inout [String: @Sendable (Data) throws -> any Persistable & Sendable]
    ) {
        let name = String(describing: type)
        map[name] = { data in
            try JSONDecoder().decode(T.self, from: data)
        }
    }

    /// Decode JSON data into a concrete Persistable entity.
    ///
    /// - Parameters:
    ///   - typeName: The type name (e.g. "Person", "Organization")
    ///   - data: JSON data for the entity
    /// - Returns: Decoded entity, or nil if type is not registered
    public func decode(typeName: String, from data: Data) throws -> (any Persistable & Sendable)? {
        guard let decoder = decoders[typeName] else { return nil }
        return try decoder(data)
    }

    /// All registered type names.
    public var registeredTypeNames: Set<String> {
        Set(decoders.keys)
    }
}
