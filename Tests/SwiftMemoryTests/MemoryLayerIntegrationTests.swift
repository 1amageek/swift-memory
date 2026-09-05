import Database
import Foundation
import Testing
@testable import SwiftMemory

private struct LayerEmbeddingProvider: EmbeddingProvider {
    let dimensions = Given.embeddingDimensions

    func embed(_ text: String) async throws -> [Float] {
        _ = text
        var vector = [Float](repeating: 0, count: dimensions)
        vector[0] = 1
        return vector
    }
}

@Suite("Memory Layer Integration Tests", .serialized)
struct MemoryLayerIntegrationTests {
    @Test("Default and explicit layers isolate equal identifiers")
    func layersIsolateEqualIdentifiers() async throws {
        let personal = try MemoryLayer(id: "personal", name: "Personal")
        let shared = try MemoryLayer(id: "shared", name: "Shared")
        let layerSet = try MemoryLayerSet(
            [personal, shared],
            default: personal
        )
        let memory = try await Memory(path: nil, layerSet: layerSet)

        var personalBatch = MemoryBatch()
        personalBatch.triple("ex:knowledge", "rdf:type", "ex:Knowledge")
        personalBatch.triple("ex:knowledge", "rdfs:label", "Personal Knowledge")
        try await memory.store(personalBatch)

        var sharedBatch = MemoryBatch()
        sharedBatch.triple("ex:knowledge", "rdf:type", "ex:Knowledge")
        sharedBatch.triple("ex:knowledge", "rdfs:label", "Shared Knowledge")
        try await memory.store(sharedBatch, in: shared)

        let personalRecall = try await memory.recall(
            keywords: ["Knowledge"],
            in: personal
        )
        let sharedRecall = try await memory.recall(
            keywords: ["Knowledge"],
            in: shared
        )

        #expect(personalRecall.entities.map(\.label) == ["Personal Knowledge"])
        #expect(sharedRecall.entities.map(\.label) == ["Shared Knowledge"])
        #expect(personalRecall.entities.map(\.iri) == ["ex:knowledge"])
        #expect(sharedRecall.entities.map(\.iri) == ["ex:knowledge"])
        await memory.shutdown()
    }

