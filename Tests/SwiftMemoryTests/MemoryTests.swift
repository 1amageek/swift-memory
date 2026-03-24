import Testing
import SwiftMemory

@Suite
struct MemoryTests {

    @Test
    func emptyBatch() {
        let batch = MemoryBatch.empty
        #expect(batch.givens.isEmpty)
        #expect(batch.knowledge.isEmpty)
    }

    @Test
    func mergeBatches() {
        let a = MemoryBatch(
            givens: [],
            knowledge: [Statement(subject: "ex:A", predicate: "rdf:type", object: "ex:Person")]
        )
        let b = MemoryBatch(
            givens: [],
            knowledge: [Statement(subject: "ex:B", predicate: "rdf:type", object: "ex:Place")]
        )
        let merged = a.merging(b)
        #expect(merged.knowledge.count == 2)
    }

    @Test
    func ontologyPolicyPrimitiveClasses() {
        #expect(OntologyPolicy.primitiveClasses.count == 26)
        #expect(!OntologyPolicy.seedSubClasses.isEmpty)
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

    @Test
    func givenEncodingContainer() {
        let container = GivenEncodingContainer()
        container.encode("hello", source: "test")
        container.encode(imageRef: "img://abc", source: "test")
        let materials = container.collectMaterials()
        #expect(materials.count == 2)
        #expect(materials[0].modality == "text")
        #expect(materials[1].modality == "image")
    }

    @Test
    func knowledgeEncodingContainer() {
        let container = KnowledgeEncodingContainer()
        container.encode(subject: "ex:A", predicate: "rdf:type", object: "ex:Person")
        let statements = container.collectStatements()
        #expect(statements.count == 1)
        #expect(statements[0].subject == "ex:A")
    }

    @Test
    func stringMemoryEncodable() async throws {
        let givenContainer = GivenEncodingContainer()
        let knowledgeContainer = KnowledgeEncodingContainer()

        struct TestEncoding: MemoryEncoding {
            let givens: GivenEncodingContainer
            let knowledge: KnowledgeEncodingContainer
            func givenContainer() -> GivenEncodingContainer { givens }
            func knowledgeContainer() -> KnowledgeEncodingContainer { knowledge }
        }

        let encoding = TestEncoding(givens: givenContainer, knowledge: knowledgeContainer)
        try await "Hello world".encode(to: encoding)

        let materials = givenContainer.collectMaterials()
        #expect(materials.count == 1)
        #expect(materials[0].payload == "Hello world")
        #expect(materials[0].source == "text")
    }
}
