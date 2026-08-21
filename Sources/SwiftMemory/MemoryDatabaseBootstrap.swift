@_spi(DatabaseExecution) import Database
import MemoryOntology

enum MemoryDatabaseBootstrap {
    private static let namespacePath = ["swift-memory"]

    static func requireAuthenticatedPrincipal(
        _ authorization: AuthorizationContext
    ) throws -> Principal {
        guard let principal = authorization.principal else {
            throw MemoryLayerError.authenticatedPrincipalRequired
        }
        return principal
    }

    static func localTopology(
        storageEngine: any StorageEngine,
        monotonicClock: any StorageMonotonicClock
    ) async throws -> DatabaseStorageTopology {
        try await rejectSingleDatabaseRoot(
            storageEngine: storageEngine,
            monotonicClock: monotonicClock
        )

        let domainID = try DatabaseStorageDomain.ID("swift-memory-local")
        let placementID = try Base.Placement.ID("layers")
        return try DatabaseStorageTopology(
            controlDomainID: domainID,
            domains: [
                try DatabaseStorageDomain(
                    id: domainID,
                    namespacePath: namespacePath,
                    storageEngine: storageEngine
                )
            ],
            placements: [
                try DatabaseStoragePlacement(
                    id: placementID,
                    domainID: domainID,
                    path: ["layers"]
                )
            ],
            defaultPlacementID: placementID
        )
    }

    static func open(
        schema: Schema,
        runtimeConfiguration: DatabaseRuntimeConfiguration,
        storageTopology: DatabaseStorageTopology,
        layerSet: MemoryLayerSet,
        ontologyPolicy: any OntologyPolicy,
        graphName: RDFGraphName,
        embeddingProvider: (any EmbeddingProvider)?,
        monotonicClock: any StorageMonotonicClock,
        wallClock: any WallClock,
        authorization: AuthorizationContext
    ) async throws -> MemoryDatabaseRuntime {
        let principal = try requireAuthenticatedPrincipal(authorization)

        let container = try await DBContainer.open(
            for: schema,
            configuration: DBConfiguration(
                storageTopology: storageTopology,
                monotonicClock: monotonicClock,
                wallClock: wallClock
            ),
            runtimeConfiguration: runtimeConfiguration
        )

        do {
            var contexts: [Base.ID: MemoryContext] = [:]
            contexts.reserveCapacity(layerSet.layers.count)
            for layer in layerSet.layers {
                _ = try await container.executionProvisionBaseRecord(
                    layer.baseID,
                    placementID: container.executionDefaultBasePlacementID,
                    initialGrants: [
                        Security.Grant(
                            subject: .principal(principal.identifier),
                            resource: .base(layer.baseID),
                            access: .all
                        )
                    ],
                    expectedRevision: 0
                )
                let databaseContext = container.session(
                    authorization: authorization
                ).base(layer.baseID).newContext()
                try await databaseContext.ontology.load(
                    ontologyPolicy.buildOntology(),
                    at: wallClock.now
                )
                contexts[layer.baseID] = MemoryContext(
                    databaseContext: databaseContext,
                    layer: layer,
                    graphName: graphName,
                    embeddingProvider: embeddingProvider,
                    wallClock: wallClock
                )
            }
            return MemoryDatabaseRuntime(
                container: container,
                contexts: contexts,
                authorization: authorization
            )
        } catch {
            await container.shutdown()
            throw error
        }
    }

    private static func rejectSingleDatabaseRoot(
        storageEngine: any StorageEngine,
        monotonicClock: any StorageMonotonicClock
    ) async throws {
        do {
            let descriptor = try await DatabaseFormatCatalog(
                database: storageEngine,
                clock: monotonicClock
            ).loadRequired()
            switch descriptor.layoutKind {
            case .singleDatabase:
                throw MemoryLayerError.singleDatabaseMigrationRequired
            case .multiBase:
                throw MemoryLayerError.unexpectedRootStorageLayout(
                    descriptor.layoutKind
                )
            }
        } catch DatabaseFormatCatalogError.missingDescriptor {
            // Continue below. Current MultiBase stores keep their descriptor
            // under the configured domain namespace, not at the engine root.
        }

        var namespaceRoot = Subspace()
        for component in namespacePath {
            namespaceRoot = namespaceRoot.subspace(component)
        }
        do {
            let descriptor = try await DatabaseFormatCatalog(
                database: storageEngine,
                root: namespaceRoot,
                clock: monotonicClock
            ).loadRequired()
            switch descriptor.layoutKind {
            case .multiBase:
                return
            case .singleDatabase:
                throw MemoryLayerError.singleDatabaseMigrationRequired
            }
        } catch DatabaseFormatCatalogError.missingDescriptor {
            guard try await containsAnyRootKey(
                storageEngine: storageEngine,
                monotonicClock: monotonicClock
            ) else {
                return
            }
            throw MemoryLayerError.singleDatabaseMigrationRequired
        }
    }

    private static func containsAnyRootKey(
        storageEngine: any StorageEngine,
        monotonicClock: any StorageMonotonicClock
    ) async throws -> Bool {
        let range = Subspace().range()
        return try await StorageTransactionExecutor(
            engine: storageEngine
        ).withTransaction(
            configuration: .default,
            clock: monotonicClock
        ) { transaction in
            let rows = try await TransactionRangeCollection.collect(
                using: transaction,
                from: .firstGreaterOrEqual(range.begin),
                to: .firstGreaterOrEqual(range.end),
                limit: 1,
                reverse: false,
                snapshot: true,
                streamingMode: .small
            )
            return !rows.isEmpty
        }
    }
}
