# swift-memory

A KuzuDB-based hierarchical task management system for AI agents, built with Swift and designed for use with OpenFoundationModels.

## Features

- **Hierarchical Task Management**: Support for parent-child task relationships with cycle detection
- **Dependency Tracking**: DAG-based task dependencies with automatic cycle prevention
- **Session-based Organization**: Group tasks into work sessions with ordering
- **Difficulty-based Assignment**: 5-level difficulty system for skill-based task matching
- **Status Management**: Track task lifecycle (pending → inProgress → done/cancelled)
- **Type-safe Tool Interface**: OpenFoundationModels-compatible tools for AI agent integration

## Installation

Add swift-memory to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-memory.git", from: "1.0.0")
]
```

## Architecture

### Graph Schema

```
Session -[HasTask]-> Task
Task -[SubTaskOf]-> Task (parent)
Task -[Blocks]-> Task (dependency)
```

### Core Models

- **Session**: Work context with title and timestamp
- **Task**: Individual task with status, difficulty, assignee, and cancellation tracking
- **Edges**: HasTask (with order), SubTaskOf (single parent), Blocks (DAG constraint)

## Usage

### Basic Task Management

```swift
import SwiftMemory

// Initialize the database
try await GraphDatabaseSetup.shared.setup(at: "path/to/database")

// Create a session
let session = try await SessionManager.shared.create(title: "Sprint Planning")

// Add tasks
let designTask = try await TaskManager.shared.create(
    sessionID: session.id,
    title: "Design API",
    difficulty: 4
)

let implementTask = try await TaskManager.shared.create(
    sessionID: session.id,
    title: "Implement API",
    difficulty: 3
)

// Add dependency
try await DependencyManager.shared.add(
    blockerID: designTask.id,
    blockedID: implementTask.id
)

// Check if task is blocked
let isBlocked = try await DependencyManager.shared.isTaskBlocked(
    taskID: implementTask.id
)

// Update task status
let updated = try await TaskManager.shared.update(
    id: designTask.id,
    status: .done
)
```

### Tool Integration (OpenFoundationModels)

```swift
import OpenFoundationModels

// Available tools
let tools = [
    // Session management
    SessionCreateTool(),
    SessionListTool(),
    SessionUpdateTool(),
    SessionDeleteTool(),
    
    // Task management
    TaskCreateTool(),
    TaskListTool(),
    TaskUpdateTool(),
    TaskReorderTool(),
    TaskDeleteTool(),
    
    // Dependency management
    DependencyAddTool(),
    DependencyRemoveTool()
]

// Use with AI agent
let agent = Agent(tools: tools)
```

### Advanced Queries

```swift
// Find ready tasks (no incomplete blockers)
let readyTasks = try await TaskManager.shared.list(
    sessionID: session.id,
    readyOnly: true,
    difficultyMax: 3
)

// Get task hierarchy
let taskInfo = try await TaskManager.shared.getTaskInfo(taskID: task.id)
// Returns: task, parent, children, blockers, blocking

// Get dependency chain
let chain = try await DependencyManager.shared.getDependencyChain(
    taskID: task.id
)
// Returns: upstream and downstream dependencies with depth
```

## Tool Reference

### Session Tools

- `memory.session.create`: Create new work session
- `memory.session.list`: List sessions with date filtering
- `memory.session.update`: Update session title
- `memory.session.delete`: Delete session (with optional cascade)

### Task Tools

- `memory.task.create`: Create task with optional parent
- `memory.task.list`: List tasks with filtering (status, assignee, ready-only)
- `memory.task.update`: Update task properties and status
- `memory.task.reorder`: Reorder tasks within session
- `memory.task.delete`: Delete task (with optional cascade)

### Dependency Tools

- `memory.dependency.add`: Create blocker → blocked relationship
- `memory.dependency.remove`: Remove dependency

## Key Features

### Cycle Detection

Both task dependencies (Blocks) and hierarchies (SubTaskOf) automatically detect and prevent cycles:

```swift
// This will throw MemoryError.circularDependency
try await DependencyManager.shared.add(blockerID: taskB.id, blockedID: taskA.id)
// if taskA already blocks taskB
```

### Task Readiness

Tasks are "ready" when:
- Status is pending or inProgress
- No active blockers (pending/inProgress dependencies)

### Cascade Operations

Delete operations support cascading:

```swift
// Delete session and all its tasks
try await SessionManager.shared.delete(id: sessionID, cascade: true)

// Delete task and all subtasks
try await TaskManager.shared.delete(id: taskID, cascade: true)
```

## Error Handling

```swift
public enum MemoryError: LocalizedError {
    case databaseNotInitialized
    case sessionNotFound(UUID)
    case taskNotFound(UUID)
    case invalidDifficulty(Int)  // Must be 1-5
    case circularDependency(blocker: UUID, blocked: UUID)
    case duplicateParent(child: UUID, existingParent: UUID)
    case databaseError(String)
}
```

## Requirements

- Swift 5.9+
- macOS 13.0+ / iOS 16.0+ / Linux
- KuzuDB (via kuzu-swift)

## Dependencies

- [kuzu-swift](https://github.com/kuzudb/kuzu-swift): KuzuDB Swift bindings
- [kuzu-swift-extension](https://github.com/1amageek/kuzu-swift-extension): Query DSL and utilities
- [OpenFoundationModels](https://github.com/1amageek/OpenFoundationModels): AI agent tool framework

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.