import Testing
import Foundation
import SwiftMemory
import MemoryOntology

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
}
