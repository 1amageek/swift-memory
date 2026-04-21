import Testing
import Foundation
import NaturalLanguage
@testable import SwiftMemory
import MemoryOntology
import Database

// Test entity for AppleEmbeddingProvider. Overrides `embeddingDimensions`
// to match the English NLContextualEmbedding model output so that the
// shared Entity polymorphic vector index is consistent.
@Persistable @OWLClass("ex:Person")
struct AppleTestPerson: Entity {

    #Directory<AppleTestPerson>("apple", "test", "persons")

    var id: String = ULID().ulidString
    var name: String
    var embedding: [Float] = []
    var created: Date = Date()
    var updated: Date = Date()
}

extension AppleTestPerson {
    static var embeddingDimensions: Int { 512 }
    var label: String { name }
    var entityType: String { "persons" }
}

@Suite("Apple Embedding Integration Tests", .serialized)
struct AppleEmbeddingIntegrationTests {

    private func makeProvider() async throws -> AppleEmbeddingProvider {
        try await AppleEmbeddingProvider(language: .english)
    }

    @Test("AppleEmbeddingProvider loads and reports dimensions")
    func providerLoads() async throws {
        let provider = try await makeProvider()
        #expect(provider.dimensions == AppleTestPerson.embeddingDimensions,
                "Apple English embedding dimension must match AppleTestPerson.embeddingDimensions; got \(provider.dimensions)")
    }

    @Test("AppleEmbeddingProvider embeds text to normalized vector")
    func embedsToNormalizedVector() async throws {
        let provider = try await makeProvider()
        let vector = try await provider.embed("persons Alice")
        #expect(vector.count == provider.dimensions)

        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1.0) < 1e-3, "embedding must be L2-normalized; got norm=\(norm)")
    }

    @Test("Identical entities deduplicate via Apple embeddings")
    func identicalEntitiesDedup() async throws {
        let provider = try await makeProvider()
        let memory = try await Memory(
            path: nil,
            entityTypes: [AppleTestPerson.self],
            embeddingProvider: provider,
            resolutionThreshold: 0.99
        )

        var first = MemoryBatch()
        first.entity(AppleTestPerson(name: "Alice"))
        try await memory.store(first)

        var second = MemoryBatch()
        second.entity(AppleTestPerson(name: "Alice"))
        try await memory.store(second)

        let count = try await memory._debugEntityCount(witness: AppleTestPerson.self)
        #expect(count == 1, "identical entities must collapse to a single record; got \(count)")
    }

    @Test("Distinct entities remain separate under Apple embeddings")
    func distinctEntitiesSeparate() async throws {
        let provider = try await makeProvider()
        let memory = try await Memory(
            path: nil,
            entityTypes: [AppleTestPerson.self],
            embeddingProvider: provider,
            resolutionThreshold: 0.99
        )

        var first = MemoryBatch()
        first.entity(AppleTestPerson(name: "Alice"))
        try await memory.store(first)

        var second = MemoryBatch()
        second.entity(AppleTestPerson(name: "Bob"))
        try await memory.store(second)

        let count = try await memory._debugEntityCount(witness: AppleTestPerson.self)
        #expect(count == 2, "distinct names must remain separate; got \(count)")
    }
}
