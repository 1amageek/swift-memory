import Testing
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
        batch.triple("ex:A", "rdf:type", "ex:Person")
        #expect(batch.givens.count == 1)
        #expect(batch.statements.count == 1)
        #expect(batch.givens[0].payloadRef == "hello")
        #expect(batch.statements[0].subject == "ex:A")
    }

    @Test
    func mergeBatches() {
        let a = MemoryBatch(
            statements: [Statement(subject: "ex:A", predicate: "rdf:type", object: "ex:Person")]
        )
        let b = MemoryBatch(
            statements: [Statement(subject: "ex:B", predicate: "rdf:type", object: "ex:Place")]
        )
        let merged = a.merging(b)
        #expect(merged.statements.count == 2)
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
            paths: [
                "direct match",
                "ex:Bob --[ex:worksAt]--> ex:Acme",
                "ex:Task1 --[ex:assignedTo]--> ex:Alice",
            ]
        )
        #expect(entity.score == 3)
        #expect(entity.paths.count == 3)
    }

    @Test
    func emptyRecallResult() {
        let result = RecallResult.empty
        #expect(result.entities.isEmpty)
        #expect(result.givens.isEmpty)
    }
}
