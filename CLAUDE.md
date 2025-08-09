# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

swift-memory is a KuzuDB-based task management system designed to be used as Tools by OpenFoundationModels agents. It provides hierarchical task management with dependencies, session tracking, difficulty-based assignment, and ordering capabilities.

## Naming Conventions

### ID Properties
All ID properties should use uppercase "ID" suffix for consistency:
- ✅ `sessionID` (not sessionId)
- ✅ `taskID` (not taskId)  
- ✅ `parentTaskID` (not parentTaskId)
- ✅ `blockerID` (not blockerId)
- ✅ `blockedID` (not blockedId)
- ✅ `fromID` (not fromId)
- ✅ `toID` (not toId)
- ✅ `childID` (not childId)
- ✅ `parentID` (not parentId)

This convention applies to:
- Function parameters
- Property names
- Variable names
- Binding keys in queries
- Tool argument names

## Build and Test Commands

```bash
# Build the package
swift build

# Run tests
swift test

# Run a specific test suite
swift test --filter SessionToolsTests
swift test --filter TaskToolsTests

# Clean build
swift build --clean
```

## Architecture

### Core Components

1. **Graph Database Models** (KuzuDB)
   - **Nodes**:
     - `Session`: Work context with title and timestamp
     - `Task`: Individual task with status, difficulty, assignee, and cancellation tracking
   - **Edges**:
     - `HasTask`: Session → Task with `order` property for task ordering
     - `SubTaskOf`: Child → Parent task relationship (single parent only)
     - `Blocks`: Dependency relationship (blocker → blocked) maintaining DAG

2. **Tool Suite** (OpenFoundationModels.Tool)
   Named with `memory.[domain].[verb]` convention to avoid conflicts:
   - **Session Tools**: `memory.session.create`, `.get`, `.list`, `.update`, `.delete`
   - **Task Tools**: `memory.task.create`, `.get`, `.list`, `.update`, `.reorder`, `.delete`
   - **Dependency Tools**: `memory.dependency.add`, `.remove`

3. **Query Patterns**
   - DAG validation for circular dependency prevention
   - "Ready tasks" filtering (tasks with no incomplete dependencies)
   - Order maintenance within sessions
   - Difficulty-based task matching

### Key Design Decisions

- **Namespace Convention**: All tools prefixed with `memory.` to prevent naming collisions
- **Single Assignee**: Tasks have one assignee (string) for simplicity
- **Order Management**: Tasks ordered within sessions via `HasTask.order`
- **Dependency as DAG**: `Blocks` edges maintain acyclic dependency graph
- **Difficulty Scale**: 1-5 integer scale (1=easy, 5=hard, default=3)

### Database Schema

```swift
// Nodes
@GraphNode Session { id, title, startedAt }
@GraphNode Task { id, title, description?, status, cancelReason?, assignee?, difficulty, createdAt, updatedAt }

// Edges
@GraphEdge(from: Session, to: Task) HasTask { order }
@GraphEdge(from: Task, to: Task) SubTaskOf { }
@GraphEdge(from: Task, to: Task) Blocks { }

// Constraints
- HasTask: (sessionID, order) must be unique
- SubTaskOf: Each task can have at most one parent
- Blocks: Must maintain DAG (no cycles)
```

### KuzuSwift Protocol Definitions

The models conform to the following protocols from KuzuSwift:

```swift
// MARK: - GraphNodeModel Protocol for node operations
public protocol GraphNodeModel: _KuzuGraphModel, Codable {
    static var modelName: String { get }
}

public extension GraphNodeModel {
    static var modelName: String {
        String(describing: Self.self)
    }
}

// MARK: - GraphEdgeModel Protocol for edge operations
public protocol GraphEdgeModel: _KuzuGraphModel, Codable {
    static var edgeName: String { get }
}

public extension GraphEdgeModel {
    static var edgeName: String {
        String(describing: Self.self)
    }
}
```

These protocols provide the foundation for graph database operations in KuzuDB. The `@GraphNode` and `@GraphEdge` macros automatically generate conformance to these protocols.

## Key Queries

```cypher
// Check for circular dependencies
MATCH p = (blocked:Task {id:$blockedID})<-[:Blocks*]-(blocker:Task {id:$blockerID})
RETURN COUNT(p) > 0 AS hasCycle

// Find ready tasks (no incomplete blockers)
MATCH (s:Session {id:$sessionID})-[r:HasTask]->(t:Task)
WHERE t.status IN ['pending','inProgress']
  AND NOT EXISTS {
    MATCH (blocker)-[:Blocks]->(t)
    WHERE blocker.status <> 'done'
  }
RETURN t ORDER BY r.order
```

## Usage Example

```swift
// Create session
memory.session.create { title: "Sprint Planning" }

// Add tasks with dependencies
memory.task.create { sessionID: "S1", title: "Design API", difficulty: 4 }
memory.task.create { sessionID: "S1", title: "Implement API", difficulty: 3 }
memory.dependency.add { blockerID: "T1", blockedID: "T2" }

// Find tasks ready for assignment
memory.task.list { sessionID: "S1", readyOnly: true, difficultyMax: 3 }

// Reorder tasks
memory.task.reorder { sessionID: "S1", orderedIDs: ["T2", "T1"] }
```

## Testing Strategy

- **Unit Tests**: Each tool tested independently with mock data
- **Integration Tests**: Full workflow scenarios including dependencies
- **Edge Cases**: Circular dependency detection, order conflicts, cascade deletes
- **Performance**: Bulk operations and complex graph queries

## Future Extensions

- **Status History**: Add `StatusChanged` edges for audit trail
- **Agent Management**: Upgrade assignee from string to `Agent` nodes
- **Time Tracking**: Add `startedAt`/`completedAt` timestamps
- **Priority/Due Dates**: Additional task properties as needed

## Important Patterns

- Session creation must precede task creation
- Dependency cycles are prevented at creation time
- Task ordering is session-scoped
- Ready task queries automatically filter by dependency status
- Difficulty matching enables skill-based assignment algorithms

## Known Issues

- **kuzu-swift-extension deepwiki**: The deepwiki documentation for kuzu-swift-extension is not available as the API is outdated and cannot be used.