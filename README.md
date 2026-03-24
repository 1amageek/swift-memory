# swift-memory

A place that holds both what is given and the knowledge born from it.
Not a store of knowledge, but the whole system embracing raw material and structure alike.

## The Four Concepts

```
                    ┌─────────────────┐
                    │     Concept     │  ← Appears when used, vanishes when done
                    └────┬───────┬────┘
          Interpretation │       │ Produces relations
                         ↓       ↓
          ┌──────────────┐         ┌──────────────┐
          │    Given     │         │  Knowledge   │
          │              │ ──────▶ │              │
          │              │ ◀────── │              │
          └──────────────┘         └──────────────┘
            Materials bind →
            ← Knowledge guides recall

          └──────────────────────────────────────┘
                         Memory
              Holds Given and Knowledge together
```

**Given** — Raw material not yet determined as anything. The redness before it becomes "apple" or "danger." Light, sound, texture, color, scent.

**Knowledge** — Not isolated fragments but relationships. "A is related to B." Cherry blossoms are beautiful in relation to spring, to flowers, to transience. Knowledge exists as a web of relations.

**Concept** — Not fixed in a dictionary. The concept of "flower" takes a slightly different form when seeing cherry blossoms, reading poetry, or thinking about butterflies. Concepts are operational units reconstructed each time in context. They are not stored.

**Memory** — The place that holds both the uninterpreted materials and the structured relations born from them. When we remember an event, we carry not just its meaning but also the quality of light and the texture of voice. Memory embraces the whole.

## Design Principles

- Memory stores **Given** and **Knowledge**. It does not store Concepts.
- `store(input)` does not save raw input. Input passes through the **Concept Protocol** (`MemoryEncoding`), which is implemented by the client.
- `recall(query)` uses **spreading activation** — keywords match entity labels, activation spreads bidirectionally through the knowledge graph, and entities reached by multiple paths score higher.
- `Statement` is the atomic unit of knowledge (subject-predicate-object). A collection of statements constitutes knowledge.
- Grounding is not a separate layer — it is a kind of knowledge expressed as statements.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-memory.git", branch: "main"),
]
```

```swift
.target(
    dependencies: [
        .product(name: "SwiftMemory", package: "swift-memory"),
    ]
)
```

## Usage

### Store

Types conform to `MemoryEncodable` to define how they decompose into Given and Knowledge:

```swift
import SwiftMemory

struct ChatMessage: MemoryEncodable {
    var text: String
    var sender: String

    func encode(to encoding: some MemoryEncoding) async throws {
        let givens = encoding.givenContainer()
        givens.encode(text, source: "chat")

        let knowledge = encoding.knowledgeContainer()
        knowledge.encode(
            subject: "ex:\(sender)",
            predicate: "ex:said",
            object: text
        )
    }
}
```

The client provides a `MemoryEncoding` implementation (the Concept Protocol):

```swift
struct MyEncoder: MemoryEncoding {
    let givens = GivenEncodingContainer()
    let knowledge = KnowledgeEncodingContainer()

    func givenContainer() -> GivenEncodingContainer { givens }
    func knowledgeContainer() -> KnowledgeEncodingContainer { knowledge }
}
```

Store through Memory:

```swift
let memory = Memory(context: context, encoding: MyEncoder())
try await memory.store(ChatMessage(text: "The cherry blossoms are beautiful", sender: "Alice"))
```

### Recall

Spreading activation from keywords — entities reached by multiple paths score higher:

```swift
let result = try await memory.recall(RecallQuery(keywords: ["Alice", "cherry blossoms"]))

for entity in result.entities {
    print("\(entity.label) (score: \(entity.score))")
    for path in entity.paths {
        print("  via: \(path)")
    }
}
```

Vector similarity search on Given embeddings:

```swift
let result = try await memory.recall(RecallQuery(embedding: queryVector))
for given in result.givens {
    print("\(given.payloadRef) [\(given.modality)]")
}
```

## Architecture

```
User / App
    │
    ▼
Memory.store(input)
    │
    ▼
input.encode(to: encoding)     ← MemoryEncodable: type knows its decomposition
    ├─→ GivenEncodingContainer   → Given Store (SQLite + VectorIndex)
    └─→ KnowledgeEncodingContainer → Knowledge Store (SQLite + GraphIndex)

Memory.recall(query)
    │
    ▼
RecallEngine
    ├─ keywords → Spreading Activation (label match → bidirectional traversal → convergence scoring)
    └─ embedding → Vector Similarity Search (cosine distance on Given.embedding)
    │
    ▼
RecallResult(entities: [RecalledEntity], givens: [Given])
```

## Requirements

- Swift 6.2+
- macOS 26+

## License

MIT
