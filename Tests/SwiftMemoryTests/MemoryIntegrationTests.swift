import Testing
import Foundation
import SwiftMemory
import MemoryOntology

/// Simple encoding that stores input as Given only.
struct TestEncoding: MemoryEncoding {
    func encode(_ input: String) async throws -> MemoryBatch {
        var batch = MemoryBatch()
        batch.given(input, source: "test")
        return batch
    }
}

/// Encoding that parses "person:Name" / "org:Name" / "rel:s,p,o" commands.
struct EntityEncoding: MemoryEncoding {
    func encode(_ input: String) async throws -> MemoryBatch {
        var batch = MemoryBatch()
        batch.given(input, source: "test")

        for part in input.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if part.hasPrefix("person:") {
                let name = String(part.dropFirst("person:".count))
                batch.entity(type: "Person", name: name)
            } else if part.hasPrefix("org:") {
                let name = String(part.dropFirst("org:".count))
                batch.entity(type: "Organization", name: name)
            } else if part.hasPrefix("rel:") {
                let components = part.dropFirst("rel:".count).split(separator: ",")
                if components.count == 3 {
                    batch.triple(
                        String(components[0]),
                        String(components[1]),
                        String(components[2])
                    )
                }
            }
        }
        return batch
    }
}

@Suite("Memory Integration Tests", .serialized)
struct MemoryIntegrationTests {

    @Test("Store text and verify no crash")
    func storeText() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())
        try await memory.store("Cherry blossoms are beautiful in spring")
    }

    @Test("Store entities via encoding and recall by label")
    func storeEntitiesAndRecall() async throws {
        let memory = try await Memory(path: nil, encoding: EntityEncoding())
        try await memory.store("person:Alice; org:Acme Corp")

        let result = try await memory.recall(keywords: ["Alice"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Alice")
        #expect(result.entities[0].type == "ex:Person")
    }

    @Test("Recall spreads activation through relationships")
    func recallSpreadsActivation() async throws {
        let memory = try await Memory(path: nil, encoding: EntityEncoding())
        try await memory.store("person:Alice; org:Acme Corp; rel:memory:person/alice,ex:worksAt,memory:organization/acme_corp")

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("memory:person/alice"))
        #expect(iris.contains("memory:organization/acme_corp"))
    }

    @Test("Store batch directly")
    func storeBatchDirectly() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())

        var batch = MemoryBatch()
        batch.given("Direct batch test", source: "test")
        batch.entity(type: "Person", name: "Bob")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Bob"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Bob")
    }

    @Test("Store Codable batch from JSON")
    func storeCodableBatch() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())

        let json = """
        {
            "givens": [{"text": "test", "source": "json"}],
            "entities": [{"type": "Person", "name": "Carol", "properties": {}}],
            "statements": []
        }
        """
        let batch = try JSONDecoder().decode(MemoryBatch.self, from: json.data(using: .utf8)!)
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Carol"])
        #expect(!result.entities.isEmpty)
        #expect(result.entities[0].label == "Carol")
    }

    @Test("Recall with no match returns empty")
    func recallNoMatch() async throws {
        let memory = try await Memory(path: nil, encoding: EntityEncoding())
        try await memory.store("person:Alice")

        let result = try await memory.recall(keywords: ["Nonexistent"])
        #expect(result.entities.isEmpty)
    }

    @Test("Recall with empty keywords returns empty")
    func recallEmptyKeywords() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())
        let result = try await memory.recall(keywords: [])
        #expect(result.entities.isEmpty)
    }

    @Test("Multiple stores accumulate knowledge")
    func multipleStoresAccumulate() async throws {
        let memory = try await Memory(path: nil, encoding: EntityEncoding())
        try await memory.store("person:Alice")
        try await memory.store("person:Bob")
        try await memory.store("rel:memory:person/alice,ex:worksAt,memory:person/bob")

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("memory:person/alice"))
        #expect(iris.contains("memory:person/bob"))
    }

    @Test("OntologyPolicy validation via Memory")
    func policyValidation() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())
        #expect(memory.ontologyPolicy.validate(typeIRI: "ex:Person"))
        #expect(!memory.ontologyPolicy.validate(typeIRI: "ex:Spaceship"))
    }

    @Test("Entity name resolution in statements")
    func entityNameResolution() async throws {
        let memory = try await Memory(path: nil, encoding: TestEncoding())

        var batch = MemoryBatch()
        batch.entity(type: "Person", name: "Alice")
        batch.entity(type: "Organization", name: "Acme")
        // Use names (not IRIs) — Memory resolves them
        batch.triple("Alice", "ex:worksAt", "Acme")
        try await memory.store(batch)

        let result = try await memory.recall(keywords: ["Alice"])
        let iris = result.entities.map(\.iri)
        #expect(iris.contains("memory:person/alice"))
        #expect(iris.contains("memory:organization/acme"))
    }
}
