// RecallEngine.swift
// Spreading activation associative memory

import Database

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

    private var graphNames: [RDFGraphName] { [context.graphName] }

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

        // Vector search over Given: only when an explicit query embedding is
        // provided. Keyword-only recall does not auto-embed because the
        // decision to run a vector search should be made by the caller.
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

        var activation: [ActivationNode: (count: Int, paths: [String])] = [:]

        // Step 1: Name recall — find seed entities by label substring match.
        // Free-form statements are stored in `context.graphName`; typed
        // @OWLClass entities commonly materialize in the macro default graph.
        var seedIRIs: Set<String> = []
        for cue in cues {
            for graph in graphNames {
                let result = try await context.databaseContext.sparql(namedGraph: graph)
                    .where(
                        .variable("?entity"),
                        try MemoryRDF.executionPredicate("rdfs:label"),
                        .variable("?label")
                    )
                    .filter("?label", contains: cue)
                    .select(["?entity"])
                    .execute()

                for binding in result.bindings {
                    if let iri = MemoryRDF.resourceValue(binding, variable: "?entity") {
                        seedIRIs.insert(iri)
                    }
                }
            }
        }

        MemoryLog.info(category: "RecallEngine", "[associate] cues=\(cues) seeds=\(seedIRIs.count)")
        guard !seedIRIs.isEmpty else { return [] }

        // Step 2: Spread from each seed
        for seedIRI in seedIRIs {
            activate(&activation, node: .resource(seedIRI), path: "direct match")
            try await spread(
                from: seedIRI,
                hop: 1,
                maxHops: maxHops,
                visited: [seedIRI],
                activation: &activation
            )
        }

        // Step 3: Resolve labels and types
        var results: [RecalledEntity] = []
        for (node, entry) in activation {
            let iri: String
            let label: String
            let type: String
            switch node {
            case .resource(let value):
                iri = value
                label = try await resolveLabel(for: value)
                type = try await resolveType(for: value)
            case .literal(let value):
                iri = value
                label = value
                type = "Literal"
            }
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
        MemoryLog.info(category: "RecallEngine", "[associate] results=\(results.count)")
        return Array(results.prefix(limit))
    }

    /// Recursive bidirectional spread.
    private func spread(
        from iri: String,
        hop: Int,
        maxHops: Int,
        visited: Set<String>,
        activation: inout [ActivationNode: (count: Int, paths: [String])]
    ) async throws {
        guard hop <= maxHops else { return }

        let sourceTerms = try await equivalentTerms(for: iri)
        for graph in graphNames {
            for sourceTerm in sourceTerms {
                // Outgoing: iri → ?rel → ?target
                let outgoing = try await context.databaseContext.sparql(namedGraph: graph)
                    .where(
                        try MemoryRDF.executionResource(sourceTerm),
                        .variable("?rel"),
                        .variable("?target")
                    )
                    .select(["?target", "?rel"])
                    .execute()

                for binding in outgoing.bindings {
                    guard case .rdfTerm(let targetTerm)? = binding["?target"],
                          let rel = MemoryRDF.resourceValue(binding, variable: "?rel"),
                          !Self.excludedPredicates.contains(rel) else { continue }

                    switch targetTerm {
                    case .iri, .blankNode:
                        guard let target = MemoryRDF.value(targetTerm) else { continue }
                        let canonicalTarget = try await canonicalTerm(for: target)
                        guard !visited.contains(canonicalTarget) else { continue }

                        activate(
                            &activation,
                            node: .resource(canonicalTarget),
                            path: "\(sourceTerm) --[\(rel)]--> \(target)"
                        )

                        var nextVisited = visited
                        nextVisited.insert(canonicalTarget)
                        try await spread(
                            from: canonicalTarget,
                            hop: hop + 1,
                            maxHops: maxHops,
                            visited: nextVisited,
                            activation: &activation
                        )
                    case .literal:
                        guard let target = MemoryRDF.value(targetTerm) else { continue }
                        activate(
                            &activation,
                            node: .literal(target),
                            path: "\(sourceTerm) --[\(rel)]--> \(target)"
                        )
                    case .tripleTerm:
                        continue
                    }
                }

                // Incoming: ?source → ?rel → iri
                let incoming = try await context.databaseContext.sparql(namedGraph: graph)
                    .where(
                        .variable("?source"),
                        .variable("?rel"),
                        try MemoryRDF.executionResource(sourceTerm)
                    )
                    .select(["?source", "?rel"])
                    .execute()

                for binding in incoming.bindings {
                    guard let source = MemoryRDF.resourceValue(binding, variable: "?source"),
                          let rel = MemoryRDF.resourceValue(binding, variable: "?rel"),
                          !Self.excludedPredicates.contains(rel) else { continue }

                    let canonicalSource = try await canonicalTerm(for: source)
                    guard !visited.contains(canonicalSource) else { continue }

                    activate(
                        &activation,
                        node: .resource(canonicalSource),
                        path: "\(source) --[\(rel)]--> \(sourceTerm)"
                    )

                    var nextVisited = visited
                    nextVisited.insert(canonicalSource)
                    try await spread(
                        from: canonicalSource,
                        hop: hop + 1,
                        maxHops: maxHops,
                        visited: nextVisited,
                        activation: &activation
                    )
                }
            }
        }
    }

    // MARK: - Activation

    private enum ActivationNode: Hashable {
        case resource(String)
        case literal(String)
    }

    private func activate(
        _ activation: inout [ActivationNode: (count: Int, paths: [String])],
        node: ActivationNode,
        path: String
    ) {
        var entry = activation[node] ?? (count: 0, paths: [])
        entry.count += 1
        entry.paths.append(path)
        activation[node] = entry
    }

    // MARK: - Resolution

    private func resolveLabel(for iri: String) async throws -> String {
        for term in try await equivalentTerms(for: iri) {
            for graph in graphNames {
                let result = try await context.databaseContext.sparql(namedGraph: graph)
                    .where(
                        try MemoryRDF.executionResource(term),
                        try MemoryRDF.executionPredicate("rdfs:label"),
                        .variable("?label")
                    )
                    .select(["?label"])
                    .execute()
                if let first = result.bindings.first,
                   let raw = MemoryRDF.value(first, variable: "?label") {
                    return cleanLiteral(raw)
                }
            }
        }
        return iri
    }

    private func resolveType(for iri: String) async throws -> String {
        for term in try await equivalentTerms(for: iri) {
            for graph in graphNames {
                let result = try await context.databaseContext.sparql(namedGraph: graph)
                    .where(
                        try MemoryRDF.executionResource(term),
                        try MemoryRDF.executionPredicate("rdf:type"),
                        .variable("?type")
                    )
                    .select(["?type"])
                    .execute()
                if let first = result.bindings.first,
                   let type = MemoryRDF.resourceValue(first, variable: "?type") {
                    return type
                }
            }
        }
        return ""
    }

    private func canonicalTerm(for term: String) async throws -> String {
        if term.hasPrefix("entity:") {
            return term
        }
        let entityIRIs = try await entityIRIs(forStorageID: term)
        return entityIRIs.sorted().first ?? term
    }

    private func equivalentTerms(for term: String) async throws -> [String] {
        var terms = [term]
        if let storageID = storageID(fromEntityIRI: term) {
            terms.append(storageID)
        } else {
            terms.append(contentsOf: try await entityIRIs(forStorageID: term))
        }
        return orderedUnique(terms)
    }

    private func entityIRIs(forStorageID storageID: String) async throws -> [String] {
        guard !storageID.isEmpty else { return [] }
        var matches: [String] = []
        for graph in graphNames {
            let result = try await context.databaseContext.sparql(namedGraph: graph)
                .where(
                    .variable("?entity"),
                    try MemoryRDF.executionPredicate("rdf:type"),
                    .variable("?type")
                )
                .filter("?entity", contains: "/\(storageID)")
                .select(["?entity"])
                .execute()
            for binding in result.bindings {
                if let iri = MemoryRDF.resourceValue(binding, variable: "?entity") {
                    matches.append(iri)
                }
            }
        }
        return orderedUnique(matches)
    }

    private func storageID(fromEntityIRI iri: String) -> String? {
        guard iri.hasPrefix("entity:"),
              let slash = iri.lastIndex(of: "/"),
              slash < iri.index(before: iri.endIndex) else {
            return nil
        }
        return String(iri[iri.index(after: slash)...])
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values where seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }

    private func cleanLiteral(_ raw: String) -> String {
        guard raw.hasPrefix("\""),
              let closingQuote = raw.lastIndex(of: "\""),
              closingQuote > raw.startIndex else { return raw }
        return String(raw[raw.index(after: raw.startIndex)..<closingQuote])
    }

    // MARK: - Given Store

    private func searchGivens(embedding: [Float], limit: Int) async throws -> [Given] {
        let results = try await context.databaseContext.findSimilar(Given.self)
            .vector(Given.fields.embedding, dimensions: embedding.count)
            .query(embedding, k: limit)
            .execute()
        return results.map { $0.item }
    }
}
