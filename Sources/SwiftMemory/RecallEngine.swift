// RecallEngine.swift
// Spreading activation associative memory recall

import Foundation
import FDBite

/// Recall Engine — spreading activation over the knowledge graph.
///
/// Mimics human associative memory:
/// 1. Keywords match entity labels → seed entities
/// 2. Activation spreads bidirectionally through relationships
/// 3. Entities reached by multiple paths score higher (convergence)
/// 4. Results sorted by score, with traversal paths for explainability
///
/// Metadata predicates (rdf:type, rdfs:label) are excluded from spreading
/// to prevent structural noise from dominating content relationships.
public struct RecallEngine: Sendable {

    /// Predicates excluded from spreading activation.
    /// These are structural metadata, not content relationships.
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
    ///
    /// - Keywords trigger spreading activation over the knowledge graph
    /// - Embedding triggers vector similarity search on Given Store
    public func execute(_ query: RecallQuery) async throws -> RecallResult {
        var entities: [RecalledEntity] = []
        var givens: [Given] = []

        // Spreading activation on Knowledge Store
        if !query.keywords.isEmpty {
            entities = try await spreadingActivation(
                keywords: query.keywords,
                maxHops: query.maxHops,
                limit: query.limit
            )
        }

        // Vector similarity on Given Store
        if let embedding = query.embedding {
            givens = try await searchGivens(embedding: embedding, limit: query.limit)
        }

        return RecallResult(entities: entities, givens: givens)
    }

    // MARK: - Spreading Activation

    /// Core spreading activation algorithm.
    ///
    /// 1. Name recall: find entities whose rdfs:label contains any keyword
    /// 2. Spread activation bidirectionally up to maxHops
    /// 3. Score by convergence (number of paths reaching each entity)
    /// 4. Resolve labels and types, sort by score
    private func spreadingActivation(
        keywords: [String],
        maxHops: Int,
        limit: Int
    ) async throws -> [RecalledEntity] {

        // Activation map: IRI → (count, paths)
        var activation: [String: (count: Int, paths: [String])] = [:]

        // Step 1: Name recall — find seed entities
        var seedIRIs: Set<String> = []
        for keyword in keywords {
            let result = try await context.fdbContext.sparql(Statement.self)
                .defaultIndex()
                .where("?entity", "rdfs:label", "?label")
                .filter("?label", contains: keyword)
                .select(["?entity"])
                .execute()

            for binding in result.bindings {
                if let iri = binding.string("?entity") {
                    seedIRIs.insert(iri)
                }
            }
        }

        // Step 2: Spread activation from each seed
        for seedIRI in seedIRIs {
            // Activate seed itself
            activate(&activation, iri: seedIRI, path: "direct match")

            // 1-hop outgoing: seed → ?rel → ?target
            let hop1Out = try await context.fdbContext.sparql(Statement.self)
                .defaultIndex()
                .where(seedIRI, "?rel", "?target")
                .select(["?target", "?rel"])
                .execute()

            for binding in hop1Out.bindings {
                guard let target = binding.string("?target"),
                      let rel = binding.string("?rel"),
                      !Self.excludedPredicates.contains(rel),
                      !target.hasPrefix("\"") else { continue }

                activate(&activation, iri: target, path: "\(seedIRI) --[\(rel)]--> \(target)")

                // 2-hop from outgoing target
                if maxHops >= 2 {
                    let hop2 = try await context.fdbContext.sparql(Statement.self)
                        .defaultIndex()
                        .where(target, "?rel2", "?target2")
                        .select(["?target2", "?rel2"])
                        .execute()

                    for b2 in hop2.bindings {
                        guard let target2 = b2.string("?target2"),
                              let rel2 = b2.string("?rel2"),
                              !Self.excludedPredicates.contains(rel2),
                              !target2.hasPrefix("\""),
                              target2 != seedIRI else { continue }

                        activate(&activation, iri: target2,
                                 path: "\(seedIRI) → \(target) --[\(rel2)]--> \(target2)")
                    }
                }
            }

            // 1-hop incoming: ?source → ?rel → seed
            let hop1In = try await context.fdbContext.sparql(Statement.self)
                .defaultIndex()
                .where("?source", "?rel", seedIRI)
                .select(["?source", "?rel"])
                .execute()

            for binding in hop1In.bindings {
                guard let source = binding.string("?source"),
                      let rel = binding.string("?rel"),
                      !Self.excludedPredicates.contains(rel) else { continue }

                activate(&activation, iri: source, path: "\(source) --[\(rel)]--> \(seedIRI)")

                // 2-hop from incoming source
                if maxHops >= 2 {
                    let hop2 = try await context.fdbContext.sparql(Statement.self)
                        .defaultIndex()
                        .where("?source2", "?rel2", source)
                        .select(["?source2", "?rel2"])
                        .execute()

                    for b2 in hop2.bindings {
                        guard let source2 = b2.string("?source2"),
                              let rel2 = b2.string("?rel2"),
                              !Self.excludedPredicates.contains(rel2),
                              source2 != seedIRI else { continue }

                        activate(&activation, iri: source2,
                                 path: "\(source2) --[\(rel2)]--> \(source) → \(seedIRI)")
                    }
                }
            }
        }

        // Step 3: Resolve labels and types, build results
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

        // Step 4: Sort by score descending, limit
        results.sort { $0.score > $1.score }
        return Array(results.prefix(limit))
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

    // MARK: - Label / Type Resolution

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

    /// Strip RDF literal syntax: "text"@ja → text, "text"^^xsd:string → text
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

    /// Search givens by vector similarity.
    private func searchGivens(embedding: [Float], limit: Int) async throws -> [Given] {
        let results = try await context.fdbContext.findSimilar(Given.self)
            .vector(\.embedding, dimensions: embedding.count)
            .query(embedding, k: limit)
            .execute()
        return results.map(\.item)
    }
}
