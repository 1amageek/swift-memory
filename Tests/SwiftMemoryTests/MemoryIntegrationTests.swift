import Testing
import Foundation
@testable import SwiftMemory
import MemoryOntology
import Database

// Test-only entity type used to exercise embedding-based deduplication.
// `Entity` conformance is declared in the struct header so Swift emits the
// Polymorphable conformance record on the concrete type's metadata.
@Persistable @OWLClass("ex:Person")
struct TestPerson: Entity {

    #Directory<TestPerson>("test", "persons")

    var id: String = ULID().ulidString
    var name: String
    var assertion: String = ""
    var embedding: [Float] = []
}

@Persistable @OWLClass("ex:Organization")
struct TestOrganization: Entity {

    #Directory<TestOrganization>("test", "organizations")

    var id: String = ULID().ulidString
    var name: String
    var domain: String = ""
    var assertion: String = ""
    var embedding: [Float] = []
}

extension TestPerson {
    static var embeddingDimensions: Int { Given.embeddingDimensions }
}

extension TestOrganization {
    static var embeddingDimensions: Int { Given.embeddingDimensions }
}

/// Deterministic stub used by tests that need a Memory with a provider.
/// Returns a seeded embedding that depends only on the input text, so two
/// different strings produce different vectors and identical strings produce
/// identical vectors.
private struct StubEmbeddingProvider: EmbeddingProvider {
    let dimensions: Int = Given.embeddingDimensions

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

    // MARK: - Entity Embedding Deduplication