    @Test("Cross-layer recall preserves requested Base order and origin")
    func crossLayerRecallPreservesOrigin() async throws {
        let personal = try MemoryLayer(id: "personal", name: "Personal")
        let shared = try MemoryLayer(id: "shared", name: "Shared")
        let memory = try await Memory(
            path: nil,
            layerSet: try MemoryLayerSet([personal, shared], default: personal),
            embeddingProvider: LayerEmbeddingProvider()
        )

        var personalBatch = MemoryBatch()
        personalBatch.triple("ex:knowledge", "rdfs:label", "Personal Knowledge")
        try await memory.store(personalBatch, in: personal)

        var sharedBatch = MemoryBatch()
        sharedBatch.triple("ex:knowledge", "rdfs:label", "Shared Knowledge")
        try await memory.store(sharedBatch, in: shared)

        let result = try await memory.recall(
            RecallQuery(keywords: ["Knowledge"]),
            across: [shared, personal]
        )

        #expect(result.layers.map(\.layer) == [shared, personal])
        #expect(result.layers[0].result.entities.map(\.label) == ["Shared Knowledge"])
        #expect(result.layers[1].result.entities.map(\.label) == ["Personal Knowledge"])
        #expect(result.layers.allSatisfy {
            $0.result.entities.map(\.iri) == ["ex:knowledge"]
        })

        var personalGivenBatch = MemoryBatch()
        personalGivenBatch.triple("ex:personal-anchor", "rdfs:label", "Personal Anchor")
        try await memory.store(
            given: "personal payload",
            knowledge: personalGivenBatch,
            in: personal
        )
        var sharedGivenBatch = MemoryBatch()
        sharedGivenBatch.triple("ex:shared-anchor", "rdfs:label", "Shared Anchor")
        try await memory.store(
            given: "shared payload",
            knowledge: sharedGivenBatch,
            in: shared
        )
        var embedding = [Float](repeating: 0, count: Given.embeddingDimensions)
        embedding[0] = 1
        let givenResult = try await memory.recall(
            RecallQuery(embedding: embedding),
            across: [personal, shared]
        )
        #expect(givenResult.layers[0].result.givens.map(\.payloadRef) == ["personal payload"])
        #expect(givenResult.layers[1].result.givens.map(\.payloadRef) == ["shared payload"])
        await memory.shutdown()
    }

    @Test("Unknown and duplicate layer selections fail explicitly")
    func invalidLayerSelectionsFail() async throws {
        let personal = try MemoryLayer(id: "personal")
        let shared = try MemoryLayer(id: "shared")
        let memory = try await Memory(
            path: nil,
            layerSet: try MemoryLayerSet([personal])
        )

        do {
            _ = try await memory.recall(keywords: ["Knowledge"], in: shared)
            Issue.record("Recall must reject a layer outside the configured set")
        } catch MemoryLayerError.layerNotConfigured(let baseID) {
            #expect(baseID == shared.baseID)
        }

        do {
            _ = try await memory.recall(
                RecallQuery(keywords: ["Knowledge"]),
                across: [personal, personal]
            )
            Issue.record("Recall must reject duplicate layer selections")
        } catch MemoryLayerError.duplicateLayer(let baseID) {
            #expect(baseID == personal.baseID)
        }
        await memory.shutdown()
    }

    @Test("SQLite MultiBase layers persist across reopen")
    func sqliteLayersPersistAcrossReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "swift-memory-layer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let path = directory.appending(path: "memory.sqlite").path
        let personal = try MemoryLayer(id: "personal")
        let shared = try MemoryLayer(id: "shared")
        let layerSet = try MemoryLayerSet([personal, shared], default: personal)

        do {
            let memory = try await Memory(path: path, layerSet: layerSet)
            var personalBatch = MemoryBatch()
            personalBatch.triple("ex:personal", "rdfs:label", "Personal Durable")
            try await memory.store(personalBatch, in: personal)

            var sharedBatch = MemoryBatch()
            sharedBatch.triple("ex:shared", "rdfs:label", "Shared Durable")
            try await memory.store(sharedBatch, in: shared)
            await memory.shutdown()
        }

        do {
            _ = try await Memory(
                path: path,
                layerSet: layerSet,
                authorization: .authenticated(
                    Principal(identifier: "different-principal")
                )
            )
            Issue.record("A principal without persisted Base Grants must be denied")
        } catch is DatabaseGrantAuthorizationError {
            // Expected fail-closed Base authorization.
        }

        do {
            let memory = try await Memory(path: path, layerSet: layerSet)
            let personalResult = try await memory.recall(
                keywords: ["Durable"],
                in: personal
            )
            let sharedResult = try await memory.recall(
                keywords: ["Durable"],
                in: shared
            )
            #expect(personalResult.entities.map(\.iri) == ["ex:personal"])
            #expect(sharedResult.entities.map(\.iri) == ["ex:shared"])
            await memory.shutdown()
        }

        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Failed to remove SQLite test directory: \(error)")
        }
    }

    @Test("Anonymous authorization is rejected before Base provisioning")
    func anonymousAuthorizationFails() async throws {
        do {
            _ = try await Memory(path: nil, authorization: .anonymous)
            Issue.record("MultiBase Memory must require an authenticated principal")
        } catch MemoryLayerError.authenticatedPrincipalRequired {
            // Expected typed failure.
        }
    }

    @Test("A single-database root requires explicit migration")
    func singleDatabaseRootRequiresMigration() async throws {
        let engine = InMemoryEngine()
        let descriptor = DatabaseFormatDescriptor.current(
            layoutKind: .singleDatabase,
            itemStorage: .v1
        )
        let descriptorKey = Subspace()
            .subspace("_database-framework")
            .pack(Tuple("format"))
        _ = try await StorageTransactionExecutor(engine: engine).withTransaction(
            configuration: .default,
            clock: MemoryMonotonicClock()
        ) { transaction in
            try transaction.setValue(descriptor.serialize(), for: descriptorKey)
        }

        do {
            _ = try await Memory(storageEngine: engine)
            Issue.record("Single-database storage must not be opened as MultiBase")
        } catch let error as StorageError {
            #expect(error.code == .incompatibleStorageLayout)
        }
        await engine.shutdown()
    }

    @Test("A descriptorless nonempty root is rejected without mutation")
    func descriptorlessRootRequiresMigration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "swift-memory-layout-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let path = directory.appending(path: "memory.sqlite").path
        let lowKey: ByteString = [0x01]
        let lowValue: ByteString = [0x11]
        let highKey: ByteString = [0xFF]
        let highValue: ByteString = [0xEE]
        let engine = try SQLiteStorageEngine(configuration: .file(path))
        _ = try await StorageTransactionExecutor(engine: engine).withTransaction(
            configuration: .default,
            clock: MemoryMonotonicClock()
        ) { transaction in
            try transaction.setValue(lowValue, for: lowKey)
            try transaction.setValue(highValue, for: highKey)
        }
        await engine.shutdown()

        do {
            _ = try await Memory(path: path)
            Issue.record("Unknown nonempty storage must not be claimed as MultiBase")
        } catch let error as StorageError {
            #expect(error.code == .incompatibleStorageLayout)
        }

        let reopenedEngine = try SQLiteStorageEngine(configuration: .file(path))
        let entries = try await StorageTransactionExecutor(engine: reopenedEngine)
            .withTransaction(
                configuration: .default,
                clock: MemoryMonotonicClock()
            ) { transaction in
                try await TransactionRangeCollection.collect(
                    using: transaction,
                    from: .firstGreaterOrEqual([]),
                    to: .firstGreaterThan([0xFF]),
                    limit: 16,
                    reverse: false,
                    snapshot: true,
                    streamingMode: .small
                )
            }
        #expect(entries.map { Array($0.0) } == [[0x01], [0xFF]])
        #expect(entries.map { Array($0.1) } == [[0x11], [0xEE]])
        await reopenedEngine.shutdown()
        try FileManager.default.removeItem(at: directory)
    }

    @Test("A legacy tuple-namespace MultiBase root is rejected")
    func legacyTupleNamespaceRootRequiresMigration() async throws {
        let engine = InMemoryEngine()
        let descriptor = DatabaseFormatDescriptor.current(
            layoutKind: .multiBase,
            itemStorage: .v1
        )
        let descriptorKey = Subspace()
            .subspace("swift-memory")
            .subspace("_database-framework")
            .pack(Tuple("format"))
        _ = try await StorageTransactionExecutor(engine: engine).withTransaction(
            configuration: .default,
            clock: MemoryMonotonicClock()
        ) { transaction in
            try transaction.setValue(descriptor.serialize(), for: descriptorKey)
        }

        do {
            _ = try await Memory(storageEngine: engine)
            Issue.record("Legacy tuple-namespace storage must not be adopted")
        } catch let error as StorageError {
            #expect(error.code == .incompatibleStorageLayout)
        }
        await engine.shutdown()
    }
}
