import Testing
import Memory

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
        #expect(query.depth == 2)
        #expect(query.limit == 10)
        #expect(query.embedding == nil)
        #expect(query.anchor == nil)
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
        let container = GivenEncodingContainer()
        let knowledgeContainer = KnowledgeEncodingContainer()

        struct TestEncoding: MemoryEncoding {
            let givens: GivenEncodingContainer
            let knowledge: KnowledgeEncodingContainer
            func givenContainer() -> GivenEncodingContainer { givens }
            func knowledgeContainer() -> KnowledgeEncodingContainer { knowledge }
        }

        let encoding = TestEncoding(givens: container, knowledge: knowledgeContainer)
        let input = "Hello world"
        try await input.encode(to: encoding)

        let materials = container.collectMaterials()
        #expect(materials.count == 1)
        #expect(materials[0].payload == "Hello world")
        #expect(materials[0].source == "text")
    }
}