    @Test("Entity vector descriptors remain concrete KeyPaths per member type")
    func entityVectorDescriptorsRemainConcreteKeyPaths() throws {
        let schema = Schema(
            [TestPerson.self, TestOrganization.self],
            version: Schema.Version(1, 0, 0)
        )

        let personDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "Entity",
                memberType: TestPerson.self
            ).first { $0.name == "Entity_vector_embedding" }
        )
        let organizationDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "Entity",
                memberType: TestOrganization.self
            ).first { $0.name == "Entity_vector_embedding" }
        )

        #expect(personDescriptor.fieldNames == ["embedding"])
        #expect(organizationDescriptor.fieldNames == ["embedding"])
        #expect(personDescriptor.kind is VectorIndexKind<TestPerson>)
        #expect(organizationDescriptor.kind is VectorIndexKind<TestOrganization>)
        #expect(personDescriptor.keyPaths.first is PartialKeyPath<TestPerson>)
        #expect(organizationDescriptor.keyPaths.first is PartialKeyPath<TestOrganization>)
        #expect((personDescriptor.keyPaths.first is PartialKeyPath<TestOrganization>) == false)
        #expect((organizationDescriptor.keyPaths.first is PartialKeyPath<TestPerson>) == false)
    }

    @Test("Entity vector index stores and resolves multiple concrete types")
    func entityVectorIndexStoresAndResolvesMultipleConcreteTypes() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self, TestOrganization.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        var batch = MemoryBatch()
        batch.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        batch.entity(TestOrganization(name: "Acme", domain: "acme.example", assertion: "Acme is a company at acme.example"))
        try await memory.store(batch)

        let entities = try await memory._debugEntities(witness: TestPerson.self)
        #expect(entities.count == 2)
        #expect(entities.contains { $0 is TestPerson })
        #expect(entities.contains { $0 is TestOrganization })

        let resolved = try await memory.resolve(
            [ResolveCandidate(assertion: "Acme is a company at acme.example")],
            witness: TestOrganization.self
        )
        let first = try #require(resolved.first)
        #expect(first.hasCandidates)
        #expect(first.candidates.first?.assertion == "Acme is a company at acme.example")
        #expect((first.topSimilarity ?? 0) > 0.99)
    }

    @Test("Direct fdbContext.insert writes to polymorphic directory")
    func directInsertDualWrite() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        // First confirm Swift's runtime recognises TestPerson as Polymorphable
        // and resolves distinct concrete vs polymorphic directories.
        let metadata = await memory._debugPolymorphicMetadata(TestPerson.self)
        #expect(metadata.isPolymorphable, "TestPerson must conform to Polymorphable at runtime")
        #expect(metadata.polyDirectory != metadata.typeDirectory,
                "poly and concrete directories must differ for dual-write to trigger; poly=\(metadata.polyDirectory) type=\(metadata.typeDirectory)")
        #expect(metadata.polymorphableType == "Entity",
                "polymorphableType must resolve to 'Entity'; got '\(metadata.polymorphableType)'")

        let groups = await memory._debugPolymorphicGroupIdentifiers()
        #expect(groups.contains("Entity"),
                "Schema must register the 'Entity' polymorphic group; groups=\(groups)")

        let groupInfo = await memory._debugPolymorphicGroupInfo(identifier: "Entity")
        #expect(groupInfo?.memberTypes.contains("TestPerson") == true,
                "Entity group must list TestPerson as a member; members=\(groupInfo?.memberTypes ?? [])")
        #expect(groupInfo?.components == ["memory", "entities"],
                "Entity group must resolve to [memory, entities]; components=\(groupInfo?.components ?? [])")
        #expect(groupInfo?.indexes.contains("Entity_vector_embedding") == true,
                "Entity group must include the vector embedding index; indexes=\(groupInfo?.indexes ?? [])")

        // Bypass Memory's resolve pipeline — insert directly via fdbContext to
        // isolate the dual-write code path from entity-resolution logic.
        var alice = TestPerson(name: "Alice", assertion: "Alice is a person")
        alice.embedding = [Float](repeating: 0, count: TestPerson.embeddingDimensions)
        try await memory._debugDirectInsertAndCommit(alice)

        let concrete = try await memory._debugFetchAll(TestPerson.self)
        let rawPolyKeys = try await memory._debugRawPolymorphicKeyCount(identifier: "Entity")
        let probe = try await memory._debugPolymorphicItemsProbe(TestPerson.self)
        let polymorphic = try await memory._debugEntities(witness: TestPerson.self)
        #expect(concrete.count == 1, "concrete fetch should see 1 record")
        #expect(rawPolyKeys >= 1,
                "raw scan under _polymorphic_Entity/R must see >=1 key; got \(rawPolyKeys)")
        let probeMessage = "itemsPrefix=\(probe.itemsPrefixHex) typePrefix=\(probe.typeSubspacePrefixHex) typeCode=\(probe.typeCode) allKeys=\(probe.allKeysHex) typeKeys=\(probe.typeScopedKeysHex)"
        #expect(probe.typeScopedKeysHex.count >= 1,
                "typeCode-scoped scan must see >=1 key. \(probeMessage)")
        #expect(polymorphic.count == 1,
                "polymorphic fetch should see 1 record; raw=\(rawPolyKeys) concrete=\(concrete.count)")
    }

    @Test("Entity with identical assertion is deduplicated")
    func entityIdenticalIsDeduplicated() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        var first = MemoryBatch()
        first.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        try await memory.store(first)

        let concreteAfterFirst = try await memory._debugFetchAll(TestPerson.self)
        let polyAfterFirst = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(concreteAfterFirst.count == 1)
        #expect(polyAfterFirst == 1)

        var second = MemoryBatch()
        second.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        try await memory.store(second)

        let concreteAfterSecond = try await memory._debugFetchAll(TestPerson.self)
        let polyAfterSecond = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(concreteAfterSecond.count == 1)
        #expect(polyAfterSecond == 1)
    }

    @Test("Entity with different assertion is inserted as a new record")
    func entityDifferentLabelIsNewRecord() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        var first = MemoryBatch()
        first.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        try await memory.store(first)

        var second = MemoryBatch()
        second.entity(TestPerson(name: "Bob", assertion: "Bob is a person"))
        try await memory.store(second)

        let count = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(count == 2)
    }

    @Test("Duplicate entity in the same batch collapses to a single record")
    func entityDuplicateWithinBatchCollapses() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        var batch = MemoryBatch()
        batch.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        batch.entity(TestPerson(name: "Alice", assertion: "Alice is a person"))
        try await memory.store(batch)

        let count = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(count == 1)
    }

    @Test("Statement subject is remapped to resolved entity ID")
    func statementRemappedToResolvedEntity() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestPerson.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        let assertion = "Alice is a person"
        var initial = MemoryBatch()
        initial.entity(TestPerson(name: "Alice", assertion: assertion))
        try await memory.store(initial)

        let existing = try await memory._debugEntities(witness: TestPerson.self)
        let persistedAlice = try #require(existing.first as? TestPerson)

        // Store again with a statement referencing the entity's assertion.
        // The resolver should map the assertion to the persisted entity ID and
        // rewrite the statement subject.
        var followup = MemoryBatch()
        followup.entity(TestPerson(name: "Alice", assertion: assertion))
        followup.triple(assertion, "rdfs:comment", "loves memory")
        try await memory.store(followup)

        let statements = try await memory._debugFetchAll(Statement.self)
        let remapped = statements.first {
            $0.predicate == "rdfs:comment" && $0.object == "loves memory"
        }
        #expect(remapped?.subject == persistedAlice.id)
        #expect(remapped?.id == Statement.contentID(
            graph: "memory:default",
            subject: persistedAlice.id,
            predicate: "rdfs:comment",
            object: "loves memory"
        ))
    }

    @Test("Statement endpoints matching entity aliases are remapped to resolved entity IDs")
    func statementEndpointAliasesRemapToResolvedEntities() async throws {
        let memory = try await Memory(
            path: nil,
            entityTypes: [TestOrganization.self],
            embeddingProvider: StubEmbeddingProvider()
        )

        let assertion = "TSMC is a semiconductor foundry"
        var batch = MemoryBatch()
        batch.entity(TestOrganization(name: "TSMC", domain: "tsmc.com", assertion: assertion))
        batch.alias("TSMC", for: assertion)
        batch.triple("TSMC", "ex:produces", "TSMC N2")
        try await memory.store(batch)

        let entities = try await memory._debugEntities(witness: TestOrganization.self)
        let tsmc = try #require(entities.first as? TestOrganization)
        let statements = try await memory._debugFetchAll(Statement.self)
        let remapped = statements.first {
            $0.predicate == "ex:produces" && $0.object == "TSMC N2"
        }

        #expect(remapped?.subject == tsmc.id)
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
