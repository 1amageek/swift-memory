// Memory.swift
// Knowledge persistence and recall

import Foundation
import Database
import MemoryOntology
import os.log

private let logger = Logger(subsystem: "com.memory", category: "Memory")

/// Knowledge persistence system for LLM agents.
///
/// Memory stores and recalls knowledge. It does **not** interpret raw input.
///
/// Interpretation is the responsibility of an external agent:
/// - A nested agent (e.g. haiku) analyzes conversation and structures knowledge
/// - The agent calls `store(batch)` with entities and relationships
/// - Memory persists them and enables recall via spreading activation
///
/// Entities are deduplicated on store via embedding similarity. When a new
/// entity's assertion embedding matches an existing entity above the
/// configured threshold, the incoming entity is discarded and the relationship
/// statements are remapped to the resolved identifier.
///
/// ```swift
/// let memory = try await Memory(
///     path: "memory.sqlite",
///     entityTypes: [Person.self, Organization.self],
///     embeddingProvider: MLXEmbeddingProvider()
/// )
///
/// // Store (called by the interpreting agent via MCP tool)
/// var batch = MemoryBatch()
/// batch.entity(person)
/// batch.triple("ex:alice", "ex:worksAt", "ex:acme")
/// try await memory.store(batch)
///
/// // Recall (called by Claude via MCP tool)
/// let result = try await memory.recall(keywords: ["Alice"])
/// ```
public actor Memory {

    /// Default cosine-similarity threshold used by `store()` to treat a new
    /// entity as a duplicate of an existing one.
    public static let defaultResolutionThreshold: Float = 0.85

    private static let resolutionSearchLimit = 10

    private let context: MemoryContext
    private let container: DBContainer
    private let recallEngine: RecallEngine
    private let resolutionThreshold: Float

    public nonisolated let ontologyPolicy: any OntologyPolicy

    public init(
        path: String?,
        entityTypes: [any Persistable.Type] = [],
        ontologyPolicy: any OntologyPolicy = DefaultOntologyPolicy(),
        graphName: String = "memory:default",
        embeddingProvider: (any EmbeddingProvider)? = nil,
        resolutionThreshold: Float = Memory.defaultResolutionThreshold
    ) async throws {
        self.ontologyPolicy = ontologyPolicy
        self.resolutionThreshold = resolutionThreshold

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
    /// Entities are deduplicated via embedding similarity; statements are
    /// remapped to resolved identifiers. Trace records link each Statement
    /// back to its source Given.
    public func store(given: any Memorable, knowledge: some MemoryBatchConvertible) async throws {
        let batch = knowledge.toBatch()
        try await persist(given: given, batch: batch)
    }

    /// Store Given + Knowledge from raw JSON data and a decode closure.
    /// Used by MCP tool handlers where knowledge arrives as JSON bytes.
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

        // Entity resolution (requires embedding provider when entities exist).
        var resolutionMap: [String: String] = [:]
        if !batch.entities.isEmpty {
            guard let provider = context.embeddingProvider else {
                throw MemoryError.embeddingProviderRequired
            }
            resolutionMap = try await resolveAndInsertEntities(
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

        // Statements + optional traces. Subject/object are remapped using the
        // entity resolution result so that relationships point at the canonical
        // entity when a match occurred.
        for record in batch.statements {
            let subject = resolutionMap[record.subject] ?? record.subject
            let object = resolutionMap[record.object] ?? record.object
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

    // MARK: - Entity Resolution

    /// Resolve and insert each entity in the batch.
    ///
    /// For every input entity, computes a query embedding from its `assertion`
    /// (a natural-language class assertion like "Alice is a person") and
    /// searches the shared polymorphic vector index using the `Entity.embedding`
    /// KeyPath. If the best cosine similarity is at or above the threshold,
    /// the input is treated as a duplicate and no new record is created.
    /// Otherwise the input is inserted with its embedding.
    ///
    /// Newly inserted entities are appended to the candidate list so that
    /// later entities in the same batch resolve against them (self-collision
    /// handling).
    ///
    /// - Returns: Map from input entity assertion to the resolved entity ID.
    private func resolveAndInsertEntities(
        _ entities: [any Persistable & Entity & Sendable],
        provider: any EmbeddingProvider
    ) async throws -> [String: String] {
        guard let first = entities.first else { return [:] }
        return try await _resolveAndInsertEntities(
            entities,
            witness: first,
            provider: provider
        )
    }

    private func _resolveAndInsertEntities<E: Persistable & Entity & Sendable>(
        _ entities: [any Persistable & Entity & Sendable],
        witness: E,
        provider: any EmbeddingProvider
    ) async throws -> [String: String] {
        var pendingCandidates: [ResolutionCandidate] = []
        pendingCandidates.reserveCapacity(entities.count)

        var resolutionMap: [String: String] = [:]
        resolutionMap.reserveCapacity(entities.count)

        for entity in entities {
            let queryVec = try await provider.embed(entity.assertion)

            let persistedMatch = try await bestPersistedCandidate(
                witness: E.self,
                embedding: queryVec,
                threshold: resolutionThreshold,
                limit: Self.resolutionSearchLimit
            )
            let pendingMatch = bestCandidate(
                in: pendingCandidates,
                embedding: queryVec,
                threshold: resolutionThreshold
            )
            let bestMatch = strongerMatch(persistedMatch, pendingMatch)

            if let match = bestMatch {
                resolutionMap[entity.assertion] = match.candidate.id
                logger.info(
                    "[resolve] match '\(Self.shortAssertion(entity.assertion))' -> '\(Self.shortAssertion(match.candidate.assertion))' sim=\(match.similarity)"
                )
            } else {
                var mutable = entity
                mutable.embedding = queryVec
                context.fdbContext.insert(mutable)

                let newID = String(describing: mutable.id)
                resolutionMap[entity.assertion] = newID

                pendingCandidates.append(ResolutionCandidate(
                    id: newID,
                    assertion: mutable.assertion,
                    embedding: queryVec,
                    persistable: mutable
                ))
                logger.info("[resolve] new '\(Self.shortAssertion(entity.assertion))' id=\(newID)")
            }
        }

        return resolutionMap
    }

    private struct ResolutionCandidate: Sendable {
        let id: String
        let assertion: String
        let embedding: [Float]
        let persistable: any Persistable & Entity & Sendable
    }

    private typealias ResolutionMatch = (candidate: ResolutionCandidate, similarity: Float)

    private func bestPersistedCandidate<E: Persistable & Entity & Sendable>(
        witness: E.Type,
        embedding: [Float],
        threshold: Float,
        limit: Int
    ) async throws -> ResolutionMatch? {
        let page = try await context.fdbContext.findPolymorphic(E.self)
            .vector(\.embedding, dimensions: E.embeddingDimensions)
            .query(embedding, k: limit)
            .metric(.cosine)
            .executePage()

        var best: (id: String, similarity: Float)?
        for result in page.results {
            guard result.item is any Persistable & Entity & Sendable else {
                continue
            }
            guard let distance = result.annotations["distance"]?.doubleValue else {
                throw MemoryError.invalidQuery("polymorphic vector result is missing distance annotation")
            }

            let similarity = 1 - Float(distance)
            guard similarity >= threshold else { continue }

            let id = String(describing: result.item.id)
            if best == nil || similarity > best!.similarity {
                best = (id: id, similarity: similarity)
            }
        }

        guard let best else {
            return nil
        }
        guard let item = try await context.fdbContext.fetchPolymorphic(E.self, id: best.id),
              let entity = item as? any Persistable & Entity & Sendable else {
            return nil
        }

        return (
            ResolutionCandidate(
                id: best.id,
                assertion: entity.assertion,
                embedding: entity.embedding,
                persistable: entity
            ),
            best.similarity
        )
    }

    /// Truncate a long assertion for log output.
    private static func shortAssertion(_ assertion: String, limit: Int = 64) -> String {
        if assertion.count <= limit { return assertion }
        return String(assertion.prefix(limit)) + "…"
    }

    private func bestCandidate(
        in candidates: [ResolutionCandidate],
        embedding: [Float],
        threshold: Float
    ) -> ResolutionMatch? {
        var best: ResolutionMatch?
        for candidate in candidates {
            guard candidate.embedding.count == embedding.count else { continue }
            let similarity = Self.cosineSimilarity(embedding, candidate.embedding)
            guard similarity >= threshold else { continue }
            best = strongerMatch(best, (candidate, similarity))
        }
        return best
    }

    private func strongerMatch(
        _ lhs: ResolutionMatch?,
        _ rhs: ResolutionMatch?
    ) -> ResolutionMatch? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.similarity >= rhs.similarity ? lhs : rhs
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
    /// For each candidate, embeds its `assertion` (natural-language class
    /// assertion), searches the shared Entity polymorphic vector index, and
    /// returns the best match at or above the similarity threshold.
    ///
    /// This API is for callers that want to inspect resolution results before
    /// deciding what to store. Regular `store()` calls perform the same logic
    /// internally.
    ///
    /// - Parameters:
    ///   - candidates: Entity candidates, each with a natural-language assertion.
    ///   - witness: Any concrete Entity type (used to satisfy Swift generics;
    ///     the polymorphic fetch returns ALL Entity types regardless).
    ///   - threshold: Minimum similarity score to consider a match.
    ///     Defaults to the store-side threshold.
    /// - Returns: Resolution results for each candidate.
    public func resolve<T: Persistable & Entity>(
        _ candidates: [ResolveCandidate],
        witness: T.Type,
        threshold: Float? = nil
    ) async throws -> [ResolvedEntity] {
        let effectiveThreshold = threshold ?? resolutionThreshold

        guard let provider = context.embeddingProvider else {
            logger.info("[resolve] no embedding provider — returning all unresolved")
            return candidates.map {
                ResolvedEntity(inputAssertion: $0.assertion)
            }
        }

        guard !candidates.isEmpty else { return [] }

        var results: [ResolvedEntity] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let queryEmbedding = try await provider.embed(candidate.assertion)
            let match = try await bestPersistedCandidate(
                witness: T.self,
                embedding: queryEmbedding,
                threshold: effectiveThreshold,
                limit: Self.resolutionSearchLimit
            )

            if let match {
                results.append(ResolvedEntity(
                    inputAssertion: candidate.assertion,
                    matchedID: match.candidate.id,
                    matchedAssertion: match.candidate.assertion,
                    similarity: match.similarity
                ))
            } else {
                results.append(ResolvedEntity(inputAssertion: candidate.assertion))
            }
        }

        let resolvedCount = results.filter(\.isResolved).count
        logger.info("[resolve] \(candidates.count) candidates -> \(resolvedCount) resolved")
        return results
    }

    // MARK: - Test Support

    /// Count entities stored under the shared polymorphic directory for the
    /// given witness type. Exposed for `@testable` so dedup tests can assert
    /// on persisted entity counts.
    internal func _debugEntityCount<T: Persistable & Entity>(witness: T.Type) async throws -> Int {
        try await context.fdbContext.fetchPolymorphic(T.self).count
    }

    /// Fetch all entities stored under the shared polymorphic directory for
    /// the given witness type. Exposed for `@testable` so dedup tests can
    /// inspect `created`/`updated` timestamps after resolution.
    internal func _debugEntities<T: Persistable & Entity>(witness: T.Type) async throws -> [any Persistable] {
        try await context.fdbContext.fetchPolymorphic(T.self)
    }

    /// Fetch a concrete Persistable type directly (non-polymorphic).
    /// Exposed for `@testable` diagnostics.
    internal func _debugFetchAll<T: Persistable>(_ type: T.Type) async throws -> [T] {
        try await context.fdbContext.fetch(type).execute()
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

    /// Directly insert a Persistable (bypassing `resolveAndInsertEntities`) and
    /// commit. Used by diagnostic tests to isolate the dual-write code path
    /// from entity-resolution logic.
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
