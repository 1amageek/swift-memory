import Testing
import Foundation
@testable import SwiftMemory
import MemoryOntology
import Database

protocol TestSecurityPolicy: SecurityPolicy {}

extension TestSecurityPolicy {
    static func permitsRead(
        of resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    static func permitsCreate(
        _ newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    static func permitsUpdate(
        from resource: borrowing Self,
        to newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }

    static func permitsDelete(
        _ resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { true }
}

// Test-only entity type used to exercise entity storage and resolution.
// `Entity` conformance is declared in the struct header so Swift emits the
// Polymorphable conformance record on the concrete type's metadata.
@Persistable
struct TestPerson: Entity, TestSecurityPolicy {

    #Directory<TestPerson>("test", "persons")

    var id: String = UUID().uuidString
    var name: String
    var assertion: String = ""
    var embedding: Vector = Vector(int8: [])

    var memoryLabel: String? { name }
}

@Persistable
struct TestOrganization: Entity, TestSecurityPolicy {

    #Directory<TestOrganization>("test", "organizations")

    var id: String = UUID().uuidString
    var name: String
    var domain: String = ""
    var assertion: String = ""
    var embedding: Vector = Vector(int8: [])

    var memoryLabel: String? { name }
}

protocol AuthenticatedTestSecurityPolicy: SecurityPolicy {}

extension AuthenticatedTestSecurityPolicy {
    static func permitsRead(
        of resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsCreate(
        _ newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsUpdate(
        from resource: borrowing Self,
        to newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsDelete(
        _ resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }
}

@Persistable
struct ProtectedTestPerson: Entity, AuthenticatedTestSecurityPolicy {

    #Directory<ProtectedTestPerson>("test", "protected-people")

    var id: String = UUID().uuidString
    var name: String
    var assertion: String = ""
    var embedding: Vector = Vector(int8: [])

    var memoryLabel: String? { name }
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
        deterministicEmbedding(for: text, dimensions: dimensions)
    }
}

private actor HostEmbeddingBatchRecorder {
    private var recordedBatches: [[String]] = []

    func embed(_ texts: [String]) -> [[Float]] {
        recordedBatches.append(texts)
        return texts.map {
            deterministicEmbedding(for: $0, dimensions: Given.embeddingDimensions)
        }
    }

    func batches() -> [[String]] {
        recordedBatches
    }
}

private func deterministicEmbedding(for text: String, dimensions: Int) -> [Float] {
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

    @Test("Recall by typed entity label reaches explicit statements")
    func recallTypedEntityLabelReachesStatements() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestOrganization.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        let assertion = ":TSMC a :Organization ."
        var batch = MemoryBatch()
        batch.entity(TestOrganization(name: "TSMC", domain: "tsmc.com", assertion: assertion))
        batch.alias("TSMC", for: assertion)
        batch.triple("TSMC", "ex:produces", "TSMC N2")
        try await memory.store(batch)

        let concrete = try await memory._debugFetchAll(TestOrganization.self)
        let polymorphic = try await memory._debugEntities(witness: TestOrganization.self)
        #expect(concrete.count == 1)
        #expect(polymorphic.count == 1)

        let typedTriples = try await memory._debugTriples(graph: "memory:default")
        #expect(typedTriples.contains { $0.predicate == "rdfs:label" && $0.object == "TSMC" })

        let result = try await memory.recall(keywords: ["TSMC"])
        let labels = result.entities.map(\.label)
        let paths = result.entities.flatMap(\.paths)

        #expect(labels.contains("TSMC"))
        #expect(labels.contains("TSMC N2"))
        #expect(paths.contains { $0.contains("ex:produces") })
    }

    @Test("Host embedding provider batches entity store requests")
    func hostEmbeddingProviderBatchesEntityStoreRequests() async throws {
        let recorder = HostEmbeddingBatchRecorder()
        let provider = HostEmbeddingProvider(
            dimensions: Given.embeddingDimensions,
            embedBatch: { texts in
                await recorder.embed(texts)
            }
        )
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestOrganization.self)],
            embeddingProvider: provider
        )

        let first = ":Cloudflare a :Organization ."
        let second = ":WorkersAI a :Organization ."
        var batch = MemoryBatch()
        batch.entity(TestOrganization(name: "Cloudflare", domain: "cloudflare.com", assertion: first))
        batch.entity(TestOrganization(name: "Workers AI", domain: "cloudflare.com", assertion: second))
        try await memory.store(batch)

        let batches = await recorder.batches()
        #expect(batches == [[first, second]])
    }

    @Test("Host embedding provider validates vector dimensions")
    func hostEmbeddingProviderValidatesVectorDimensions() async throws {
        let provider = HostEmbeddingProvider(
            dimensions: Given.embeddingDimensions,
            embedBatch: { texts in
                texts.map { _ in [Float](repeating: 1, count: Given.embeddingDimensions - 1) }
            }
        )

        do {
            _ = try await provider.embed("invalid dimension")
            Issue.record("HostEmbeddingProvider must reject vectors with invalid dimensions")
        } catch HostEmbeddingProviderError.invalidDimensions(let expected, let actual) {
            #expect(expected == Given.embeddingDimensions)
            #expect(actual == Given.embeddingDimensions - 1)
        }
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

    @Test("Entity with an empty identifier fails before database insertion")
    func emptyEntityIdentifierFailsBeforeInsert() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
            embeddingProvider: StubEmbeddingProvider()
        )
        var person = TestPerson(name: "Alice", assertion: ":Alice a :Person .")
        person.id = ""
        var batch = MemoryBatch()
        batch.entity(person)

        do {
            try await memory.store(batch)
            Issue.record("Memory must reject an empty entity identifier")
        } catch MemoryError.invalidEntityIdentifier(let type) {
            #expect(type == TestPerson.persistableType)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try await memory._debugEntityCount(witness: TestPerson.self) == 0)
    }

    @Test("OntologyPolicy validation")
    func policyValidation() async throws {
        let memory = try await Memory(path: nil)
        #expect(memory.ontologyPolicy.validate(typeIRI: "ex:Person"))
        #expect(!memory.ontologyPolicy.validate(typeIRI: "ex:Spaceship"))
    }

    @Test("Client entity security policy evaluates authorization context")
    func entitySecurityPolicyEvaluatesAuthorization() async throws {
        let registration = try MemoryEntityRegistration(ProtectedTestPerson.self)
        var batch = MemoryBatch()
        batch.entity(ProtectedTestPerson(name: "Alice", assertion: ":Alice a :Person ."))

        let anonymousMemory = try await Memory(
            path: nil,
            entityRegistrations: [registration],
            embeddingProvider: StubEmbeddingProvider()
        )
        do {
            try await anonymousMemory.store(batch)
            Issue.record("Anonymous entity creation must be denied")
        } catch let error as SecurityError {
            #expect(error.operation == .create)
            #expect(error.targetType == ProtectedTestPerson.persistableType)
            #expect(error.userID == nil)
        }

        let authenticatedMemory = try await Memory(
            path: nil,
            entityRegistrations: [registration],
            embeddingProvider: StubEmbeddingProvider(),
            authorization: .authenticated(Principal(identifier: "test-user"))
        )
        try await authenticatedMemory.store(batch)
        let stored = try await authenticatedMemory._debugFetchAll(ProtectedTestPerson.self)
        #expect(stored.count == 1)
    }

    @Test("SQLite path stores and recalls typed RDF statements")
    func sqlitePathStoresAndRecallsStatements() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "swift-memory-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )

        do {
            let memory = try await Memory(
                path: directory.appending(path: "memory.sqlite").path
            )
            var batch = MemoryBatch()
            batch.triple("ex:person/alice", "rdf:type", "ex:Person")
            batch.triple("ex:person/alice", "rdfs:label", "Alice")
            try await memory.store(batch)

            let result = try await memory.recall(keywords: ["Alice"])
            #expect(result.entities.map(\.iri).contains("ex:person/alice"))
        }

        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove SQLite test directory: \(error)")
        }
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

