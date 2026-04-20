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
/// entity's resolution embedding text matches an existing entity above the
/// configured threshold, the incoming entity is discarded and only the
/// existing entity's `updated` timestamp is refreshed. Relationship
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
                now: now,
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
    /// For every input entity, computes a query embedding from its resolution
    /// text and compares against existing entities (fetched once upfront).
    /// If the best cosine similarity is at or above the threshold, the input
    /// is treated as a duplicate: the existing record's `updated` timestamp
    /// is refreshed and no new record is created. Otherwise the input is
    /// inserted with its embedding and `created`/`updated` set to `now`.
    ///
    /// Newly inserted entities are appended to the candidate list so that
    /// later entities in the same batch resolve against them (self-collision
    /// handling).
    ///
    /// - Returns: Map from input entity label to the resolved entity ID.
    private func resolveAndInsertEntities(
        _ entities: [any Persistable & Entity & Sendable],
        now: Date,
        provider: any EmbeddingProvider
    ) async throws -> [String: String] {
        guard let first = entities.first else { return [:] }
        return try await _resolveAndInsertEntities(
            entities,
            witness: first,
            now: now,
            provider: provider
        )
    }

    private func _resolveAndInsertEntities<E: Persistable & Entity & Sendable>(
        _ entities: [any Persistable & Entity & Sendable],
        witness: E,
        now: Date,
        provider: any EmbeddingProvider
    ) async throws -> [String: String] {
        let existingItems = try await context.fdbContext.fetchPolymorphic(E.self)

        var candidates: [ResolutionCandidate] = []
        candidates.reserveCapacity(existingItems.count)
        for item in existingItems {
            guard let ent = item as? any Persistable & Entity & Sendable else { continue }
            candidates.append(ResolutionCandidate(
                id: String(describing: item.id),
                label: ent.label,
                embedding: ent.embedding,
                persistable: ent
            ))
        }

        var resolutionMap: [String: String] = [:]
        resolutionMap.reserveCapacity(entities.count)

        for entity in entities {
            let queryVec = try await provider.embed(entity.resolutionEmbeddingText)

            var bestIndex: Int?
            var bestSimilarity: Float = 0
            for i in 0..<candidates.count {
                let candEmbedding = candidates[i].embedding
                guard candEmbedding.count == queryVec.count else { continue }
                let sim = Self.cosineSimilarity(queryVec, candEmbedding)
                if sim >= resolutionThreshold && sim > bestSimilarity {
                    bestSimilarity = sim
                    bestIndex = i
                }
            }

            if let idx = bestIndex {
                var existing = candidates[idx].persistable
                existing.updated = now
                context.fdbContext.insert(existing)
                resolutionMap[entity.label] = candidates[idx].id
                logger.info(
                    "[resolve] match '\(entity.label)' -> '\(candidates[idx].label)' sim=\(bestSimilarity)"
                )
            } else {
                var mutable = entity
                mutable.embedding = queryVec
                mutable.created = now
                mutable.updated = now
                context.fdbContext.insert(mutable)

                let newID = String(describing: mutable.id)
                resolutionMap[entity.label] = newID

                candidates.append(ResolutionCandidate(
                    id: newID,
                    label: mutable.label,
                    embedding: queryVec,
                    persistable: mutable
                ))
                logger.info("[resolve] new '\(entity.label)' id=\(newID)")
            }
        }

        return resolutionMap
    }

    private struct ResolutionCandidate: Sendable {
        let id: String
        let label: String
        let embedding: [Float]
        let persistable: any Persistable & Entity & Sendable
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
    /// For each candidate, embeds its text ("{type} {label} {context}"),
    /// fetches all existing entities from the shared Entity polymorphic group,
    /// and returns the best match at or above the similarity threshold.
    ///
    /// This API is for callers that want to inspect resolution results before
    /// deciding what to store. Regular `store()` calls perform the same logic
    /// internally.
    ///
    /// - Parameters:
    ///   - candidates: Entity candidates with type, label, and optional context.
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
                ResolvedEntity(inputLabel: $0.label, inputType: $0.type)
            }
        }

        guard !candidates.isEmpty else { return [] }

        let existingItems = try await context.fdbContext.fetchPolymorphic(T.self)

        var entityIDs: [String] = []
        var entityLabels: [String] = []
        var entityEmbeddings: [[Float]] = []

        for item in existingItems {
            guard let entity = item as? any Entity else { continue }
            entityIDs.append(String(describing: item.id))
            entityLabels.append(entity.label)
            entityEmbeddings.append(entity.embedding)
        }

        var results: [ResolvedEntity] = []
        results.reserveCapacity(candidates.count)

        for candidate in candidates {
            let queryEmbedding = try await provider.embed(candidate.embeddingText)

            var bestIndex: Int?
            var bestSimilarity: Float = 0

            for i in 0..<entityIDs.count {
                let emb = entityEmbeddings[i]
                guard !emb.isEmpty, emb.count == queryEmbedding.count else { continue }
                let sim = Self.cosineSimilarity(queryEmbedding, emb)
                if sim >= effectiveThreshold && sim > bestSimilarity {
                    bestIndex = i
                    bestSimilarity = sim
                }
            }

            if let idx = bestIndex {
                results.append(ResolvedEntity(
                    inputLabel: candidate.label,
                    inputType: candidate.type,
                    matchedID: entityIDs[idx],
                    matchedLabel: entityLabels[idx],
                    similarity: bestSimilarity
                ))
            } else {
                results.append(ResolvedEntity(
                    inputLabel: candidate.label,
                    inputType: candidate.type
                ))
            }
        }

        let resolvedCount = results.filter(\.isResolved).count
        logger.info("[resolve] \(candidates.count) candidates -> \(resolvedCount) resolved")
        return results
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
