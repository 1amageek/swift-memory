// RecallEngine.swift
// Spreading activation associative memory

import Foundation
import Database
import os.log

private let logger = Logger(subsystem: "com.memory", category: "RecallEngine")

/// Associative memory recall via spreading activation.
///
/// Given cues (keywords), finds seed entities by label match,
/// then spreads activation bidirectionally through the graph.
/// Entities reached from multiple cues score higher (convergence).
public struct RecallEngine: Sendable {

    private static let excludedPredicates: Set<String> = [
        "rdf:type",
        "rdfs:label",
        "rdfs:comment",
    ]

    private let context: MemoryContext

    public init(context: MemoryContext) {
        self.context = context
    }

    /// Execute a recall query.
    public func execute(_ query: RecallQuery) async throws -> RecallResult {
        var entities: [RecalledEntity] = []
        var givens: [Given] = []

        if !query.keywords.isEmpty {
            entities = try await associate(
                cues: query.keywords,
                maxHops: query.maxHops,
                limit: query.limit
            )
        }

        if let embedding = query.embedding {
            givens = try await searchGivens(embedding: embedding, limit: query.limit)
        }

        return RecallResult(entities: entities, givens: givens)
    }

    // MARK: - Associate

    /// Core spreading activation algorithm.
    ///
    /// 1. Name recall: find entities whose rdfs:label contains any cue
    /// 2. Spread activation bidirectionally up to maxHops
    /// 3. Score by convergence (paths reaching each entity)
    /// 4. Resolve labels and types, sort by score
    private func associate(
        cues: [String],
        maxHops: Int,
        limit: Int
    ) async throws -> [RecalledEntity] {

        var activation: [String: (count: Int, paths: [String])] = [:]

        // Step 1: Name recall — find seed entities
        var seedIRIs: Set<String> = []
        for cue in cues {
            let result = try await context.fdbContext.sparql(Statement.self)
                .defaultIndex()
                .where("?entity", "rdfs:label", "?label")
                .filter("?label", contains: cue)
                .select(["?entity"])
                .execute()

            for binding in result.bindings {
                if let iri = binding.string("?entity") {
                    seedIRIs.insert(iri)
                }
            }
        }

        logger.info("[associate] cues=\(cues) seeds=\(seedIRIs.count)")
        guard !seedIRIs.isEmpty else { return [] }

        // Step 2: Spread from each seed
        for seedIRI in seedIRIs {
            activate(&activation, iri: seedIRI, path: "direct match")
            try await spread(
                from: seedIRI,
                seedIRI: seedIRI,
                hop: 1,
                maxHops: maxHops,
                visited: [seedIRI],
                activation: &activation
            )
        }

        // Step 3: Resolve labels and types
        var results: [RecalledEntity] = []
        for (iri, entry) in activation {
            let label = try await resolveLabel(for: iri)
            let type = try await resolveType(for: iri)
            results.append(RecalledEntity(
                iri: iri,
                label: label,
                type: type,
                score: entry.count,
                paths: entry.paths
            ))
        }

        // Step 4: Sort by score descending
        results.sort { $0.score > $1.score }
        logger.info("[associate] results=\(results.count)")
        return Array(results.prefix(limit))
    }

    /// Recursive bidirectional spread.
    private func spread(
        from iri: String,
        seedIRI: String,
        hop: Int,
        maxHops: Int,
        visited: Set<String>,
        activation: inout [String: (count: Int, paths: [String])]
    ) async throws {
        guard hop <= maxHops else { return }

        // Outgoing: iri → ?rel → ?target
        let outgoing = try await context.fdbContext.sparql(Statement.self)
            .defaultIndex()
            .where(iri, "?rel", "?target")
            .select(["?target", "?rel"])
            .execute()

        for binding in outgoing.bindings {
            guard let target = binding.string("?target"),
                  let rel = binding.string("?rel"),
                  !Self.excludedPredicates.contains(rel),
                  !target.hasPrefix("\""),
                  !visited.contains(target) else { continue }

            activate(&activation, iri: target, path: "\(iri) --[\(rel)]--> \(target)")

            // Continue spreading
            var nextVisited = visited
            nextVisited.insert(target)
            try await spread(
                from: target,
                seedIRI: seedIRI,
                hop: hop + 1,
                maxHops: maxHops,
                visited: nextVisited,
                activation: &activation
            )
        }

        // Incoming: ?source → ?rel → iri
        let incoming = try await context.fdbContext.sparql(Statement.self)
            .defaultIndex()
            .where("?source", "?rel", iri)
            .select(["?source", "?rel"])
            .execute()

        for binding in incoming.bindings {
            guard let source = binding.string("?source"),
                  let rel = binding.string("?rel"),
                  !Self.excludedPredicates.contains(rel),
                  !visited.contains(source) else { continue }

            activate(&activation, iri: source, path: "\(source) --[\(rel)]--> \(iri)")

            var nextVisited = visited
            nextVisited.insert(source)
            try await spread(
                from: source,
                seedIRI: seedIRI,
                hop: hop + 1,
                maxHops: maxHops,
                visited: nextVisited,
                activation: &activation
            )
        }
    }

    // MARK: - Activation

    private func activate(
        _ activation: inout [String: (count: Int, paths: [String])],
        iri: String,
        path: String
    ) {
        var entry = activation[iri] ?? (count: 0, paths: [])
        entry.count += 1
        entry.paths.append(path)
        activation[iri] = entry
    }

    // MARK: - Resolution

    private func resolveLabel(for iri: String) async throws -> String {
        let result = try await context.fdbContext.sparql(Statement.self)
            .defaultIndex()
            .where(iri, "rdfs:label", "?label")
            .select(["?label"])
            .execute()
        guard let raw = result.bindings.first?.string("?label") else { return iri }
        return cleanLiteral(raw)
    }

    private func resolveType(for iri: String) async throws -> String {
        let result = try await context.fdbContext.sparql(Statement.self)
            .defaultIndex()
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

    // MARK: - Given Store

    private func searchGivens(embedding: [Float], limit: Int) async throws -> [Given] {
        let results = try await context.fdbContext.findSimilar(Given.self)
            .vector(\.embedding, dimensions: embedding.count)
            .query(embedding, k: limit)
            .execute()
        return results.map(\.item)
    }
}
