import Testing
import Foundation
import SwiftMemory
import MemoryOntology

@Suite
struct MemoryTests {

    @Test
    func emptyBatch() {
        let batch = MemoryBatch.empty
        #expect(batch.givens.isEmpty)
        #expect(batch.entities.isEmpty)
        #expect(batch.statements.isEmpty)
    }

    @Test
    func batchBuilderMethods() {
        var batch = MemoryBatch()
        batch.given("hello", source: "test")
        batch.entity(type: "Person", name: "Alice", properties: ["email": "alice@acme.com"])
        batch.triple("ex:A", "rdf:type", "ex:Person")
        #expect(batch.givens.count == 1)
        #expect(batch.givens[0].text == "hello")
        #expect(batch.entities.count == 1)
        #expect(batch.entities[0].name == "Alice")
        #expect(batch.entities[0].properties["email"] == "alice@acme.com")
        #expect(batch.statements.count == 1)
        #expect(batch.statements[0].subject == "ex:A")
    }

    @Test
    func mergeBatches() {
        let a = MemoryBatch(
            statements: [StatementRecord(subject: "ex:A", predicate: "rdf:type", object: "ex:Person")]
        )
        let b = MemoryBatch(
            statements: [StatementRecord(subject: "ex:B", predicate: "rdf:type", object: "ex:Place")]
        )
        let merged = a.merging(b)
        #expect(merged.statements.count == 2)
    }

    @Test
    func batchCodable() throws {
        var batch = MemoryBatch()
        batch.given("test input", source: "chat")
        batch.entity(type: "Person", name: "Alice", properties: ["email": "a@b.com"])
        batch.triple("Alice", "ex:worksAt", "Acme")

        let data = try JSONEncoder().encode(batch)
        let decoded = try JSONDecoder().decode(MemoryBatch.self, from: data)

        #expect(decoded.givens.count == 1)
        #expect(decoded.givens[0].text == "test input")
        #expect(decoded.entities.count == 1)
        #expect(decoded.entities[0].name == "Alice")
        #expect(decoded.entities[0].properties["email"] == "a@b.com")
        #expect(decoded.statements.count == 1)
        #expect(decoded.statements[0].predicate == "ex:worksAt")
    }

    @Test
    func batchDecodableFromLLMJSON() throws {
        let json = """
        {
            "givens": [],
            "entities": [
                {"type": "Person", "name": "John", "properties": {"email": "john@example.com"}},
                {"type": "Organization", "name": "Globex Corp", "properties": {}}
            ],
            "statements": [
                {"subject": "John", "predicate": "ex:worksAt", "object": "Globex Corp"}
            ]
        }
        """
        let batch = try JSONDecoder().decode(MemoryBatch.self, from: json.data(using: .utf8)!)

        #expect(batch.entities.count == 2)
        #expect(batch.entities[0].type == "Person")
        #expect(batch.entities[1].name == "Globex Corp")
        #expect(batch.statements[0].predicate == "ex:worksAt")
    }

    @Test
    func defaultOntologyPolicy() {
        let policy = DefaultOntologyPolicy()
        #expect(policy.primitiveClasses.count == 26)
        #expect(!policy.seedSubClasses.isEmpty)
        #expect(policy.validate(typeIRI: "ex:Person"))
        #expect(!policy.validate(typeIRI: "ex:Spaceship"))
    }

    @Test
    func recallQueryDefaults() {
        let query = RecallQuery()
        #expect(query.maxHops == 2)
        #expect(query.limit == 20)
        #expect(query.keywords.isEmpty)
        #expect(query.embedding == nil)
    }

    @Test
    func recalledEntityScore() {
        let entity = RecalledEntity(
            iri: "ex:Alice",
            label: "Alice",
            type: "ex:Person",
            score: 3,
            paths: ["direct match", "ex:Bob --[ex:worksAt]--> ex:Acme"]
        )
        #expect(entity.score == 3)
        #expect(entity.paths.count == 2)
    }

    @Test
    func emptyRecallResult() {
        let result = RecallResult.empty
        #expect(result.entities.isEmpty)
        #expect(result.givens.isEmpty)
    }
}
