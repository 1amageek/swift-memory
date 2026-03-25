# swift-memory

Knowledge persistence and associative recall for LLM agents.

## Design Philosophy

Memory stores and recalls knowledge. It does **not** interpret raw input.

Interpretation is the responsibility of an **external agent**:

1. A nested agent (e.g. haiku) analyzes conversation and structures knowledge
2. The agent calls `Memory.store(batch)` with entities and relationships
3. Memory persists them and enables recall via spreading activation

This separation ensures:

- **Clean context** — Memory holds no LLM prompts or interpretation logic
- **Cost optimization** — The interpreting agent can use a cheaper model
- **Flexible deployment** — Interpretation logic lives in a Skill, not in code

```
Parent Agent (conversation with user)
  │
  ├─→ Nested Agent (haiku, cost-efficient)
  │     Analyzes conversation
  │     Structures entities + relationships
  │     Calls store() via MCP tool
  │
  └─→ recall() via MCP tool
       Spreading activation on knowledge graph
       Returns entities scored by convergence
```

## API

```swift
let memory = try await Memory(
    path: "memory.sqlite",
    entityTypes: [Person.self, Organization.self]
)

// Store — called by the interpreting agent
var batch = MemoryBatch()
batch.entity(person)            // @OWLClass Persistable
batch.triple(s, p, o)           // Explicit relationship
try await memory.store(batch)

// Recall — spreading activation from keywords
let result = try await memory.recall(keywords: ["Alice", "auth"])
for entity in result.entities {
    print("\(entity.label) (\(entity.type), score: \(entity.score))")
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `SwiftMemory` | Core: Memory actor, MemoryBatch, RecallEngine, Given, Statement |
| `MemoryOntology` | OntologyPolicy protocol + DefaultOntologyPolicy (26 primitives) |

## Recall: Spreading Activation

Given keywords (cues), the recall algorithm:

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
