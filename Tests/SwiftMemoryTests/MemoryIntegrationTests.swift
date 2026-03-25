import Testing
import Foundation
import SwiftMemory
import MemoryOntology
import Database

/// Encoding that does nothing — returns empty batch.
struct PassthroughEncoding: MemoryEncoding {
    func interpret(_ input: any GivenRepresentable) async throws -> MemoryBatch {
        MemoryBatch.empty
    }
    func extractQuery(_ input: any GivenRepresentable) async throws -> RecallQuery {
        RecallQuery()
    }
}

/// Encoding that creates Statement triples from input text.
/// Parses "triple:s,p,o" patterns.
struct TripleEncoding: MemoryEncoding {
    func extractQuery(_ input: any GivenRepresentable) async throws -> RecallQuery {
        let content = input.givenRepresentation
        let words = content.components.compactMap { c -> [String]? in
            if case .text(let t) = c { return t.value.split(separator: " ").map(String.init) }
            return nil
        }.flatMap { $0 }
        return RecallQuery(keywords: words)
    }
    func interpret(_ input: any GivenRepresentable) async throws -> MemoryBatch {
        var batch = MemoryBatch()
        let content = input.givenRepresentation
        for component in content.components {
            if case .text(let text) = component {
                for line in text.value.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    if line.hasPrefix("triple:") {
                        let parts = line.dropFirst("triple:".count).split(separator: ",")
                        if parts.count == 3 {
                            batch.triple(String(parts[0]), String(parts[1]), String(parts[2]))
                        }
                    }
                }
            }
        }
        return batch
    }
}

@Suite("Memory Integration Tests", .serialized)
struct MemoryIntegrationTests {

    @Test("Store with empty batch discards materials")
    func storeEmptyBatchDiscardsGivens() async throws {
        let memory = try await Memory(path: nil, encoding: PassthroughEncoding())
        try await memory.store("Cherry blossoms are beautiful")
        // PassthroughEncoding returns empty → materials discarded, nothing saved
    }

    @Test("Store and recall via triples")
    func storeAndRecallViaTriples() async throws {
        let memory = try await Memory(path: nil, encoding: TripleEncoding())
        try await memory.store("triple:ex:person/alice,rdf:type,ex:Person; triple:ex:person/alice,rdfs:label,Alice")

        let result = try await memory.recall(keywords: ["Alice"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Alice")
        #expect(result.entities[0].type == "ex:Person")
    }

    @Test("Spreading activation through relationships")
    func spreadingActivation() async throws {
        let memory = try await Memory(path: nil, encoding: TripleEncoding())
        try await memory.store("""
            triple:ex:person/alice,rdf:type,ex:Person; \
            triple:ex:person/alice,rdfs:label,Alice; \
            triple:ex:org/acme,rdf:type,ex:Organization; \
            triple:ex:org/acme,rdfs:label,Acme; \
            triple:ex:person/alice,ex:worksAt,ex:org/acme
            """)

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("ex:person/alice"))
        #expect(iris.contains("ex:org/acme"))
    }

    @Test("Store batch directly")
    func storeBatchDirectly() async throws {
        let memory = try await Memory(path: nil, encoding: PassthroughEncoding())

        var batch = MemoryBatch()
        batch.triple("ex:person/bob", "rdf:type", "ex:Person")
        batch.triple("ex:person/bob", "rdfs:label", "Bob")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Bob"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Bob")
    }

    @Test("Recall with no match returns empty")
    func recallNoMatch() async throws {
        let memory = try await Memory(path: nil, encoding: TripleEncoding())
        try await memory.store("triple:ex:person/alice,rdf:type,ex:Person; triple:ex:person/alice,rdfs:label,Alice")

        let result = try await memory.recall(keywords: ["Nonexistent"])
        #expect(result.entities.isEmpty)
    }

    @Test("Recall with empty keywords returns empty")
    func recallEmptyKeywords() async throws {
        let memory = try await Memory(path: nil, encoding: PassthroughEncoding())
        let result = try await memory.recall(keywords: [])
        #expect(result.entities.isEmpty)
    }

    @Test("Multiple stores accumulate knowledge")
    func multipleStores() async throws {
        let memory = try await Memory(path: nil, encoding: TripleEncoding())
        try await memory.store("triple:ex:person/alice,rdf:type,ex:Person; triple:ex:person/alice,rdfs:label,Alice")
        try await memory.store("triple:ex:person/bob,rdf:type,ex:Person; triple:ex:person/bob,rdfs:label,Bob")
        try await memory.store("triple:ex:person/alice,ex:worksAt,ex:person/bob")

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("ex:person/alice"))
        #expect(iris.contains("ex:person/bob"))
    }

    @Test("OntologyPolicy validation via Memory")
    func policyValidation() async throws {
        let memory = try await Memory(path: nil, encoding: PassthroughEncoding())
        #expect(memory.ontologyPolicy.validate(typeIRI: "ex:Person"))
        #expect(!memory.ontologyPolicy.validate(typeIRI: "ex:Spaceship"))
    }
}
