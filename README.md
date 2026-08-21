# swift-memory

Knowledge persistence and associative recall for LLM agents.

## Design Philosophy

Memory is the whole — a system that holds what has been given and what has been understood, and reactivates them on demand.

Memory contains two kinds of content:

- **Given** — what is presented as material for interpretation: text, images, events. Not yet structured, but not nothing — the ground on which meaning is built.
- **Knowledge** — structured relationships between concepts, expressed as statements (subject–predicate–object). The stable product of interpretation.

**Concept** mediates between them. It is the operation that carves distinctions in the Given, groups what belongs together, and places things in relation. Concept is not stored — it is a dynamic act performed by an external agent (LLM, VLM, rules). Each time input arrives, the agent interprets Given into Knowledge through Concept. Each time recall occurs, Concept is reconstructed from what Memory holds.

This means Memory persists **Given** and **Knowledge**, while **Concept** lives outside — in the interpreting agent. The cycle is:

```
Given → Concept (external) → Knowledge → shapes future interpretation of Given
```

**Grounding** is not a separate layer. It is a kind of Knowledge — statements that bind a Given to its interpretation ("this conversation produced this understanding").

## Data Flow

```
Input
  ↓
Concept (external agent: LLM / VLM / rules)
  ├─ selects sensory material      → Given  (vector embedding)
  └─ structures relationships      → Knowledge (RDF statements)
  ↓
Memory.store(batch)
  ├─ Given Store   (vector index, 768d cosine)
  └─ Knowledge Store (graph index, triple store)

Memory.recall(query)
  ├─ Vector similarity search  → givens
  └─ Spreading activation      → entities
  ↓
RecallResult (givens + entities)
```

## API

```swift
let memory = try await Memory(
    path: "memory.sqlite",
    entityRegistrations: [
        try MemoryEntityRegistration(Person.self),
        try MemoryEntityRegistration(Organization.self),
    ],
    embeddingProvider: embeddingProvider,
    authorization: authorization
)

// Store — called by the interpreting agent (Concept)
var batch = MemoryBatch()
batch.entity(person)                              // @OWLClass Persistable
batch.triple("ex:alice", "ex:worksAt", "ex:acme") // Explicit relationship
try await memory.store(batch)

// Recall — reactivates what Memory holds
let result = try await memory.recall(keywords: ["Alice", "auth"])
for entity in result.entities {
    print("\(entity.label) (score: \(entity.score))")
}
for given in result.givens {
    print("\(given.modality): \(given.payloadRef)")
}
```

### RecallQuery

Recall supports two strategies, usable independently or together:

```swift
// Keywords: spreading activation on Knowledge graph
let result = try await memory.recall(keywords: ["Alice"], maxHops: 2, limit: 20)

// Embedding: vector similarity on Given store
let result = try await memory.recall(RecallQuery(embedding: vector, limit: 10))

// Both: combined recall
let result = try await memory.recall(RecallQuery(
    keywords: ["Alice"],
    embedding: vector,
    maxHops: 2,
    limit: 20
))
```

## Recall: Spreading Activation

Given keywords (cues), the recall algorithm reactivates Knowledge:

1. **Name recall** — Find entities whose `rdfs:label` matches any keyword
2. **Spread** — Traverse relationships bidirectionally up to N hops
3. **Convergence** — Entities reached from multiple keywords score higher
4. **Return** — Sorted by score, with traversal paths for explainability

```
recall(keywords: ["Alice", "auth"])

  "Alice" → ex:Person/alice (direct match)
  "auth"  → ex:Activity/auth_module (direct match)

  Spread from both seeds:
    alice → worksAt → acme         (score +1)
    alice → memberOf → backend     (score +1)
    auth_module → partOf → backend (score +1)

  Convergence:
    backend: reached from Alice AND auth → score 2 (strongest association)
    acme: reached from Alice only → score 1
```

When an embedding is provided, Memory also searches the Given store by vector similarity — returning the raw materials that are semantically closest to the query.

## Embedding Boundary

`EmbeddingProvider` is an injected boundary. Native apps may provide local ML implementations. Browser and Cloudflare Worker builds should keep model APIs in the host runtime and pass vectors into Swift through `HostEmbeddingProvider`.

```
Host runtime
  └─ model API / Workers AI / browser fetch
       ↓ batch normalized vectors
Swift WASM
  └─ Memory.store / Memory.resolve
```

`Memory` calls the batch embedding API for entity store and resolve paths. Returned vectors are checked against the configured index dimensions before persistence or vector search.

## Key Types

