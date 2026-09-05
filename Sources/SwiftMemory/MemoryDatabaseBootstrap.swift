@_spi(DatabaseExecution) import Database
import MemoryOntology

enum MemoryDatabaseBootstrap {
    private static let rootPath = ["swift-memory"]

    static func requireAuthenticatedPrincipal(
        _ authorization: AuthorizationContext
    ) throws -> Principal {
        guard let principal = authorization.principal else {
            throw MemoryLayerError.authenticatedPrincipalRequired
        }
        return principal
    }

    static func localTopology(
        storageEngine: any StorageEngine
    ) throws -> DatabaseStorageTopology {
        let domainID = try DatabaseStorageDomain.ID("swift-memory-local")
        let placementID = try Base.Placement.ID("layers")
        return try DatabaseStorageTopology(
            controlDomainID: domainID,
            domains: [
                try DatabaseStorageDomain(
                    id: domainID,
                    rootPath: rootPath,
                    storageEngine: storageEngine
                )
            ],
            placements: [
                DatabaseStoragePlacement(
                    id: placementID,
                    domainID: domainID
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

}
