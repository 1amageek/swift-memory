# swift-memory

## Purpose and Scope

`swift-memory` persists Given materials and Statement knowledge for LLM agents.
It owns the application schema, memory API, entity registration, and recall
projection. Each `MemoryLayer` is one Database Framework `Base`.

- Parent: workspace architecture and package boundaries in `../AGENTS.md`.
- Children: `MemoryOntology` and `SwiftMemory` SwiftPM targets.
- This package does not own storage engines, Directory catalogs, or physical
  database-format admission.

## Responsibilities and Boundaries

`SwiftMemory` owns Given, Statement, Trace, Entity, layer selection, provenance
projection, and the store/resolve/recall API. `MemoryDatabaseBootstrap` supplies
the configured domain root and delegates Directory and format admission to
`DBContainer.open`.

The package does not inspect raw storage keys, recreate framework layout rules,
or silently reinterpret an existing store. DatabaseKit owns declarations and
StorageKit/database-framework own Directory and runtime execution semantics.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [database-kit](https://github.com/1amageek/database-kit/tree/26.0831.1) | depends on | Static schema, persistable fields, indexes, security, RDF | Supplies application declaration contracts. | Persisted type, field, index, and graph identities remain stable. |
| [database-framework](https://github.com/1amageek/database-framework/tree/26.0905.0) | depends on | `DBContainer`, `DBConfiguration`, MultiBase topology, Base sessions | Executes the configured schema and Base transactions. | Format admission belongs to the framework; callers propagate typed failures. |
| [storage-kit](https://github.com/1amageek/storage-kit/tree/26.0905.0) | depends on | Directory root existence and incompatible-layout errors | Owns backend Directory catalog semantics. | Raw-key probes in this package are prohibited. |

## Architecture

```text
Memory API
    -> MemoryDatabaseBootstrap
        -> DatabaseStorageTopology(rootPath)
        -> DBContainer.open
            -> StorageKit Directory admission
            -> Database Framework MultiBase runtime
                -> one Base per MemoryLayer
                    -> Given / Statement / Trace / Entity
```

## Contracts and Invariants

- Given and Statement are canonical persisted knowledge; Concept remains an
  external interpretation operation.
- Layer identity, authorization, and provenance are Base boundaries; equal
  entity IDs in different layers remain distinct origins.
- Existing Given, Statement, Trace, Entity, directory, field, index, graph,
  schema-version, and execution-identity encodings are unchanged.
- The configured domain root is passed as `rootPath`; a placement selects its
  storage domain and the framework places each Base at `bases/<Base.ID>` below
  that domain root.
- `DBContainer.open` and StorageKit decide whether a root is initialized,
  compatible, or incompatible. `swift-memory` does not create or reinitialize
  a foreign nonempty root and propagates the typed incompatibility failure.
- MultiBase requires an authenticated principal and all Base grants are
  evaluated by the framework.

## Runtime Flows

```text
configured path
    -> StorageKit openOrInitializeRoot
    -> framework format validation
    -> Base provisioning and grants
    -> layer-scoped context
    -> store / resolve / recall
```

An incompatible or legacy root fails before layer provisioning. No migration
is implicit; export/import is an explicit application operation.

## State, Ownership, and Lifecycle

`Memory` owns the container and layer contexts for its lifetime. The container
owns runtime and storage shutdown. A `MemoryLayerSet` is fixed during one
`Memory` lifetime, and `Memory.shutdown()` must complete before releasing a
path-backed engine or reopening the same file.

## Failure, Concurrency, and Constraints

Database and storage errors remain typed failures. Memory does not map a raw
storage-layout failure to a guessed format or default root. `Memory` is an
actor; synchronous schema and layer values are immutable and `Sendable`.

## Verification and Change Impact

`swift build --build-tests` proves the resolved release graph compiles. The
SwiftMemory behavioral suite proves layer isolation, Base authorization,
SQLite reopen, store/resolve/recall, and legacy or unformatted root rejection.
Changes to topology, database admission, or persisted model declarations
require rechecking this design and the linked dependency contracts.
