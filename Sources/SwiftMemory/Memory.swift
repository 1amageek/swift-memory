// Memory.swift
// Knowledge persistence and recall

import Foundation
import Database
import MemoryOntology
import os.log

private let logger = Logger(subsystem: "com.memory", category: "Memory")

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
///     entityTypes: [Person.self, Organization.self],
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

    /// Default cosine-similarity threshold used by `resolve()` to surface
    /// possible matches to the caller.
    public static let defaultResolveThreshold: Float = 0.90

    /// Default maximum number of candidates returned per input by `resolve()`.
    public static let defaultResolveLimit: Int = 30

    private static let resolutionSearchLimit = 30

    private let context: MemoryContext
    private let container: DBContainer
    private let recallEngine: RecallEngine

    public nonisolated let ontologyPolicy: any OntologyPolicy

    public init(
        path: String?,
        entityTypes: [any Persistable.Type] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil
    ) async throws {
        self.ontologyPolicy = ontologyPolicy

        let allTypes: [any Persistable.Type] = [Given.self, Statement.self, Trace.self] + entityTypes
        let schema = Schema(allTypes, version: Schema.Version(2, 0, 0))

        if let path {
            self.container = try await DBContainer.sqlite(
                for: schema, path: path, security: .disabled
            )
        } else {
            self.container = try await DBContainer.inMemory(
                for: schema, security: .disabled
            )
        }

        let fdbContext = container.newContext()
        try await fdbContext.ontology.load(ontologyPolicy.buildOntology())

        self.context = MemoryContext(
            fdbContext: fdbContext,
            graphName: graphName,
            embeddingProvider: embeddingProvider
        )
        self.recallEngine = RecallEngine(context: context)
    }

    // MARK: - Store

    /// Store Given + Knowledge atomically.
    ///
    /// Given is the raw material. Knowledge is the structured interpretation.
    /// Entities are inserted as provided; statements are remapped to identifiers
    /// created in the payload or registered aliases. Trace records link each
    /// Statement back to its source Given.
    public func store(given: any Memorable, knowledge: some MemoryBatchConvertible) async throws {
        let batch = knowledge.toBatch()
        try await persist(given: given, batch: batch)
    }

    /// Store Given + Knowledge from raw JSON data and a decode closure.
    /// Used by transport adapters where knowledge arrives as JSON bytes.
    public func store(
        given: any Memorable,
        knowledgeData: Data,
        decode: @Sendable (Data) throws -> MemoryBatch
    ) async throws {
        let batch = try decode(knowledgeData)
        try await persist(given: given, batch: batch)
    }

    /// Store a batch directly (without Given).
    /// No Trace records are created because there is no Given to link from.
    public func store(_ batch: MemoryBatch) async throws {
        try await persist(given: nil, batch: batch)
    }

    // MARK: - Persist (shared implementation)

    private func persist(given: (any Memorable)?, batch: MemoryBatch) async throws {
        guard !batch.entities.isEmpty || !batch.statements.isEmpty else {
            logger.info("[store] empty knowledge — nothing saved")
            return
        }

        let now = Date()

        // Entity insertion (requires embedding provider when entities exist).
        var entityReferenceMap: [String: String] = [:]
        if !batch.entities.isEmpty {
            guard let provider = context.embeddingProvider else {
                throw MemoryError.embeddingProviderRequired
            }
            entityReferenceMap = try await insertEntities(
                batch.entities,
                provider: provider
            )
        }

        // Given record (requires embedding provider when given is present).
        var givenID: String?
        if let given {
            guard let provider = context.embeddingProvider else {
                throw MemoryError.embeddingProviderRequired
            }
            let id = ULID().ulidString
            let embedding = try await provider.embed(given.payloadRef)
            var record = Given(
                modality: given.modality,
                payloadRef: given.payloadRef,
                embedding: embedding,
                timestamp: now,
                source: "given"
            )
            record.id = id
            context.fdbContext.insert(record)
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
                graph: context.graphName,
                subject: subject,
                predicate: record.predicate,
                object: object
            )
            var statement = Statement(
                graph: context.graphName,
                subject: subject,
                predicate: record.predicate,
                object: object
            )
            statement.id = statementID
            context.fdbContext.insert(statement)

            if let givenID {
                var trace = Trace()
                trace.id = "\(givenID)|\(statementID)"
                trace.givenID = givenID
                trace.statementID = statementID
                context.fdbContext.insert(trace)
            }
        }

        try await context.fdbContext.save()
        logger.info(
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
        _ entities: [any Persistable & Entity & Sendable],
        provider: any EmbeddingProvider
    ) async throws -> [String: String] {
        var entityReferenceMap: [String: String] = [:]
        entityReferenceMap.reserveCapacity(entities.count)

        for entity in entities {
            let queryVec = try await provider.embed(entity.assertion)
            let inputID = String(describing: entity.id)

            var mutable = entity
            mutable.embedding = queryVec
            context.fdbContext.insert(mutable)

            let newID = String(describing: mutable.id)
            insertEntityIdentityStatements(id: newID, entity: mutable)
            entityReferenceMap[entity.assertion] = newID
            entityReferenceMap[inputID] = newID
            entityReferenceMap[newID] = newID

            logger.info("[store] inserted entity '\(Self.shortAssertion(entity.assertion))' id=\(newID)")
        }

        return entityReferenceMap
    }

    private func insertEntityIdentityStatements(
        id: String,
        entity: any Entity
    ) {
        let label = entityLabel(from: entity, fallback: id)
        let type = entityType(from: entity.assertion, fallback: String(describing: Swift.type(of: entity)))

        insertIdentityStatement(subject: id, predicate: "rdf:type", object: type)
        insertIdentityStatement(subject: id, predicate: "rdfs:label", object: label)
    }

    private func insertIdentityStatement(
        subject: String,
        predicate: String,
        object: String
    ) {
        guard !subject.isEmpty, !predicate.isEmpty, !object.isEmpty else { return }
        let statementID = Statement.contentID(
            graph: context.graphName,
            subject: subject,
            predicate: predicate,
            object: object
        )
        var statement = Statement(
            graph: context.graphName,
            subject: subject,
            predicate: predicate,
            object: object
        )
        statement.id = statementID
        context.fdbContext.insert(statement)
    }

    private struct StatementEndpointResolver {
        let entityReferences: [String: String]
        let aliases: [String: String]

        func resolve(_ endpoint: String) -> String {
            if let id = entityReferences[endpoint] {
                return id
            }

            if let aliasTarget = aliases[endpoint],
               let id = entityReferences[aliasTarget] {
                return id
            }

            let key = normalized(endpoint)
            if let id = entityReferences.first(where: { normalized($0.key) == key })?.value {
                return id
            }

            if let aliasTarget = aliases.first(where: { normalized($0.key) == key })?.value,
               let id = entityReferences[aliasTarget] {
                return id
            }

            return endpoint
        }

        private func normalized(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
        }
    }

    /// Return up to `k` persisted `E` entities (runtime type == `typeID`)
    /// whose cosine similarity to `embedding` clears `threshold`, sorted by
    /// similarity descending.
    ///
    /// Used by the public `resolve` API to surface possible matches for
    /// external caller judgment. Store-time persistence does not call this path
    /// for already-persisted entities.
    private func topPersistedCandidates<E: Persistable & Entity & Sendable>(
        witness: E.Type,
        typeID: ObjectIdentifier,
        embedding: [Float],
        threshold: Float,
        k: Int,
        searchLimit: Int
    ) async throws -> [ResolvedMatch] {
        guard k > 0 else { return [] }

        let page = try await context.fdbContext.findPolymorphic(E.self)
            .vector(\.embedding, dimensions: E.embeddingDimensions)
            .query(embedding, k: searchLimit)
            .metric(.cosine)
            .executePage()

        var matches: [(id: String, assertion: String, similarity: Float, label: String, type: String)] = []
        matches.reserveCapacity(min(k, page.results.count))

        for result in page.results {
            guard result.item is any Persistable & Entity & Sendable else { continue }
            guard ObjectIdentifier(type(of: result.item)) == typeID else { continue }
            guard let distance = result.annotations["distance"]?.doubleValue else {
                throw MemoryError.invalidQuery("polymorphic vector result is missing distance annotation")
            }
            let similarity = 1 - Float(distance)
            guard similarity >= threshold else { continue }
            guard let entity = result.item as? any Entity else { continue }
            let id = String(describing: result.item.id)
            let label = entityLabel(from: result.item, fallback: id)
            let type = entityType(from: entity.assertion, fallback: String(describing: Swift.type(of: result.item)))
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
            let context = try await resolveOneHopContext(for: match.id)
            resolvedMatches.append(ResolvedMatch(
                id: match.id,
                assertion: match.assertion,
                similarity: match.similarity,
                label: match.label,
                type: match.type,
                context: context
            ))
        }
        return resolvedMatches
    }

    /// Truncate a long assertion for log output.
    private static func shortAssertion(_ assertion: String, limit: Int = 64) -> String {
        if assertion.count <= limit { return assertion }
        return String(assertion.prefix(limit)) + "…"
    }

    private func entityLabel(from item: Any, fallback: String) -> String {
        let mirror = Mirror(reflecting: item)
        for key in ["name", "title", "label"] {
            if let value = stringProperty(named: key, in: mirror), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private func stringProperty(named name: String, in mirror: Mirror) -> String? {
        for child in mirror.children where child.label == name {
            return child.value as? String
        }
        return nil
    }

    private func entityType(from assertion: String, fallback: String) -> String {
        let tokens = assertion
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        guard let predicateIndex = tokens.firstIndex(of: "a"),
              tokens.indices.contains(tokens.index(after: predicateIndex)) else {
            return fallback
        }
        return tokens[tokens.index(after: predicateIndex)]
    }

    private func resolveOneHopContext(for iri: String) async throws -> [ResolvedContextStatement] {
        var contextStatements: [ResolvedContextStatement] = []
        var endpointCache: [String: ResolvedEndpoint] = [:]

        let outgoing = try await context.fdbContext.sparql(graph: context.graphName)
            .where(iri, "?predicate", "?object")
            .select(["?predicate", "?object"])
            .execute()
        for binding in outgoing.bindings {
            guard let predicate = binding.string("?predicate"),
                  let object = binding.string("?object") else { continue }
            let subjectEndpoint = try await resolvedEndpoint(for: iri, cache: &endpointCache)
            let objectEndpoint = try await resolvedEndpoint(for: object, cache: &endpointCache)
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

        let incoming = try await context.fdbContext.sparql(graph: context.graphName)
            .where("?subject", "?predicate", iri)
            .select(["?subject", "?predicate"])
            .execute()
        for binding in incoming.bindings {
            guard let subject = binding.string("?subject"),
                  let predicate = binding.string("?predicate") else { continue }
            let subjectEndpoint = try await resolvedEndpoint(for: subject, cache: &endpointCache)
            let objectEndpoint = try await resolvedEndpoint(for: iri, cache: &endpointCache)
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
        cache: inout [String: ResolvedEndpoint]
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

        let label = try await graphLabel(for: cleaned)
        let type = try await graphType(for: cleaned)
        let endpoint = ResolvedEndpoint(
            id: cleaned,
            label: label.isEmpty ? cleaned : label,
            type: type
        )
        cache[cleaned] = endpoint
        return endpoint
    }

    private func graphLabel(for iri: String) async throws -> String {
        let result = try await context.fdbContext.sparql(graph: context.graphName)
            .where(iri, "rdfs:label", "?label")
            .select(["?label"])
            .execute()
        guard let raw = result.bindings.first?.string("?label") else {
            return ""
        }
        return cleanLiteral(raw)
    }

    private func graphType(for iri: String) async throws -> String {
        let result = try await context.fdbContext.sparql(graph: context.graphName)
            .where(iri, "rdf:type", "?type")
            .select(["?type"])
            .execute()
        return result.bindings.first?.string("?type") ?? ""
    }

    private func cleanLiteral(_ raw: String) -> String {
        guard raw.hasPrefix("\"") else { return raw }
        if let range = raw.range(of: "\"^^", options: .backwards) {
            return String(raw[raw.index(after: raw.startIndex)..<range.lowerBound])
        }
        if let range = raw.range(of: "\"@", options: .backwards) {
            return String(raw[raw.index(after: raw.startIndex)..<range.lowerBound])
        }
        if raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }

    // MARK: - Recall

    /// Recall from keywords — spreading activation.
    public func recall(keywords: [String], maxHops: Int = 2, limit: Int = 20) async throws -> RecallResult {
        try await recallEngine.execute(RecallQuery(keywords: keywords, maxHops: maxHops, limit: limit))
    }

    /// Recall with a full query.
    public func recall(_ query: RecallQuery) async throws -> RecallResult {
        try await recallEngine.execute(query)
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
    public func resolve<T: Persistable & Entity>(
        _ candidates: [ResolveCandidate],
        witness: T.Type,
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        let effectiveThreshold = threshold ?? Self.defaultResolveThreshold

        guard let provider = context.embeddingProvider else {
            logger.info("[resolve] no embedding provider — returning empty candidates")
            return candidates.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        guard !candidates.isEmpty else { return [] }

        let witnessTypeID = ObjectIdentifier(T.self)

        var results: [ResolvedEntity] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let queryEmbedding = try await provider.embed(candidate.assertion)
            let matches = try await topPersistedCandidates(
                witness: T.self,
                typeID: witnessTypeID,
                embedding: queryEmbedding,
                threshold: effectiveThreshold,
                k: limit,
                searchLimit: Self.resolutionSearchLimit
            )
            results.append(ResolvedEntity(
                inputAssertion: candidate.assertion,
                candidates: matches
            ))
        }

        let withCandidates = results.filter(\.hasCandidates).count
        logger.info("[resolve] \(candidates.count) inputs -> \(withCandidates) with candidates (threshold=\(effectiveThreshold), limit=\(limit))")
        return results
    }

    /// Resolve concrete entity instances against existing knowledge without
    /// inserting. This is the preferred pre-store path for callers that already
    /// hold typed entity instances because it uses each candidate's concrete
    /// runtime type for filtering.
    public func resolve(
        _ entities: [any Persistable & Entity & Sendable],
        threshold: Float? = nil,
        limit: Int = Memory.defaultResolveLimit
    ) async throws -> [ResolvedEntity] {
        guard let first = entities.first else { return [] }
        return try await _resolveEntities(
            entities,
            witness: first,
            threshold: threshold,
            limit: limit
        )
    }

    private func _resolveEntities<E: Persistable & Entity & Sendable>(
        _ entities: [any Persistable & Entity & Sendable],
        witness: E,
        threshold: Float?,
        limit: Int
    ) async throws -> [ResolvedEntity] {
        let effectiveThreshold = threshold ?? Self.defaultResolveThreshold

        guard let provider = context.embeddingProvider else {
            logger.info("[resolve] no embedding provider — returning empty candidates")
            return entities.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        var results: [ResolvedEntity] = []
        results.reserveCapacity(entities.count)

        for entity in entities {
            let queryEmbedding = try await provider.embed(entity.assertion)
            let matches = try await topPersistedCandidates(
                witness: E.self,
                typeID: ObjectIdentifier(type(of: entity)),
                embedding: queryEmbedding,
                threshold: effectiveThreshold,
                k: limit,
                searchLimit: Self.resolutionSearchLimit
            )
            results.append(ResolvedEntity(
                inputAssertion: entity.assertion,
                candidates: matches
            ))
        }

        let withCandidates = results.filter(\.hasCandidates).count
        logger.info("[resolve] \(entities.count) entity inputs -> \(withCandidates) with candidates (threshold=\(effectiveThreshold), limit=\(limit))")
        return results
    }

    // MARK: - Test Support

    /// Count entities stored under the shared polymorphic directory for the
    /// given witness type. Exposed for `@testable` so storage tests can assert
    /// on persisted entity counts.
    internal func _debugEntityCount<T: Persistable & Entity>(witness: T.Type) async throws -> Int {
        try await context.fdbContext.fetchPolymorphic(T.self).count
    }

    /// Fetch all entities stored under the shared polymorphic directory for
    /// the given witness type. Exposed for `@testable` so tests can inspect
    /// stored entity records.
    internal func _debugEntities<T: Persistable & Entity>(witness: T.Type) async throws -> [any Persistable] {
        try await context.fdbContext.fetchPolymorphic(T.self)
    }

    /// Fetch a concrete Persistable type directly (non-polymorphic).
    /// Exposed for `@testable` diagnostics.
    internal func _debugFetchAll<T: Persistable>(_ type: T.Type) async throws -> [T] {
        try await context.fdbContext.fetch(type).execute()
    }

    internal func _debugTriples(
        graph: String,
        subject: String = "?subject",
        predicate: String = "?predicate",
        object: String = "?object"
    ) async throws -> [(subject: String, predicate: String, object: String)] {
        let result = try await context.fdbContext.sparql(graph: graph)
            .where(subject, predicate, object)
            .select(["?subject", "?predicate", "?object"])
            .execute()
        return result.bindings.compactMap { binding in
            guard let subject = binding.string("?subject"),
                  let predicate = binding.string("?predicate"),
                  let object = binding.string("?object") else {
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
    internal func _debugDirectInsertAndCommit<T: Persistable & Sendable>(_ model: T) async throws {
        context.fdbContext.insert(model)
        try await context.fdbContext.save()
    }

    /// Count raw (key, value) entries directly under the polymorphic items
    /// subspace of the given group identifier. Bypasses `fetchPolymorphic`
    /// entirely so diagnostic tests can distinguish "write path didn't write
    /// to the poly directory" from "read path is broken".
    internal func _debugRawPolymorphicKeyCount(identifier: String) async throws -> Int {
        let subspace = try await container.resolvePolymorphicDirectory(for: identifier)
        let itemSubspace = subspace.subspace(SubspaceKey.items)
        let (begin, end) = itemSubspace.range()
        return try await context.fdbContext.executeCanonicalRead { transaction in
            var count = 0
            let pairs = try await transaction.collectRange(begin: begin, end: end)
            count = pairs.count
            return count
        }
    }

    /// Probe the polymorphic items layout. Returns:
    /// - `itemsPrefixHex`: hex-encoded prefix of the items subspace
    /// - `allKeysHex`: all raw keys under the items subspace
    /// - `typeCode`: DJB2 code for `T.persistableType`
    /// - `typeSubspacePrefixHex`: hex-encoded prefix of
    ///   `itemSubspace.subspace(typeCode)`
    /// - `typeScopedKeysHex`: raw keys found under `typeSubspacePrefix` range
    internal func _debugPolymorphicItemsProbe<T: Persistable & Polymorphable>(
        _ type: T.Type
    ) async throws -> (
        itemsPrefixHex: String,
        allKeysHex: [String],
        typeCode: Int64,
        typeSubspacePrefixHex: String,
        typeScopedKeysHex: [String]
    ) {
        let subspace = try await container.resolvePolymorphicDirectory(for: T.polymorphableType)
        let itemSubspace = subspace.subspace(SubspaceKey.items)
        let typeCode = T.typeCode(for: T.persistableType)
        let typeSubspace = itemSubspace.subspace(typeCode)

        let (beginAll, endAll) = itemSubspace.range()
        let (beginType, endType) = typeSubspace.range()

        return try await context.fdbContext.executeCanonicalRead { transaction in
            let allPairs = try await transaction.collectRange(begin: beginAll, end: endAll)
            let all = allPairs.map { $0.0.map { String(format: "%02x", $0) }.joined() }
            let typedPairs = try await transaction.collectRange(begin: beginType, end: endType)
            let typed = typedPairs.map { $0.0.map { String(format: "%02x", $0) }.joined() }
            return (
                itemsPrefixHex: itemSubspace.prefix.map { String(format: "%02x", $0) }.joined(),
                allKeysHex: all,
                typeCode: typeCode,
                typeSubspacePrefixHex: typeSubspace.prefix.map { String(format: "%02x", $0) }.joined(),
                typeScopedKeysHex: typed
            )
        }
    }

    // MARK: - Cosine Similarity

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }
}
