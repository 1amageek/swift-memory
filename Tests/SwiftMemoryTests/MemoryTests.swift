import Testing
import Foundation
@testable import SwiftMemory
import MemoryOntology
import Database

@Suite
struct MemoryTests {

    @Test
    func emptyBatch() {
        let batch = MemoryBatch.empty
        #expect(batch.entities.isEmpty)
        #expect(batch.statements.isEmpty)
    }

    @Test
    func batchBuilderMethods() {
        var batch = MemoryBatch()
        batch.triple("ex:A", "rdf:type", "ex:Person")
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
    func givenRepresentable() {
        let content = "Hello world".givenRepresentation
        #expect(content.components.count == 1)
        if case .text(let text) = content.components[0] {
            #expect(text.value == "Hello world")
        } else {
            Issue.record("Expected text component")
        }
    }

    @Test
    func givenContentMultimodal() {
        let content = GivenContent(components: [
            .text(GivenContent.Text(value: "hello")),
            .image(GivenContent.Image(source: .url(URL(string: "https://example.com/img.png")!))),
        ])
        #expect(content.components.count == 2)
    }

    @Test
    func defaultOntologyPolicy() {
        let policy = DefaultOntologyPolicy()
        #expect(policy.primitiveClasses.count == 26)
        #expect(policy.validate(typeIRI: "ex:Person"))
        #expect(!policy.validate(typeIRI: "ex:Spaceship"))
    }

    @Test
    func recallQueryDefaults() {
        let query = RecallQuery()
        #expect(query.maxHops == 2)
        #expect(query.limit == 20)
        #expect(query.keywords.isEmpty)
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