    // MARK: - Entity Storage and Resolution

    @Test("Entity vector descriptor uses stable field identity")
    func entityVectorDescriptorUsesStableFieldIdentity() throws {
        let schema = try Schema(
            entities: [
                try TestPerson.schemaEntity,
                try TestOrganization.schemaEntity,
            ],
            version: Schema.Version(1, 0, 0)
        )

        let group = try #require(schema.polymorphicGroup(identifier: "Entity"))
        let declaration = try #require(
            group.indexes.first { $0.name == "Entity_vector_embedding" }
        )
        let personDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "Entity",
                memberType: TestPerson.self
            ).first { $0.name == declaration.name }
        )
        let organizationDescriptor = try #require(
            schema.polymorphicIndexDescriptors(
                identifier: "Entity",
                memberType: TestOrganization.self
            ).first { $0.name == declaration.name }
        )
        let personEmbedding = try #require(
            schema.entity(for: TestPerson.self)?.fieldMapByName["embedding"]
        )
        let organizationEmbedding = try #require(
            schema.entity(for: TestOrganization.self)?.fieldMapByName["embedding"]
        )

        #expect(declaration.type == .vector)
        #expect(declaration.fieldReferences == ["embedding"])
        #expect(
            personDescriptor.fieldIdentities == [
                FieldIdentity(
                    name: personEmbedding.name,
                    number: personEmbedding.fieldNumber
                )
            ]
        )
        #expect(
            organizationDescriptor.fieldIdentities == [
                FieldIdentity(
                    name: organizationEmbedding.name,
                    number: organizationEmbedding.fieldNumber
                )
            ]
        )
    }

    @Test("Entity vector index stores and resolves multiple concrete types")
    func entityVectorIndexStoresAndResolvesMultipleConcreteTypes() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [
                try MemoryEntityRegistration(TestPerson.self),
                try MemoryEntityRegistration(TestOrganization.self),
            ],
            embeddingProvider: StubEmbeddingProvider()
        )

        var batch = MemoryBatch()
        batch.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        batch.entity(TestOrganization(name: "Acme", domain: "acme.example", assertion: ":Acme a :Organization ."))
        batch.alias("Acme", for: ":Acme a :Organization .")
        batch.triple("Acme", "ex:operatesDomain", "acme.example")
        try await memory.store(batch)

        let persons = try await memory._debugEntities(witness: TestPerson.self)
        let organizations = try await memory._debugEntities(witness: TestOrganization.self)
        #expect(persons.count == 1)
        #expect(organizations.count == 1)

        let resolved = try await memory.resolve(
            [ResolveCandidate(assertion: ":Acme a :Organization .")],
            witness: TestOrganization.self
        )
        let first = try #require(resolved.first)
        #expect(first.hasCandidates)
        #expect(first.candidates.first?.assertion == ":Acme a :Organization .")
        #expect(first.candidates.first?.label == "Acme")
        #expect(first.candidates.first?.type == ":Organization")
        #expect(first.candidates.first?.context.contains { $0.predicate == "ex:operatesDomain" && $0.object == "acme.example" } == true)
        #expect((first.topSimilarity ?? 0) > 0.99)

        let typed = try await memory.resolve([
            TestOrganization(
                name: "Acme",
                domain: "acme.example",
                assertion: ":Acme a :Organization ."
            )
        ])
        #expect(typed.first?.candidates.first?.label == "Acme")
    }

    @Test("Direct database insert writes to polymorphic directory")
    func directInsertDualWrite() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
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

        // Bypass Memory's store pipeline and use the public database insert path
        // to isolate the dual-write code path from normal store logic.
        var alice = TestPerson(name: "Alice", assertion: ":Alice a :Person .")
        alice.embedding = try Vector(
            float32: [Float](repeating: 0, count: TestPerson.embeddingDimensions)
        )
        try await memory._debugCommittedDirectInsert(alice)

        let concrete = try await memory._debugFetchAll(TestPerson.self)
        let polymorphic = try await memory._debugEntities(witness: TestPerson.self)
        #expect(concrete.count == 1, "concrete fetch should see 1 record")
        #expect(polymorphic.count == 1,
                "polymorphic fetch should see 1 record; concrete=\(concrete.count)")
    }

    @Test("Entity with identical assertion is inserted when stored in separate payloads")
    func entityIdenticalAcrossPayloadsIsCallerControlled() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        var first = MemoryBatch()
        first.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        try await memory.store(first)

        let concreteAfterFirst = try await memory._debugFetchAll(TestPerson.self)
        let polyAfterFirst = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(concreteAfterFirst.count == 1)
        #expect(polyAfterFirst == 1)

        var second = MemoryBatch()
        second.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        try await memory.store(second)

        let concreteAfterSecond = try await memory._debugFetchAll(TestPerson.self)
        let polyAfterSecond = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(concreteAfterSecond.count == 2)
        #expect(polyAfterSecond == 2)
    }

    @Test("Entity with different assertion is inserted as a new record")
    func entityDifferentLabelIsNewRecord() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        var first = MemoryBatch()
        first.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        try await memory.store(first)

        var second = MemoryBatch()
        second.entity(TestPerson(name: "Bob", assertion: ":Bob a :Person ."))
        try await memory.store(second)

        let count = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(count == 2)
    }

    @Test("Duplicate entity in the same batch is inserted as a separate record")
    func entityDuplicateWithinBatchInsertsSeparately() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        var batch = MemoryBatch()
        batch.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        batch.entity(TestPerson(name: "Alice", assertion: ":Alice a :Person ."))
        try await memory.store(batch)

        let count = try await memory._debugEntityCount(witness: TestPerson.self)
        #expect(count == 2)
    }

    @Test("Statement can target an existing resolved entity ID without reinserting it")
    func statementCanTargetResolvedEntityID() async throws {
        let memory = try await Memory(
            path: nil,
            entityRegistrations: [try MemoryEntityRegistration(TestPerson.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        let assertion = ":Alice a :Person ."
        var initial = MemoryBatch()
        initial.entity(TestPerson(name: "Alice", assertion: assertion))
        try await memory.store(initial)

        let existing = try await memory._debugEntities(witness: TestPerson.self)
        let persistedAlice = try #require(existing.first)

        var followup = MemoryBatch()
        followup.triple(persistedAlice.id, "rdfs:comment", "loves memory")
        try await memory.store(followup)

        let entitiesAfterFollowup = try await memory._debugEntities(witness: TestPerson.self)
        #expect(entitiesAfterFollowup.count == 1)

        let statements = try await memory._debugFetchAll(Statement.self)
        let remapped = statements.first {
            MemoryRDF.value($0.predicate) == "rdfs:comment"
                && MemoryRDF.value($0.object) == "loves memory"
        }
        #expect(remapped.flatMap { MemoryRDF.value($0.subject) } == persistedAlice.id)
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
            entityRegistrations: [try MemoryEntityRegistration(TestOrganization.self)],
            embeddingProvider: StubEmbeddingProvider()
        )

        let assertion = ":TSMC a :Organization ."
        let partnerAssertion = ":UMC a :Organization ."
        var batch = MemoryBatch()
        batch.entity(TestOrganization(name: "TSMC", domain: "tsmc.com", assertion: assertion))
        batch.entity(TestOrganization(name: "UMC", domain: "umc.com", assertion: partnerAssertion))
        batch.alias("TSMC", for: assertion)
        batch.alias("UMC", for: partnerAssertion)
        batch.triple("TSMC", "ex:produces", "TSMC N2")
        batch.triple("TSMC", "ex:partnersWith", "UMC")
        try await memory.store(batch)

        let entities = try await memory._debugEntities(witness: TestOrganization.self)
        let tsmc = try #require(entities.first { $0.name == "TSMC" })
        let umc = try #require(entities.first { $0.name == "UMC" })
        let statements = try await memory._debugFetchAll(Statement.self)
        let remapped = statements.first {
            MemoryRDF.value($0.predicate) == "ex:produces"
                && MemoryRDF.value($0.object) == "TSMC N2"
        }
        let relationship = try #require(statements.first {
            MemoryRDF.value($0.predicate) == "ex:partnersWith"
        })

        #expect(remapped.flatMap { MemoryRDF.value($0.subject) } == tsmc.id)
        #expect(MemoryRDF.value(relationship.object) == umc.id)
        if case .iri = relationship.object {
            // Entity relationships must remain graph edges, not RDF literals.
        } else {
            Issue.record("Resolved entity objects must be stored as RDF resources")
        }
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
