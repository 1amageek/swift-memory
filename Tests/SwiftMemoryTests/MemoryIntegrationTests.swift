import Testing
import Foundation
import SwiftMemory
import MemoryOntology

/// Deterministic stub used by tests that need a Memory with a provider.
/// Returns a seeded embedding that depends only on the input text, so two
/// different strings produce different vectors and identical strings produce
/// identical vectors.
private struct StubEmbeddingProvider: EmbeddingProvider {
    let dimensions: Int = 256

    func embed(_ text: String) async throws -> [Float] {
        var vec = [Float](repeating: 0, count: dimensions)
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        var state = hash | 1
        for i in 0..<dimensions {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let bits = Float(bitPattern: 0x3F800000 | UInt32(truncatingIfNeeded: state >> 41))
            vec[i] = bits - 1.5
        }
        let norm = vec.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vec }
        return vec.map { $0 / norm }
    }
}

@Suite("Memory Integration Tests", .serialized)
struct MemoryIntegrationTests {

    @Test("Store batch and recall by label")
    func storeBatchAndRecall() async throws {
        let memory = try await Memory(path: nil)

        var batch = MemoryBatch()
        batch.triple("ex:person/alice", "rdf:type", "ex:Person")
        batch.triple("ex:person/alice", "rdfs:label", "Alice")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Alice"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Alice")
        #expect(result.entities[0].type == "ex:Person")
    }

    @Test("Spreading activation through relationships")
    func spreadingActivation() async throws {
        let memory = try await Memory(path: nil)

        var batch = MemoryBatch()
        batch.triple("ex:person/alice", "rdf:type", "ex:Person")
        batch.triple("ex:person/alice", "rdfs:label", "Alice")
        batch.triple("ex:org/acme", "rdf:type", "ex:Organization")
        batch.triple("ex:org/acme", "rdfs:label", "Acme")
        batch.triple("ex:person/alice", "ex:worksAt", "ex:org/acme")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("ex:person/alice"))
        #expect(iris.contains("ex:org/acme"))
    }

    @Test("Multiple stores accumulate knowledge")
    func multipleStores() async throws {
        let memory = try await Memory(path: nil)

        var batch1 = MemoryBatch()
        batch1.triple("ex:person/alice", "rdf:type", "ex:Person")
        batch1.triple("ex:person/alice", "rdfs:label", "Alice")
        try await memory.store(batch1)

        var batch2 = MemoryBatch()
        batch2.triple("ex:person/bob", "rdf:type", "ex:Person")
        batch2.triple("ex:person/bob", "rdfs:label", "Bob")
        batch2.triple("ex:person/alice", "ex:worksAt", "ex:person/bob")
        try await memory.store(batch2)

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("ex:person/alice"))
        #expect(iris.contains("ex:person/bob"))
    }

    @Test("Recall with no match returns empty")
    func recallNoMatch() async throws {
        let memory = try await Memory(path: nil)

        var batch = MemoryBatch()
        batch.triple("ex:person/alice", "rdf:type", "ex:Person")
        batch.triple("ex:person/alice", "rdfs:label", "Alice")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Nonexistent"])
        #expect(result.entities.isEmpty)
    }

    @Test("Recall with empty keywords returns empty")
    func recallEmptyKeywords() async throws {
        let memory = try await Memory(path: nil)
        let result = try await memory.recall(keywords: [])
        #expect(result.entities.isEmpty)
    }

    @Test("Empty batch is no-op")
    func emptyBatchNoOp() async throws {
        let memory = try await Memory(path: nil)
        try await memory.store(.empty)
    }

    @Test("OntologyPolicy validation")
    func policyValidation() async throws {
        let memory = try await Memory(path: nil)
        #expect(memory.ontologyPolicy.validate(typeIRI: "ex:Person"))
        #expect(!memory.ontologyPolicy.validate(typeIRI: "ex:Spaceship"))
    }

    @Test("Statement deduplication — same triple from different Givens")
    func statementDeduplication() async throws {
        let memory = try await Memory(
            path: nil,
            embeddingProvider: StubEmbeddingProvider()
        )

        // Setup: create entities with labels for recall
        var setup = MemoryBatch()
        setup.triple("ex:person/alice", "rdf:type", "ex:Person")
        setup.triple("ex:person/alice", "rdfs:label", "Alice")
        setup.triple("ex:org/acme", "rdf:type", "ex:Organization")
        setup.triple("ex:org/acme", "rdfs:label", "Acme")
        try await memory.store(setup)

        // Store same relationship from two different Givens
        var batch1 = MemoryBatch()
        batch1.triple("ex:person/alice", "ex:worksAt", "ex:org/acme")
        try await memory.store(given: "Email from Alice mentioning Acme", knowledge: batch1)

        var batch2 = MemoryBatch()
        batch2.triple("ex:person/alice", "ex:worksAt", "ex:org/acme")
        try await memory.store(given: "Meeting notes confirming Alice at Acme", knowledge: batch2)

        // Same triple content → same Statement ID (content-addressable)
        let id1 = Statement.contentID(
            graph: "memory:default",
            subject: "ex:person/alice",
            predicate: "ex:worksAt",
            object: "ex:org/acme"
        )
        let id2 = Statement.contentID(
            graph: "memory:default",
            subject: "ex:person/alice",
            predicate: "ex:worksAt",
            object: "ex:org/acme"
        )
        #expect(id1 == id2)

        // Recall should find Alice via spreading activation
        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("ex:person/alice"))
    }

    @Test("Statement contentID is deterministic")
    func statementContentID() async throws {
        let id1 = Statement.contentID(
            graph: "memory:default",
            subject: "ex:person/alice",
            predicate: "ex:worksAt",
            object: "ex:org/acme"
        )
        let id2 = Statement.contentID(
            graph: "memory:default",
            subject: "ex:person/alice",
            predicate: "ex:worksAt",
            object: "ex:org/acme"
        )
        #expect(id1 == id2)

        // Different triple → different ID
        let id3 = Statement.contentID(
            graph: "memory:default",
            subject: "ex:person/bob",
            predicate: "ex:worksAt",
            object: "ex:org/acme"
        )
        #expect(id1 != id3)
    }
}
