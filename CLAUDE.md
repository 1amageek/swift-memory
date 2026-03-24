# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
swift build
xcodebuild test -scheme Memory -destination 'platform=macOS' -maximum-test-execution-time-allowance 60
```

Requires FoundationDB client library at `/usr/local/lib` (linker flags are configured in Package.swift).

## Architecture

Memory is a knowledge persistence system for LLM agents. It stores **Given** (selected sensory materials) and **Knowledge** (structured statements). **Concepts are not stored** — LLM reconstructs them at inference time.

### Design Principles

- `store(input)` does not save raw input. Input passes through the **Concept Protocol** (`MemoryEncoding`), which is implemented by the **client**, not this framework
- `MemoryEncoding` is external — the client provides an implementation (LLM, VLM, rules) that interprets input and produces Given + Knowledge
- `recall(query)` is pure data retrieval from Given Store (vector) and Knowledge Store (graph)
- `Statement` is the atomic unit of knowledge (subject-predicate-object); `MemoryBatch.knowledge` is the collection
- Grounding is not a separate layer — it is a kind of Knowledge (expressed as statements)

### Data Flow

```
Input → MemoryEncoding (client-provided) → [Given, Knowledge] → Memory.store() → FDB
Memory.recall(query) → RecallEngine → vector search + graph traversal → MemoryBatch
```

### Key Types

- **`Memory`** (actor) — public API: `store(any MemoryEncodable)` / `recall(RecallQuery) -> MemoryBatch`
- **`MemoryEncoding`** (protocol) — Concept Protocol; client implements `encode(any MemoryEncodable) -> MemoryBatch`
- **`Given`** (`@Persistable`) — sensory material with vector embedding; ScalarIndex on timestamp/source, VectorIndex on embedding (384d cosine)
- **`Statement`** (`@Persistable`) — RDF triple (subject/predicate/object); GraphIndex with `.tripleStore` strategy
- **`MemoryBatch`** — `givens: [Given]` + `knowledge: [Statement]`; `asHOOT()` for compact LLM context
- **`RecallEngine`** — vector similarity search on Given, SPARQL graph traversal on Statement
- **`OntologyPolicy`** — 26 primitive classes, ~120 subclasses, seed properties (copied from AURORA, `MemoryContext` namespace)

### Dependencies

- **database-kit** — `@Persistable` macro, `GraphIndexKind`, `VectorIndexKind`, `OWLOntology`
- **database-framework** — `FDBContext`, `DBContainer`, SPARQL execution, `GraphIndex`
- **swift-hoot** — HOOT compact format for OWL ontology serialization (~1/3 tokens vs Turtle)

### OntologyPolicy

Copied verbatim from AURORA with only 2 substitutions (`AURORAContext` → `MemoryContext`). Contains the upper ontology (TBox): class hierarchy, disjoint declarations, standard properties. `OntologyPolicy.definition()` returns the LLM instruction text with HOOT-encoded vocabulary.
