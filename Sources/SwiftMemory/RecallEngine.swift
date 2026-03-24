// RecallEngine.swift
// Pure data retrieval: search givens + traverse knowledge

import Foundation
import FDBite

/// Recall Engine — searches Given Store and Knowledge Store, returns context.
///
/// Pure data retrieval layer. No LLM interpretation.
/// - Vector search on Given embeddings
/// - SPARQL traversal on Statement GraphIndex
/// - Graph traversal from anchor IRI
public struct RecallEngine: Sendable {

    private let context: MemoryContext

    public init(context: MemoryContext) {
        self.context = context
    }

    /// Execute a recall query and return matching Given + Knowledge.
    public func execute(_ query: RecallQuery) async throws -> MemoryBatch {
        var givens: [Given] = []
        var knowledge: [Statement] = []

        // Given Store: vector similarity search
        if let embedding = query.embedding {
            givens = try await searchGivens(embedding: embedding, limit: query.limit)
        }

        // Knowledge Store: graph traversal from anchor
        if let anchor = query.anchor {
            knowledge += try await traverseKnowledge(from: anchor, depth: query.depth, limit: query.limit)
        }

        // Knowledge Store: direct SPARQL
        if let sparql = query.sparql {
            knowledge += try await executeQuery(sparql)
        }

        return MemoryBatch(givens: givens, knowledge: knowledge)
    }

    // MARK: - Given Store

    /// Search givens by vector similarity.
    ///
    /// Uses the VectorIndex defined on Given.embedding (384 dimensions by default).
    private func searchGivens(embedding: [Float], limit: Int) async throws -> [Given] {
        let results = try await context.fdbContext.findSimilar(Given.self)
            .vector(\.embedding, dimensions: embedding.count)
            .query(embedding, k: limit)
            .execute()
        return results.map(\.item)
    }

    // MARK: - Knowledge Store: Graph Traversal

    /// Traverse knowledge graph from an anchor IRI, collecting statements.
    private func traverseKnowledge(from anchor: String, depth: Int, limit: Int) async throws -> [Statement] {
        var visited: Set<String> = []
        var result: [Statement] = []
        var frontier: Set<String> = [anchor]

        for _ in 0..<depth {
            guard !frontier.isEmpty, result.count < limit else { break }
            var nextFrontier: Set<String> = []

            for entity in frontier where !visited.contains(entity) {
                visited.insert(entity)

                // Forward: entity → ?p → ?o
                let forward = try await context.fdbContext.sparql(Statement.self)
                    .defaultIndex()
                    .where(entity, "?p", "?o")
                    .execute()

                for binding in forward.bindings {
                    if let p = binding.string("?p"),
                       let o = binding.string("?o") {
                        result.append(Statement(
                            graph: context.graphName,
                            subject: entity,
                            predicate: p,
                            object: o
                        ))
                        // Follow IRI objects to next hop (skip literals)
                        if !o.hasPrefix("\"") && !visited.contains(o) {
                            nextFrontier.insert(o)
                        }
                    }
                }

                // Backward: ?s → ?p → entity
                let backward = try await context.fdbContext.sparql(Statement.self)
                    .defaultIndex()
                    .where("?s", "?p", entity)
                    .execute()

                for binding in backward.bindings {
                    if let s = binding.string("?s"),
                       let p = binding.string("?p") {
                        result.append(Statement(
                            graph: context.graphName,
                            subject: s,
                            predicate: p,
                            object: entity
                        ))
                        if !visited.contains(s) {
                            nextFrontier.insert(s)
                        }
                    }
                }

                if result.count >= limit { break }
            }

            frontier = nextFrontier
        }

        return Array(result.prefix(limit))
    }

    // MARK: - Knowledge Store: SPARQL

    /// Execute a raw SPARQL query against the knowledge store.
    private func executeQuery(_ sparqlString: String) async throws -> [Statement] {
        let parser = SPARQLParser()
        let parsed = try parser.parse(sparqlString)

        guard case .select(let selectQuery) = parsed else {
            throw MemoryError.invalidQuery("Only SELECT queries are supported")
        }

        guard case .graphPattern(let graphPattern) = selectQuery.source else {
            throw MemoryError.invalidQuery("WHERE clause with graph pattern is required")
        }

        var builder = context.fdbContext.sparql(Statement.self)
            .defaultIndex()

        builder = applyPattern(builder, graphPattern)

        if let limit = selectQuery.limit {
            builder = builder.limit(limit)
        }

        let result = try await builder.execute()

        return result.bindings.compactMap { binding -> Statement? in
            guard let s = binding.string("?s"),
                  let p = binding.string("?p"),
                  let o = binding.string("?o") else { return nil }
            return Statement(
                graph: context.graphName,
                subject: s,
                predicate: p,
                object: o
            )
        }
    }

    private func applyPattern(
        _ builder: GraphIndex.SPARQLQueryBuilder<Statement>,
        _ pattern: QueryAST.GraphPattern
    ) -> GraphIndex.SPARQLQueryBuilder<Statement> {
        switch pattern {
        case .basic(let triplePatterns):
            var result = builder
            for tp in triplePatterns {
                result = result.where(
                    termString(tp.subject),
                    termString(tp.predicate),
                    termString(tp.object)
                )
            }
            return result
        case .join(let lhs, let rhs):
            return applyPattern(applyPattern(builder, lhs), rhs)
        default:
            return builder
        }
    }

    private func termString(_ term: QueryAST.SPARQLTerm) -> String {
        switch term {
        case .variable(let name): return "?\(name)"
        case .iri(let iri): return iri
        case .prefixedName(let prefix, let local): return "\(prefix):\(local)"
        default: return String(describing: term)
        }
    }
}
