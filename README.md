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
  ├─ Given Store   (vector index, 384d cosine)
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
    entityTypes: [Person.self, Organization.self]
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

## Key Types

| Type | Role |
|------|------|
| `Memory` (actor) | Public API: `store` / `recall` |
| `Given` | Sensory material with vector embedding (384d cosine) |
| `Statement` | RDF triple in the knowledge graph (subject–predicate–object) |
| `MemoryBatch` | Container for entities + statements, produced by external Concept |
| `MemoryBatchConvertible` | Protocol for types that convert to `MemoryBatch` |
| `RecallQuery` | Query parameters: keywords, embedding, maxHops, limit |
| `RecallResult` | Result: `entities` (from graph) + `givens` (from vector search) |
| `RecalledEntity` | Entity with IRI, label, type, convergence score, and traversal paths |
| `OntologyPolicy` | Defines allowed classes and properties in the knowledge graph |

## Entity Types

Entities are `@Persistable @OWLClass` structs defined by the client:

```swift
@Persistable
@OWLClass("ex:Person")
struct Person {
    var id: String = UUID().uuidString
    @OWLDataProperty("rdfs:label")
    var name: String = ""
    @OWLDataProperty("ex:email")
    var email: String = ""
}
```

When inserted via `Memory.store(batch)`, OntologyIndex automatically generates RDF triples (`rdf:type`, `rdfs:label`, data properties) — enabling SPARQL queries and spreading activation.

## Modules

| Module | Purpose |
|--------|---------|
| `SwiftMemory` | Core: Memory actor, MemoryBatch, RecallEngine, Given, Statement |
| `MemoryOntology` | OntologyPolicy protocol + DefaultOntologyPolicy (26 primitives) |