| Type | Role |
|------|------|
| `Memory` (actor) | Public API: `store` / `recall` |
| `MemoryEntityRegistration` | Statically couples an entity schema, runtime decoder, indexes, and authorization policy |
| `MemoryEntityRecord` | Captures a concrete entity and its specialized insert operation for heterogeneous batches |
| `Given` | Sensory material with vector embedding (768d cosine) |
| `Statement` | RDF triple in the knowledge graph (subject–predicate–object) |
| `MemoryBatch` | Container for entities + statements, produced by external Concept |
| `MemoryBatchConvertible` | Protocol for types that convert to `MemoryBatch` |
| `EmbeddingProvider` | Boundary for native or host-provided embeddings |
| `RecallQuery` | Query parameters: keywords, embedding, maxHops, limit |
| `RecallResult` | Result: `entities` (from graph) + `givens` (from vector search) |
| `RecalledEntity` | Entity with IRI, label, type, convergence score, and traversal paths |
| `OntologyPolicy` | Defines allowed classes and properties in the knowledge graph |

## Entity Types

Client entities are statically compiled `@Persistable` models. `Entity`
provides the shared polymorphic vector index and refines DatabaseKit's
`SecurityPolicy`; every registered entity must therefore make explicit read,
query, create, update, and delete decisions. The shared index currently fixes
all entity embeddings at 768 dimensions.

String-backed `@Persistable` identifiers automatically satisfy
`Entity.memoryID`, and `persistableType` supplies `Entity.memoryType`. Entities
with another identifier representation must provide their own stable string
mapping. `memoryLabel` is explicit: return the user-facing label to persist as
`rdfs:label`, or rely on its default `nil` to use `memoryID`.

```swift
@Persistable
struct Person: Entity {
    #Directory<Person>("agent", "people")

    var id: String = UUID().uuidString
    var name: String
    var assertion: String = ""
    var embedding: Vector = Vector(int8: [])

    var memoryLabel: String? { name }

    static func permitsRead(
        of resource: borrowing Person,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsCreate(
        _ newResource: borrowing Person,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsUpdate(
        from resource: borrowing Person,
        to newResource: borrowing Person,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }

    static func permitsDelete(
        _ resource: borrowing Person,
        in context: borrowing AuthorizationContext
    ) -> Bool { context.isAuthenticated }
}
```

`MemoryEntityRegistration(Person.self)` compiles the model's schema, runtime
decoder, vector-index support, and `SecurityPolicy` handler into one
registration. `Memory` keeps Database Framework policy evaluation enabled;
missing policies fail closed.

When an entity is inserted through `Memory.store(batch)`, Memory writes its
typed row and recall identity statements. Explicit batch statements use
`RDFTerm`: valid IRIs remain graph resources, plain object text remains a
literal, and aliases resolved to stored entities remain resource-to-resource
graph edges.

## Database Framework 26.819 Migration

This release migrates from the runtime-metatype/FDB-oriented API to Database
Framework's static schema and explicit runtime model.

| Before | Current contract |
|---|---|
| `entityTypes: [Person.self]` | `entityRegistrations: [try MemoryEntityRegistration(Person.self)]` |
| Entity embedding as `[Float]` | Persisted `DatabaseTypes.Vector`; providers still return `[Float]` |
| Inferred runtime schema | `Schema.Entity` plus `EntityRuntimeRegistration` |
| Implicit clocks and IDs | Explicit `StorageMonotonicClock`, `WallClock`, and app-generated ULIDs |
| String graph fields | `RDFGraphName` and `RDFTerm` |
| Runtime field-name reflection | Explicit `memoryID`, `memoryType`, and `memoryLabel` contracts |
| Existential entity insertion | `MemoryEntityRecord` captures a concrete specialized insert closure |
| Missing authorization policy tolerated | `Entity: SecurityPolicy`; missing policy is denied |
| Duplicate insert behaved like upsert | Content-addressable `Statement` explicitly uses `upsert` |

The package selects the `SQLite`, `VectorIndexes`, and `GraphIndexes` traits.
Pass `path: nil` for an in-memory database, a file path for SQLite on macOS, or
use `Memory(storageEngine:...)` to inject a host storage engine. WASI does not
provide path-backed SQLite through `Memory(path:)`. Standard and Embedded WASM
use WASI realtime/monotonic clocks; Foundation-only `Data`, `URL`, JSON-byte,
and `Codable` conveniences are available only where those platform
capabilities exist.

## Modules

| Module | Purpose |
|--------|---------|
| `SwiftMemory` | Core: Memory actor, MemoryBatch, RecallEngine, Given, Statement |
| `MemoryOntology` | OntologyPolicy protocol + DefaultOntologyPolicy (26 primitives) |
