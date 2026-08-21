# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
swift build
xcodebuild test -scheme swift-memory-Package -destination 'platform=macOS' -maximum-test-execution-time-allowance 60
```

The package uses Database Framework's `SQLite`, `VectorIndexes`,
`GraphIndexes`, and `MultiBase` traits. It does not require a local
FoundationDB client for the default in-memory or SQLite paths.

When using a Swift development snapshot with Xcode, the test bundle may need
the snapshot's `usr/lib/swift/macosx/testing` directory added to
`LD_RUNPATH_SEARCH_PATHS` so `libTesting.dylib` is available to xctest.

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
Input → client interpretation → MemoryBatch → Memory.store() → DatabaseContext
Memory.recall(query) → RecallEngine → vector search + graph traversal → RecallResult
```

One `MemoryLayer` maps to one Database Framework `Base`. Unscoped API calls use
`MemoryLayerSet.defaultLayer`. Cross-layer recall preflights a derived
Composition and preserves results as Base-qualified groups rather than
flattening equal identifiers across origins.

### Key Types

- **`Memory`** (actor) — public API: `store` / `resolve` / `recall`
- **`MemoryLayer`** — application-defined knowledge layer backed by one Base
- **`MemoryLayerSet`** — configured Base order and the default API layer
- **`LayeredRecallResult`** — cross-layer recall grouped by source Base
- **`MemoryEntityRegistration`** — binds static schema, executable runtime, polymorphic indexes, and authorization policy
- **`MemoryEntityRecord`** — captures concrete entity metadata and a statically specialized insert closure for heterogeneous batches
- **`Given`** (`@Persistable`) — sensory material with a 768-dimensional `Vector`; ordered timestamp/source indexes and cosine vector index
- **`Statement`** (`@Persistable`) — typed RDF quad (`RDFTerm` graph/subject/predicate/object) with a canonical graph index
- **`MemoryBatch`** — typed entities, explicit statement records, and endpoint aliases
- **`RecallEngine`** — vector similarity search on Given, SPARQL graph traversal on Statement
- **`OntologyPolicy`** — 26 primitive classes, ~120 subclasses, seed properties (copied from AURORA, `MemoryContext` namespace)

### Dependencies

- **database-kit 26.819+** — static `Schema.Entity`, `@Persistable`, polymorphic metadata, `RDFTerm`, `Vector`, and `SecurityPolicy`
- **database-framework 26.819+** — explicit `DatabaseRuntimeConfiguration`, `DatabaseContext`, SQLite/in-memory containers, vector and SPARQL execution
- **swift-hoot** — HOOT compact format for OWL ontology serialization (~1/3 tokens vs Turtle)

### Database Runtime Contract

- Schema construction uses `[Schema.Entity]`; do not restore runtime metatype schema discovery.
- Every schema entity has a matching `EntityRuntimeRegistration`.
- Every registered client `Entity` supplies a `SecurityPolicy`; policy evaluation remains enabled.
- MultiBase grants require an authenticated principal; anonymous initialization fails explicitly.
- A legacy `singleDatabase` physical root requires explicit export/import migration and is never silently opened as MultiBase.
- Database and memory use the same explicit monotonic and wall clocks.
- Persisted vectors use `DatabaseTypes.Vector`; convert provider `[Float]` output only at the persistence boundary.
- Graph fields and queries remain typed as `RDFTerm`, `RDFGraphName`, and explicit SPARQL execution terms.
- Content-addressable statements use explicit `upsert`; other entity insertion retains create semantics.
- Entity vector index dimensions are fixed at 768 across the `Entity` polymorphic group.
- Entity graph identity is explicit through `memoryID`, `memoryType`, and `memoryLabel`; do not restore reflection-based field discovery.
- Heterogeneous `MemoryBatch` values store `MemoryEntityRecord`, which specializes generic database insertion when the concrete entity is captured.
- Embedded Swift has no Foundation reflection or `Codable`. Keep core value and storage semantics common, and gate only capability-specific conveniences.

### OntologyPolicy

Copied verbatim from AURORA with only 2 substitutions (`AURORAContext` → `MemoryContext`). Contains the upper ontology (TBox): class hierarchy, disjoint declarations, standard properties. `OntologyPolicy.definition()` returns the LLM instruction text with HOOT-encoded vocabulary.
