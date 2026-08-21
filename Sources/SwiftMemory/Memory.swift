// Memory.swift
// Knowledge persistence and recall

#if canImport(Foundation)
import Foundation
#endif
@_spi(DatabaseExecution) import Database
import MemoryOntology

/// Knowledge persistence and recall system.
///
/// Memory stores and recalls knowledge. It does **not** interpret raw input.
///
/// Interpretation is the responsibility of an external caller:
/// - The caller analyzes raw input and structures knowledge
/// - The caller calls `store(batch)` with entities and relationships
/// - Memory persists them and enables recall via spreading activation
///
/// Entities are inserted as provided. Identity against already-persisted
/// entities is handled by resolve → caller judgment → store.
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     entityRegistrations: [
///         try MemoryEntityRegistration(Person.self),
///         try MemoryEntityRegistration(Organization.self),
///     ],
///     embeddingProvider: MLXEmbeddingProvider()
/// )
///
/// // Store structured knowledge
/// var batch = MemoryBatch()
/// batch.entity(person)
/// batch.triple("ex:alice", "ex:worksAt", "ex:acme")
/// try await memory.store(batch)
///
/// // Recall associated knowledge
/// let result = try await memory.recall(keywords: ["Alice"])
/// ```
public actor Memory {

    /// Stable local owner used when an application does not inject identity.
    public static let localAuthorization = AuthorizationContext.authenticated(
        Principal(identifier: "swift-memory.local")
    )

    /// Default cosine-similarity threshold used by `resolve()` to surface
    /// possible matches to the caller.
    public static let defaultResolveThreshold: Float = 0.90

    /// Default maximum number of candidates returned per input by `resolve()`.
    public static let defaultResolveLimit: Int = 30

    private static let resolutionSearchLimit = 30

    private let contexts: [Base.ID: MemoryContext]
    private let container: DBContainer
    private let authorization: AuthorizationContext

    public nonisolated let ontologyPolicy: any OntologyPolicy
    public nonisolated let layerSet: MemoryLayerSet

    public nonisolated var layers: [MemoryLayer] { layerSet.layers }
    public nonisolated var defaultLayer: MemoryLayer { layerSet.defaultLayer }

    public init(
        path: String?,
        layerSet: MemoryLayerSet? = nil,
        entityRegistrations: [MemoryEntityRegistration] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil,
        monotonicClock: any StorageMonotonicClock = MemoryMonotonicClock(),
        wallClock: any WallClock = MemoryWallClock(),
        authorization: AuthorizationContext = Memory.localAuthorization
    ) async throws {
        _ = try MemoryDatabaseBootstrap.requireAuthenticatedPrincipal(authorization)
        let resolvedLayerSet: MemoryLayerSet
        if let layerSet {
            resolvedLayerSet = layerSet
        } else {
            resolvedLayerSet = try MemoryLayerSet.local()
        }
        let (schema, runtimeConfiguration) = try Self.databaseDefinition(
            entityRegistrations: entityRegistrations
        )
        let graph = try MemoryRDF.graphName(graphName)

        let storageEngine: any StorageEngine
        #if os(WASI)
        guard path == nil else {
            throw MemoryError.pathBackedStorageUnavailableOnWASI
        }
        storageEngine = InMemoryEngine()
        #else
        if let path {
            storageEngine = try SQLiteStorageEngine(
                configuration: .file(path)
            )
        } else {
            storageEngine = InMemoryEngine()
        }
        #endif

        let storageTopology: DatabaseStorageTopology
        do {
            storageTopology = try await MemoryDatabaseBootstrap.localTopology(
                storageEngine: storageEngine,
                monotonicClock: monotonicClock
            )
        } catch {
            await storageEngine.shutdown()
            throw error
        }
        let runtime = try await MemoryDatabaseBootstrap.open(
            schema: schema,
            runtimeConfiguration: runtimeConfiguration,
            storageTopology: storageTopology,
            layerSet: resolvedLayerSet,
            ontologyPolicy: ontologyPolicy,
            graphName: graph,
            embeddingProvider: embeddingProvider,
            monotonicClock: monotonicClock,
            wallClock: wallClock,
            authorization: authorization
        )
        self.ontologyPolicy = ontologyPolicy
        self.layerSet = resolvedLayerSet
        self.container = runtime.container
        self.contexts = runtime.contexts
        self.authorization = runtime.authorization
    }

    /// Create Memory with an explicit storage engine.
    ///
    /// This initializer is the preferred embedding point for WASM hosts that
    /// provide their own StorageKit-backed persistence boundary.
    public init(
        storageEngine: any StorageEngine,
        layerSet: MemoryLayerSet? = nil,
        entityRegistrations: [MemoryEntityRegistration] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil,
        monotonicClock: any StorageMonotonicClock = MemoryMonotonicClock(),
        wallClock: any WallClock = MemoryWallClock(),
        authorization: AuthorizationContext = Memory.localAuthorization
    ) async throws {
        _ = try MemoryDatabaseBootstrap.requireAuthenticatedPrincipal(authorization)
        let resolvedLayerSet: MemoryLayerSet
        if let layerSet {
            resolvedLayerSet = layerSet
        } else {
            resolvedLayerSet = try MemoryLayerSet.local()
        }
        let (schema, runtimeConfiguration) = try Self.databaseDefinition(
            entityRegistrations: entityRegistrations
        )
        let graph = try MemoryRDF.graphName(graphName)
        let storageTopology = try await MemoryDatabaseBootstrap.localTopology(
            storageEngine: storageEngine,
            monotonicClock: monotonicClock
        )
        let runtime = try await MemoryDatabaseBootstrap.open(
            schema: schema,
            runtimeConfiguration: runtimeConfiguration,
            storageTopology: storageTopology,
            layerSet: resolvedLayerSet,
            ontologyPolicy: ontologyPolicy,
            graphName: graph,
            embeddingProvider: embeddingProvider,
            monotonicClock: monotonicClock,
            wallClock: wallClock,
            authorization: authorization
        )
        self.ontologyPolicy = ontologyPolicy
        self.layerSet = resolvedLayerSet
        self.container = runtime.container
        self.contexts = runtime.contexts
        self.authorization = runtime.authorization
    }

    /// Create Memory with a host-owned MultiBase storage topology.
    public init(
        storageTopology: DatabaseStorageTopology,
        layerSet: MemoryLayerSet,
        entityRegistrations: [MemoryEntityRegistration] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil,
        monotonicClock: any StorageMonotonicClock = MemoryMonotonicClock(),
        wallClock: any WallClock = MemoryWallClock(),
        authorization: AuthorizationContext = Memory.localAuthorization
    ) async throws {
        _ = try MemoryDatabaseBootstrap.requireAuthenticatedPrincipal(authorization)
        let (schema, runtimeConfiguration) = try Self.databaseDefinition(
            entityRegistrations: entityRegistrations
        )
        let graph = try MemoryRDF.graphName(graphName)
        let runtime = try await MemoryDatabaseBootstrap.open(
            schema: schema,
            runtimeConfiguration: runtimeConfiguration,
            storageTopology: storageTopology,
            layerSet: layerSet,
            ontologyPolicy: ontologyPolicy,
            graphName: graph,
            embeddingProvider: embeddingProvider,
            monotonicClock: monotonicClock,
            wallClock: wallClock,
            authorization: authorization
        )
        self.ontologyPolicy = ontologyPolicy
        self.layerSet = layerSet
        self.container = runtime.container
        self.contexts = runtime.contexts
        self.authorization = runtime.authorization
    }

    private static func databaseDefinition(
        entityRegistrations: [MemoryEntityRegistration]
    ) throws -> (Schema, DatabaseRuntimeConfiguration) {
        let internalRuntimes = [
            try DatabaseFrameworkRuntime.entity(Given.self),
            try DatabaseFrameworkRuntime.entity(Statement.self),
            try DatabaseFrameworkRuntime.entity(Trace.self),
        ]
        let runtimes = internalRuntimes + entityRegistrations.map { $0.runtime }
        let schema = try Schema(
            entities: runtimes.map { $0.entity },
            version: Schema.Version(3, 0, 0)
        )
        let runtimeConfiguration = try DatabaseFrameworkRuntime.configuration(
            executionIdentity: DatabaseExecutionRuntimeIdentity(
                identifier: "swift-memory",
                revision: 2
            ),
            entityRuntimes: runtimes,
            authorizationPolicies: [
                AuthorizationPolicyHandler(Given.self),
                AuthorizationPolicyHandler(Statement.self),
                AuthorizationPolicyHandler(Trace.self),
            ] + entityRegistrations.map { $0.authorizationPolicy }
        )
        return (schema, runtimeConfiguration)
    }

    private func context(for layer: MemoryLayer) throws -> MemoryContext {
        guard layerSet.contains(layer), let context = contexts[layer.baseID] else {
            throw MemoryLayerError.layerNotConfigured(layer.baseID)
        }
        return context
    }

    private func selectedLayers(
        _ requestedLayers: [MemoryLayer]?
    ) throws -> [(layer: MemoryLayer, context: MemoryContext)] {
        let selection = requestedLayers ?? layers
        guard !selection.isEmpty else {
            throw MemoryLayerError.emptyLayerSelection
        }

        var seen: Set<Base.ID> = []
        var selected: [(layer: MemoryLayer, context: MemoryContext)] = []
        selected.reserveCapacity(selection.count)
        for layer in selection {
            guard seen.insert(layer.baseID).inserted else {
                throw MemoryLayerError.duplicateLayer(layer.baseID)
            }
            let layerContext = try context(for: layer)
            selected.append((layerContext.layer, layerContext))
        }
        return selected
    }

    private func authorizeCompositionRead(
        _ selected: [(layer: MemoryLayer, context: MemoryContext)]
    ) async throws {
        let source = try container
            .session(authorization: authorization)
            .composition(bases: selected.map { $0.layer.baseID })
        _ = try await source.resolve()
    }

    // MARK: - Store

    /// Store Given + Knowledge atomically.
    ///
    /// Given is the raw material. Knowledge is the structured interpretation.
    /// Entities are inserted as provided; statements are remapped to identifiers
    /// created in the payload or registered aliases. Trace records link each
    /// Statement back to its source Given.
    public func store(given: any Memorable, knowledge: any MemoryBatchConvertible) async throws {
        try await store(given: given, knowledge: knowledge, in: defaultLayer)
    }

    /// Store Given + Knowledge atomically in one layer.
    public func store(
        given: any Memorable,
        knowledge: any MemoryBatchConvertible,
        in layer: MemoryLayer
    ) async throws {
        let batch = knowledge.toBatch()
        try await persist(
            given: given,
            batch: batch,
            context: try context(for: layer)
        )
    }

    #if canImport(Foundation)
    /// Store Given + Knowledge from raw JSON data and a decode closure.
    /// Used by transport adapters where knowledge arrives as JSON bytes.
    public func store(
        given: any Memorable,
        knowledgeData: Data,
        decode: @Sendable (Data) throws -> MemoryBatch
    ) async throws {
        try await store(
            given: given,
            knowledgeData: knowledgeData,
            decode: decode,
            in: defaultLayer
        )
    }

    /// Store Given + Knowledge from JSON data in one layer.
    public func store(
        given: any Memorable,
        knowledgeData: Data,
        decode: @Sendable (Data) throws -> MemoryBatch,
        in layer: MemoryLayer
    ) async throws {
        let batch = try decode(knowledgeData)
        try await persist(
            given: given,
            batch: batch,
            context: try context(for: layer)
        )
    }
    #endif

    /// Store a batch directly (without Given).
    /// No Trace records are created because there is no Given to link from.
    public func store(_ batch: MemoryBatch) async throws {
        try await store(batch, in: defaultLayer)
    }

    /// Store a batch directly in one layer.
    public func store(_ batch: MemoryBatch, in layer: MemoryLayer) async throws {
        try await persist(
            given: nil,
            batch: batch,
            context: try context(for: layer)
        )
    }

    // MARK: - Persist (shared implementation)

    private func persist(
        given: (any Memorable)?,
        batch: MemoryBatch,
        context: MemoryContext
    ) async throws {
        guard !batch.entities.isEmpty || !batch.statements.isEmpty else {
            MemoryLog.info(category: "Memory", "[store] empty knowledge - nothing saved")
            return
        }

        let now = context.wallClock.now
        let graphValue = MemoryRDF.graphValue(context.graphName)

        // Entity insertion (requires embedding provider when entities exist).
        var entityReferenceMap: [String: String] = [:]
        if !batch.entities.isEmpty {
            guard let provider = context.embeddingProvider else {
                throw MemoryError.embeddingProviderRequired
            }
            entityReferenceMap = try await insertEntities(
                batch.entities,
                provider: provider,
                context: context
            )
        }

        // Given record (requires embedding provider when given is present).
        var givenID: String?
        if let given {
            guard let provider = context.embeddingProvider else {
                throw MemoryError.embeddingProviderRequired
            }
            let id = try MemoryIdentifier.ulid(at: now)
            let embedding = try Self.requireEmbedding(
                try await provider.embed(given.payloadRef),
                dimensions: Given.embeddingDimensions
            )
            let record = Given(
                id: id,
                modality: given.modality,
                payloadRef: given.payloadRef,
                embedding: try Vector(float32: embedding),
                timestamp: now,
                source: "given"
            )
            try context.databaseContext.insert(record)
            givenID = id
        }

        let endpointResolver = StatementEndpointResolver(
            entityReferences: entityReferenceMap,
            aliases: batch.aliases
        )

        // Statements + optional traces. Endpoints that match a resolved entity
        // ID, assertion, or alias are rewritten to the canonical entity ID.
        // Non-matching endpoints remain loose graph terms.
        for record in batch.statements {
            let subject = endpointResolver.resolve(record.subject)
            let object = endpointResolver.resolve(record.object)
            let statementID = Statement.contentID(
                graph: graphValue,
                subject: subject.value,
                predicate: record.predicate,
                object: object.value
            )
            var statement = Statement(
                graph: MemoryRDF.graphTerm(context.graphName),
                subject: try MemoryRDF.resourceTerm(subject.value),
                predicate: try MemoryRDF.predicateTerm(record.predicate),
                object: try object.rdfTerm
            )
            statement.id = statementID
            try context.databaseContext.upsert(statement)

            if let givenID {
                var trace = Trace()
                trace.id = "\(givenID)|\(statementID)"
                trace.givenID = givenID
                trace.statementID = statementID
                try context.databaseContext.insert(trace)
            }
        }

        try await context.databaseContext.save()
        MemoryLog.info(
            category: "Memory",
            "[store] given=\(givenID ?? "-") entities=\(batch.entities.count) statements=\(batch.statements.count)"
        )
    }

    // MARK: - Entity Insertion

    /// Insert each entity in the batch and return endpoint mappings for the
    /// statements that follow. Store-time entity deduplication is deliberately
    /// not performed here; callers must use `resolve` before `store` when they
    /// want to reuse an existing entity ID.
    ///
    /// - Returns: Map from input entity IDs/assertions to the resolved entity ID.
    private func insertEntities(
        _ entities: [MemoryEntityRecord],
        provider: any EmbeddingProvider,
        context: MemoryContext
    ) async throws -> [String: String] {
        var entityReferenceMap: [String: String] = [:]
        entityReferenceMap.reserveCapacity(entities.count)

        let queryVectors = try Self.requireEmbeddingBatch(
            try await provider.embed(entities.map { $0.assertion }),
            expectedCount: entities.count
        )

        for (entity, queryVector) in zip(entities, queryVectors) {
            guard !entity.id.isEmpty else {
                throw MemoryError.invalidEntityIdentifier(type: entity.type)
            }
            let queryVec = try Self.requireEmbedding(
                queryVector,
                dimensions: entity.embeddingDimensions
            )
            let inputID = entity.id

            try entity.insert(
                embedding: try Vector(float32: queryVec),
                into: context.databaseContext
            )

            let newID = entity.id
            try insertEntityIdentityStatements(
                id: newID,
                entity: entity,
                context: context
            )
            entityReferenceMap[entity.assertion] = newID
            entityReferenceMap[inputID] = newID
            entityReferenceMap[newID] = newID

            MemoryLog.info(category: "Memory", "[store] inserted entity '\(Self.shortAssertion(entity.assertion))' id=\(newID)")
        }

        return entityReferenceMap
    }

    private func insertEntityIdentityStatements(
        id: String,
        entity: MemoryEntityRecord,
        context: MemoryContext
    ) throws {
        let label = entity.label.flatMap { $0.isEmpty ? nil : $0 } ?? id
        let type = entityType(
            from: entity.assertion,
            fallback: "memory:type/\(entity.type)"
        )

        try insertIdentityStatement(
            subject: id,
            predicate: "rdf:type",
            object: try MemoryRDF.resourceTerm(type),
            context: context
        )
        try insertIdentityStatement(
            subject: id,
            predicate: "rdfs:label",
            object: .string(label),
            context: context
        )
    }

    private func insertIdentityStatement(
        subject: String,
        predicate: String,
        object: RDFTerm,
        context: MemoryContext
    ) throws {
        guard !subject.isEmpty else {
            throw MemoryError.invalidRDFTerm(position: "subject", value: subject)
        }
        guard !predicate.isEmpty else {
            throw MemoryError.invalidRDFTerm(position: "predicate", value: predicate)
        }
        let graphValue = MemoryRDF.graphValue(context.graphName)
        guard let objectValue = MemoryRDF.value(object) else {
            throw MemoryError.invalidRDFTerm(
                position: "object",
                value: object.description
            )
        }
        let statementID = Statement.contentID(
            graph: graphValue,
            subject: subject,
            predicate: predicate,
            object: objectValue
        )
        var statement = Statement(
            graph: MemoryRDF.graphTerm(context.graphName),
            subject: try MemoryRDF.resourceTerm(subject),
            predicate: try MemoryRDF.predicateTerm(predicate),
            object: object
        )
        statement.id = statementID
        try context.databaseContext.insert(statement)
    }

    private struct StatementEndpointResolver {
        let entityReferences: [String: String]
        let aliases: [String: String]

        func resolve(_ endpoint: String) -> ResolvedStatementEndpoint {
            if let id = entityReferences[endpoint] {
                return .entityReference(id)
            }

            if let aliasTarget = aliases[endpoint],
               let id = entityReferences[aliasTarget] {
                return .entityReference(id)
            }

            let key = normalized(endpoint)
            if let id = entityReferences.first(where: { normalized($0.key) == key })?.value {
                return .entityReference(id)
            }

            if let aliasTarget = aliases.first(where: { normalized($0.key) == key })?.value,
               let id = entityReferences[aliasTarget] {
                return .entityReference(id)
            }

            return .loose(endpoint)
        }

        private func normalized(_ value: String) -> String {
            var lowerBound = value.startIndex
            var upperBound = value.endIndex

            while lowerBound < upperBound, Self.isEndpointWhitespace(value[lowerBound]) {
                lowerBound = value.index(after: lowerBound)
            }
            while lowerBound < upperBound {
                let previous = value.index(before: upperBound)
                guard Self.isEndpointWhitespace(value[previous]) else { break }
                upperBound = previous
            }

            return value[lowerBound..<upperBound].lowercased()
        }

        private static func isEndpointWhitespace(_ character: Character) -> Bool {
            character == " " || character == "\n" || character == "\r" || character == "\t"
        }
    }

    private struct ResolvedStatementEndpoint {
        let value: String
        let isEntityReference: Bool

        static func entityReference(_ value: String) -> Self {
            Self(value: value, isEntityReference: true)
        }

        static func loose(_ value: String) -> Self {
            Self(value: value, isEntityReference: false)
        }

        var rdfTerm: RDFTerm {
            get throws {
                if isEntityReference {
                    return try MemoryRDF.resourceTerm(value)
                }
                return try MemoryRDF.objectTerm(value)
            }
        }
    }

    /// Return up to `k` persisted `E` entities.
    /// whose cosine similarity to `embedding` clears `threshold`, sorted by
    /// similarity descending.
    ///
    /// Used by the public `resolve` API to surface possible matches for
    /// external caller judgment. Store-time persistence does not call this path
    /// for already-persisted entities.
    private final func topPersistedCandidates<E: Persistable & Entity & Sendable>(
        witness: E.Type,
        embedding: [Float],
        threshold: Float,
        k: Int,
        searchLimit: Int,
        context: MemoryContext
    ) async throws -> [ResolvedMatch] {
        guard k > 0 else { return [] }

        let page = try await context.databaseContext.findPolymorphic(E.self)
            .vector(try E.persistedEmbeddingField(), dimensions: E.embeddingDimensions)
            .query(embedding, k: searchLimit)
            .metric(.cosine)
            .executePage()

        var matches: [(id: String, assertion: String, similarity: Float, label: String, type: String)] = []
        matches.reserveCapacity(min(k, page.results.count))

        for result in page.results {
            guard result.typeName == E.persistableType else { continue }
            guard let distance = result.annotations["distance"]?.float64Value else {
                throw MemoryError.invalidQuery("polymorphic vector result is missing distance annotation")
            }
            let similarity = 1 - Float(distance)
            guard similarity >= threshold else { continue }
            let entity = try result.decode(as: E.self)
            let id = entity.memoryID
            let label = entity.memoryLabel ?? id
            let type = entityType(
                from: entity.assertion,
                fallback: "memory:type/\(E.persistableType)"
            )
            matches.append((
                id: id,
                assertion: entity.assertion,
                similarity: similarity,
                label: label,
                type: type
            ))
        }

        matches.sort { $0.similarity > $1.similarity }
        if matches.count > k {
            matches = Array(matches.prefix(k))
        }
        var resolvedMatches: [ResolvedMatch] = []
        resolvedMatches.reserveCapacity(matches.count)
        for match in matches {
            let statements = try await resolveOneHopContext(
                for: match.id,
                context: context
            )
            resolvedMatches.append(ResolvedMatch(
                id: match.id,
                assertion: match.assertion,
                similarity: match.similarity,
                label: match.label,
                type: match.type,
                context: statements
            ))
        }
        return resolvedMatches
    }

    /// Truncate a long assertion for log output.
    private static func shortAssertion(_ assertion: String, limit: Int = 64) -> String {
        if assertion.count <= limit { return assertion }
        return String(assertion.prefix(limit)) + "…"
    }

    private func entityType(from assertion: String, fallback: String) -> String {
        let tokens = assertion
            .split(whereSeparator: {
                $0 == "." || $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t"
            })
            .map(String.init)
        guard let predicateIndex = tokens.firstIndex(of: "a"),
              tokens.indices.contains(tokens.index(after: predicateIndex)) else {
            return fallback
        }
        return tokens[tokens.index(after: predicateIndex)]
    }

    private func resolveOneHopContext(
        for iri: String,
        context: MemoryContext
    ) async throws -> [ResolvedContextStatement] {
        var contextStatements: [ResolvedContextStatement] = []
        var endpointCache: [String: ResolvedEndpoint] = [:]

        let outgoing = try await context.databaseContext.sparql(namedGraph: context.graphName)
            .where(
                try MemoryRDF.executionResource(iri),
                .variable("?predicate"),
                .variable("?object")
            )
            .select(["?predicate", "?object"])
            .execute()
        for binding in outgoing.bindings {
            guard let predicate = MemoryRDF.resourceValue(binding, variable: "?predicate"),
                  let object = MemoryRDF.value(binding, variable: "?object") else { continue }
            let subjectEndpoint = try await resolvedEndpoint(
                for: iri,
                cache: &endpointCache,
                context: context
            )
            let objectEndpoint = try await resolvedEndpoint(
                for: object,
                cache: &endpointCache,
                context: context
            )
            contextStatements.append(ResolvedContextStatement(
                direction: .outgoing,
                subject: iri,
                predicate: predicate,
                object: objectEndpoint.id,
                subjectLabel: subjectEndpoint.label,
                subjectType: subjectEndpoint.type,
                objectLabel: objectEndpoint.label,
                objectType: objectEndpoint.type
            ))
        }

        let incoming = try await context.databaseContext.sparql(namedGraph: context.graphName)
            .where(
                .variable("?subject"),
                .variable("?predicate"),
                try MemoryRDF.executionResource(iri)
            )
            .select(["?subject", "?predicate"])
            .execute()
        for binding in incoming.bindings {
            guard let subject = MemoryRDF.resourceValue(binding, variable: "?subject"),
                  let predicate = MemoryRDF.resourceValue(binding, variable: "?predicate") else { continue }
            let subjectEndpoint = try await resolvedEndpoint(
                for: subject,
                cache: &endpointCache,
                context: context
            )
            let objectEndpoint = try await resolvedEndpoint(
                for: iri,
                cache: &endpointCache,
                context: context
            )
            contextStatements.append(ResolvedContextStatement(
                direction: .incoming,
                subject: subject,
                predicate: predicate,
                object: iri,
                subjectLabel: subjectEndpoint.label,
                subjectType: subjectEndpoint.type,
                objectLabel: objectEndpoint.label,
                objectType: objectEndpoint.type
            ))
        }

        return contextStatements
    }

    private struct ResolvedEndpoint {
        var id: String
        var label: String
        var type: String
    }

    private func resolvedEndpoint(
        for rawValue: String,
        cache: inout [String: ResolvedEndpoint],
        context: MemoryContext
    ) async throws -> ResolvedEndpoint {
        let cleaned = cleanLiteral(rawValue)
        if let cached = cache[cleaned] {
            return cached
        }

        if rawValue.hasPrefix("\"") {
            let endpoint = ResolvedEndpoint(id: cleaned, label: cleaned, type: "Literal")
            cache[cleaned] = endpoint
            return endpoint
        }

        let label = try await graphLabel(for: cleaned, context: context)
        let type = try await graphType(for: cleaned, context: context)
        let endpoint = ResolvedEndpoint(
            id: cleaned,
            label: label.isEmpty ? cleaned : label,
            type: type
        )
        cache[cleaned] = endpoint
        return endpoint
    }

    private func graphLabel(
        for iri: String,
        context: MemoryContext
    ) async throws -> String {
        let result = try await context.databaseContext.sparql(namedGraph: context.graphName)
            .where(
                try MemoryRDF.executionResource(iri),
                try MemoryRDF.executionPredicate("rdfs:label"),
                .variable("?label")
            )
            .select(["?label"])
            .execute()
        guard let first = result.bindings.first,
              let raw = MemoryRDF.value(first, variable: "?label") else {
            return ""
        }
        return cleanLiteral(raw)
    }

    private func graphType(
        for iri: String,
        context: MemoryContext
    ) async throws -> String {
        let result = try await context.databaseContext.sparql(namedGraph: context.graphName)
            .where(
                try MemoryRDF.executionResource(iri),
                try MemoryRDF.executionPredicate("rdf:type"),
                .variable("?type")
            )
            .select(["?type"])
            .execute()
        guard let first = result.bindings.first else { return "" }
        return MemoryRDF.resourceValue(first, variable: "?type") ?? ""
    }

    private func cleanLiteral(_ raw: String) -> String {
        guard raw.hasPrefix("\""),
              let closingQuote = raw.lastIndex(of: "\""),
              closingQuote > raw.startIndex else { return raw }
        return String(raw[raw.index(after: raw.startIndex)..<closingQuote])
    }

    // MARK: - Recall

    /// Recall from the default layer using spreading activation.
    public func recall(keywords: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recall(
            RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit),
            in: defaultLayer
        )
    }

    /// Recall from one layer using spreading activation.
    public func recall(
        keywords: [String],
        in layer: MemoryLayer,
        maxHops: Int = 2,
        limit: Int = 20
    ) async throws -> RecallResult {
        try await recall(
            RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit),
            in: layer
        )
    }

    /// Recall from the default layer with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recall(query, in: defaultLayer)
    }

    /// Recall from one layer with a full query.
    public func recall(
        _ query: RecallQuery,
        in layer: MemoryLayer
    ) async throws -> RecallResult {
        let layerContext = try context(for: layer)
        return try await RecallEngine(context: layerContext).execute(query)
    }

    /// Recall across selected layers while preserving each Base origin.
    ///
    /// The derived Composition is resolved first so authorization for every
    /// selected Base is evaluated as one boundary. Results intentionally stay
    /// grouped by layer because identical model identifiers in different Bases
    /// represent different knowledge origins.
    public func recall(
        _ query: RecallQuery,
        across requestedLayers: [MemoryLayer]? = nil
    ) async throws -> LayeredRecallResult {
        let selected = try selectedLayers(requestedLayers)
        try await authorizeCompositionRead(selected)

        var results: [MemoryLayerRecallResult] = []
        results.reserveCapacity(selected.count)
        for item in selected {
            let result = try await RecallEngine(context: item.context).execute(query)
            results.append(MemoryLayerRecallResult(layer: item.layer, result: result))
        }
        return LayeredRecallResult(layers: results)
    }

    /// Finish database streams and release storage resources.
    public func shutdown() async {
        await container.shutdown()
    }

    // MARK: - Resolve (External API)

    /// Resolve entity candidates against existing knowledge without inserting.
    ///
    /// For each candidate, embeds its RDF/Turtle class assertion, searches the
    /// shared Entity polymorphic vector index, and returns the top-K persisted
    /// entities whose similarity exceeds the `threshold`, including one-hop
    /// graph context for caller judgment.
    ///
    /// Matches are filtered to the concrete Swift type `T`: a candidate will
    /// only resolve to persisted entities whose runtime type is `T`. The
    /// polymorphic index still spans every `Entity` subclass (so that recall
    /// / spreading activation can cross types), but resolve must not —
    /// otherwise mean-pooled assertion embeddings cause cross-class
    /// collisions via shared surface vocabulary.
    ///
    /// This API is for callers that need to judge possible matches before
    /// storing. Regular `store()` calls do not perform entity deduplication; the
    /// intended flow is:
    ///
    /// 1. `resolve([...])` returns candidates with one-hop context
    /// 2. If a candidate truly matches, the caller should reuse its stable ID
    ///    in statements and avoid inserting a duplicate entity.
    /// 3. `store(...)` persists the final reviewed knowledge payload.
    ///
    /// - Parameters:
    ///   - candidates: Entity candidates, each with an RDF/Turtle class assertion.
    ///   - witness: Concrete Entity type. Candidates are matched only against
    ///     persisted entities of this exact type.
    ///   - threshold: Minimum cosine similarity for a persisted entity to be
    ///     returned as a candidate. Defaults to `defaultResolveThreshold`.
    ///   - limit: Maximum candidates returned per input. Defaults to
    ///     `defaultResolveLimit`.
    /// - Returns: One `ResolvedEntity` per input, each with a (possibly
    ///   empty) list of matching candidates sorted by similarity descending.
    public final func resolve<T: Persistable & Entity>(
        _ candidates: [ResolveCandidate],
        witness: T.Type,
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        try await resolve(
            candidates,
            witness: witness,
            in: defaultLayer,
            threshold: threshold,
            limit: limit
        )
    }

    /// Resolve entity candidates against knowledge in one layer.
    public final func resolve<T: Persistable & Entity>(
        _ candidates: [ResolveCandidate],
        witness: T.Type,
        in layer: MemoryLayer,
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        let layerContext = try context(for: layer)
        let effectiveThreshold = threshold ?? Self.defaultResolveThreshold

        guard let provider = layerContext.embeddingProvider else {
            MemoryLog.info(category: "Memory", "[resolve] no embedding provider - returning empty candidates")
            return candidates.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        guard !candidates.isEmpty else { return [] }

        var results: [ResolvedEntity] = []
        results.reserveCapacity(candidates.count)

        let queryEmbeddings = try Self.requireEmbeddingBatch(
            try await provider.embed(candidates.map { $0.assertion }),
            expectedCount: candidates.count
        )

        for (candidate, queryVector) in zip(candidates, queryEmbeddings) {
            let queryEmbedding = try Self.requireEmbedding(
                queryVector,
                dimensions: T.embeddingDimensions
            )
            let matches = try await topPersistedCandidates(
                witness: T.self,
                embedding: queryEmbedding,
                threshold: effectiveThreshold,
                k: limit,
                searchLimit: Self.resolutionSearchLimit,
                context: layerContext
            )
            results.append(ResolvedEntity(
                inputAssertion: candidate.assertion,
                candidates: matches
            ))
        }

        let withCandidates = results.filter { $0.hasCandidates }.count
        MemoryLog.info(category: "Memory", "[resolve] \(candidates.count) inputs -> \(withCandidates) with candidates (threshold=\(effectiveThreshold), limit=\(limit))")
        return results
    }

    /// Resolve a homogeneous array of concrete entities without inserting.
    public final func resolve<T: Persistable & Entity & Sendable>(
        _ entities: [T],
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        try await resolve(
            entities,
            in: defaultLayer,
            threshold: threshold,
            limit: limit
        )
    }

    /// Resolve homogeneous concrete entities against one layer.
    public final func resolve<T: Persistable & Entity & Sendable>(
        _ entities: [T],
        in layer: MemoryLayer,
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        guard !entities.isEmpty else { return [] }
        let layerContext = try context(for: layer)
        let effectiveThreshold = threshold ?? Self.defaultResolveThreshold

        guard let provider = layerContext.embeddingProvider else {
            MemoryLog.info(category: "Memory", "[resolve] no embedding provider - returning empty candidates")
            return entities.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        let queryEmbeddings = try Self.requireEmbeddingBatch(
            try await provider.embed(entities.map { $0.assertion }),
            expectedCount: entities.count
        )
        var results: [ResolvedEntity] = []
        results.reserveCapacity(entities.count)
        for (entity, queryVector) in zip(entities, queryEmbeddings) {
            results.append(try await resolvedEntity(
                entity,
                queryVector: queryVector,
                threshold: effectiveThreshold,
                limit: limit,
                context: layerContext
            ))
        }
        return results
    }

    #if !hasFeature(Embedded)
    /// Resolve a heterogeneous array of concrete entities without inserting.
    ///
    /// Embedded Swift callers use the homogeneous generic overload because the
    /// runtime cannot open protocol existentials at generic query boundaries.
    public func resolve(
        _ entities: [any Persistable & Entity & Sendable],
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        try await resolve(
            entities,
            in: defaultLayer,
            threshold: threshold,
            limit: limit
        )
    }

    /// Resolve heterogeneous concrete entities against one layer.
    public func resolve(
        _ entities: [any Persistable & Entity & Sendable],
        in layer: MemoryLayer,
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        guard !entities.isEmpty else { return [] }
        let layerContext = try context(for: layer)
        let effectiveThreshold = threshold ?? Self.defaultResolveThreshold

        guard let provider = layerContext.embeddingProvider else {
            MemoryLog.info(category: "Memory", "[resolve] no embedding provider - returning empty candidates")
            return entities.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        var results: [ResolvedEntity] = []
        results.reserveCapacity(entities.count)

        let queryEmbeddings = try Self.requireEmbeddingBatch(
            try await provider.embed(entities.map { $0.assertion }),
            expectedCount: entities.count
        )

        for (entity, queryVector) in zip(entities, queryEmbeddings) {
            results.append(try await resolvedEntity(
                entity,
                queryVector: queryVector,
                threshold: effectiveThreshold,
                limit: limit,
                context: layerContext
            ))
        }

        let withCandidates = results.filter { $0.hasCandidates }.count
        MemoryLog.info(category: "Memory", "[resolve] \(entities.count) entity inputs -> \(withCandidates) with candidates (threshold=\(effectiveThreshold), limit=\(limit))")
        return results
    }
    #endif

    private final func resolvedEntity<E: Persistable & Entity & Sendable>(
        _ entity: E,
        queryVector: [Float],
        threshold: Float,
        limit: Int,
        context: MemoryContext
    ) async throws -> ResolvedEntity {
        let queryEmbedding = try Self.requireEmbedding(
            queryVector,
            dimensions: E.embeddingDimensions
        )
        let matches = try await topPersistedCandidates(
            witness: E.self,
            embedding: queryEmbedding,
            threshold: threshold,
            k: limit,
            searchLimit: Self.resolutionSearchLimit,
            context: context
        )
        return ResolvedEntity(
            inputAssertion: entity.assertion,
            candidates: matches
        )
    }

    private static func requireEmbeddingBatch(
        _ vectors: [[Float]],
        expectedCount: Int
    ) throws -> [[Float]] {
        guard vectors.count == expectedCount else {
            throw MemoryError.embeddingBatchCountMismatch(
                expected: expectedCount,
                actual: vectors.count
            )
        }
        return vectors
    }

    private static func requireEmbedding(
        _ vector: [Float],
        dimensions: Int
    ) throws -> [Float] {
        guard vector.count == dimensions else {
            throw MemoryError.embeddingDimensionMismatch(
                expected: dimensions,
                actual: vector.count
            )
        }
        return vector
    }

    #if !hasFeature(Embedded)
    // MARK: - Test Support

    /// Count entities stored under the shared polymorphic directory for the
    /// given witness type. Exposed for `@testable` so storage tests can assert
    /// on persisted entity counts.
    internal func _debugEntityCount<T: Persistable & Entity>(witness: T.Type) async throws -> Int {
        try await _debugEntityCount(witness: witness, in: defaultLayer)
    }

    internal func _debugEntityCount<T: Persistable & Entity>(
        witness: T.Type,
        in layer: MemoryLayer
    ) async throws -> Int {
        let layerContext = try context(for: layer)
        return try await layerContext.databaseContext.fetchPolymorphic(T.self).count
    }

    /// Fetch all entities stored under the shared polymorphic directory for
    /// the given witness type. Exposed for `@testable` so tests can inspect
    /// stored entity records.
    internal func _debugEntities<T: Persistable & Entity>(witness: T.Type) async throws -> [T] {
        try await _debugEntities(witness: witness, in: defaultLayer)
    }

    internal func _debugEntities<T: Persistable & Entity>(
        witness: T.Type,
        in layer: MemoryLayer
    ) async throws -> [T] {
        let layerContext = try context(for: layer)
        let models = try await layerContext.databaseContext.fetchPolymorphic(T.self)
        return try models.compactMap { model in
            guard model.entity == T.persistableType else { return nil }
            return try model.decode(as: T.self)
        }
    }

    /// Fetch a concrete Persistable type directly (non-polymorphic).
    /// Exposed for `@testable` diagnostics.
    internal func _debugFetchAll<T: Persistable>(_ type: T.Type) async throws -> [T] {
        try await _debugFetchAll(type, in: defaultLayer)
    }

    internal func _debugFetchAll<T: Persistable>(
        _ type: T.Type,
        in layer: MemoryLayer
    ) async throws -> [T] {
        let layerContext = try context(for: layer)
        return try await layerContext.databaseContext.fetch(type).execute()
    }

    internal func _debugTriples(
        graph: String,
        subject: String = "?subject",
        predicate: String = "?predicate",
        object: String = "?object"
    ) async throws -> [(subject: String, predicate: String, object: String)] {
        try await _debugTriples(
            graph: graph,
            subject: subject,
            predicate: predicate,
            object: object,
            in: defaultLayer
        )
    }

    internal func _debugTriples(
        graph: String,
        subject: String = "?subject",
        predicate: String = "?predicate",
        object: String = "?object",
        in layer: MemoryLayer
    ) async throws -> [(subject: String, predicate: String, object: String)] {
        let layerContext = try context(for: layer)
        let result = try await layerContext.databaseContext.sparql(
            namedGraph: try MemoryRDF.graphName(graph)
        )
            .where(
                subject.hasPrefix("?")
                    ? .variable(subject)
                    : try MemoryRDF.executionResource(subject),
                predicate.hasPrefix("?")
                    ? .variable(predicate)
                    : try MemoryRDF.executionPredicate(predicate),
                object.hasPrefix("?")
                    ? .variable(object)
                    : .value(.rdfTerm(try MemoryRDF.objectTerm(object)))
            )
            .select(["?subject", "?predicate", "?object"])
            .execute()
        return result.bindings.compactMap { binding in
            guard let subject = MemoryRDF.resourceValue(binding, variable: "?subject"),
                  let predicate = MemoryRDF.resourceValue(binding, variable: "?predicate"),
                  let object = MemoryRDF.value(binding, variable: "?object") else {
                return nil
            }
            return (subject, predicate, object)
        }
    }

    /// Runtime introspection for diagnosing polymorphic conformance.
    /// Returns whether the given type is recognised by Swift as conforming to
    /// `Polymorphable` at runtime, plus the polymorphic metadata resolved
    /// through that conformance.
    internal func _debugPolymorphicMetadata<T: Persistable>(
        _ type: T.Type
    ) -> (isPolymorphable: Bool, polyDirectory: String, typeDirectory: String, polymorphableType: String) {
        let polyDir: String
        let polyTypeName: String
        if let polyType = type as? any Polymorphable.Type {
            polyDir = polyType.polymorphicDirectoryPathComponents
                .map { "\($0)" }
                .joined(separator: "/")
            polyTypeName = polyType.polymorphableType
        } else {
            polyDir = ""
            polyTypeName = ""
        }
        let typeDir = type.directoryPathComponents
            .map { "\($0)" }
            .joined(separator: "/")
        return (type is any Polymorphable.Type, polyDir, typeDir, polyTypeName)
    }

    /// Returns the set of polymorphic group identifiers registered in the
    /// active Schema. Used by diagnostic tests to confirm that Schema
    /// registration picked up the runtime Polymorphable conformance.
    internal func _debugPolymorphicGroupIdentifiers() -> [String] {
        container.schema.polymorphicGroups.map { $0.identifier }
    }

    /// Returns the schema metadata observed for a polymorphic group:
    /// the resolved directory components, the member type names, and
    /// the polymorphic index descriptor names.
    internal func _debugPolymorphicGroupInfo(identifier: String) -> (components: [String], memberTypes: [String], indexes: [String])? {
        guard let group = container.schema.polymorphicGroup(identifier: identifier) else {
            return nil
        }
        let components: [String] = group.directoryComponents.map { component in
            switch component {
            case .staticPath(let value): return value
            case .dynamicField(let name): return "$\(name)"
            }
        }
        let indexes = group.indexes.map { $0.name }
        return (components, group.memberTypeNames, indexes)
    }

    /// Directly insert a Persistable (bypassing `insertEntities`) and
    /// commit. Used by diagnostic tests to isolate the dual-write code path
    /// from Memory's normal store logic.
    internal func _debugCommittedDirectInsert<T: Persistable & Sendable>(_ model: T) async throws {
        try await _debugCommittedDirectInsert(model, in: defaultLayer)
    }

    internal func _debugCommittedDirectInsert<T: Persistable & Sendable>(
        _ model: T,
        in layer: MemoryLayer
    ) async throws {
        let layerContext = try context(for: layer)
        try layerContext.databaseContext.insert(model)
        try await layerContext.databaseContext.save()
    }
    #endif

}
