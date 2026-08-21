import Testing
import Foundation
import NaturalLanguage
@testable import SwiftMemory
import MemoryOntology
import Database

// Test entity for AppleEmbeddingProvider. Uses the explicit 512-dim
// `embeddingDimensions` which matches the English NLContextualEmbedding
// model output.
@Persistable
struct AppleTestPerson: Entity {

    #Directory<AppleTestPerson>("apple", "test", "persons")

    var id: String = UUID().uuidString
    var name: String
    var assertion: String = ""
    var embedding: Vector = Vector(int8: [])

    var memoryLabel: String? { name }
}

extension AppleTestPerson {
    static var embeddingDimensions: Int { 512 }
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
        let vector = try await provider.embed(":Alice a :Person .")
        #expect(vector.count == provider.dimensions)

        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1.0) < 1e-3, "embedding must be L2-normalized; got norm=\(norm)")
    }

    @Test("Entity registration rejects an incompatible embedding dimension")
    func entityRegistrationRejectsIncompatibleDimension() throws {
        do {
            _ = try MemoryEntityRegistration(AppleTestPerson.self)
            Issue.record("Registration must reject a 512-dimensional Entity")
        } catch MemoryError.embeddingDimensionMismatch(let expected, let actual) {
            #expect(expected == Given.embeddingDimensions)
            #expect(actual == AppleTestPerson.embeddingDimensions)
        }
    }
}
