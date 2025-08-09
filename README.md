# swift-memory

A KuzuDB-based hierarchical task management system for AI agents, built with Swift and designed for use with OpenFoundationModels.

## Features

- **Hierarchical Task Management**: Support for parent-child task relationships with cycle detection
- **Dependency Tracking**: DAG-based task dependencies with automatic cycle prevention
- **Session-based Organization**: Group tasks into work sessions with ordering
- **Difficulty-based Assignment**: 5-level difficulty system with intuitive enum values
- **Status Management**: Track task lifecycle (pending → inProgress → done/cancelled)
- **Type-safe Tool Interface**: OpenFoundationModels-compatible tools for AI agent integration
- **Batch Operations**: Update multiple tasks efficiently in a single operation
- **Flexible Information Retrieval**: Get exactly the task information you need with include options
- **Enhanced Error Handling**: Detailed error codes with recovery suggestions

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
- **Task**: Individual task with status, difficulty (1-5), assignee, and cancellation tracking
- **Edges**: HasTask (with order), SubTaskOf (single parent), Blocks (DAG constraint)

### Key Enumerations

```swift
// Task difficulty levels
public enum TaskDifficulty: String {
    case trivial = "trivial"  // 1
    case easy = "easy"        // 2
    case medium = "medium"    // 3
    case hard = "hard"        // 4
    case expert = "expert"    // 5
}

// Task status
public enum TaskStatus: String {
    case pending = "pending"
    case inProgress = "inProgress"
    case done = "done"
    case cancelled = "cancelled"
}
```

## Usage

### Basic Task Management

```swift
import SwiftMemory

// Initialize the database
try await GraphDatabaseSetup.shared.context()

// Create a session
let session = try await SessionManager.shared.create(title: "Sprint Planning")

// Add tasks
let designTask = try await TaskManager.shared.create(
    sessionID: session.id,
    title: "Design API",
    difficulty: 4  // hard
)

let implementTask = try await TaskManager.shared.create(
    sessionID: session.id,
    title: "Implement API",
    difficulty: 3  // medium
)

// Add dependency using the new unified tool
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

// Batch update multiple tasks
let updatedTasks = try await TaskManager.shared.updateBatch(
    taskIDs: [task1.id, task2.id, task3.id],
    status: .done,
    assignee: "AI Agent"
)
```

### Tool Integration (OpenFoundationModels)

```swift
import OpenFoundationModels
import SwiftMemory

// All available tools (13 total, simplified from 15)
let tools = memoryTools  // Pre-configured collection

// Or specify individually:
let tools = [
    // Session management (5)
    SessionCreateTool(),
    SessionGetTool(),
    SessionListTool(),
    SessionUpdateTool(),
    SessionDeleteTool(),
    
    // Task management (6)
    TaskCreateTool(),
    TaskGetTool(),       // Enhanced with include options
    TaskListTool(),
    TaskUpdateTool(),    // Enhanced with batch support
    TaskReorderTool(),
    TaskDeleteTool(),
    
    // Dependency management (2)
    DependencySetTool(),  // Unified add/remove
    DependencyGetTool()   // Unified queries
]

// Use with AI agent
let agent = Agent(tools: tools)
```

### Advanced Queries

```swift
// Get task with selective information using include options
let fullInfo = try await TaskManager.shared.getWithIncludes(
    taskID: task.id,
    include: TaskIncludeOptions(
        parent: true,
        children: true,
        dependencies: true,
        fullChain: true,
        session: true
    )
)

// Find ready tasks (no incomplete blockers)
let readyTasks = try await TaskManager.shared.list(
    sessionID: session.id,
    readyOnly: true,
    difficultyMax: 3
)

// Get dependency chain
let chain = try await DependencyManager.shared.getDependencyChain(
    taskID: task.id
)
// Returns: upstream and downstream dependencies with depth
```

## Tool Reference

### Session Tools

- `memory.session.create`: Create new work session
- `memory.session.get`: Retrieve session by ID
- `memory.session.list`: List sessions with date filtering
- `memory.session.update`: Update session title
- `memory.session.delete`: Delete session (with optional cascade)

### Task Tools

- `memory.task.create`: Create task with optional parent
- `memory.task.get`: Get task with flexible include options
  ```swift
  // Include options:
  {
    include: {
      parent: true,      // Include parent task
      children: true,    // Include child tasks
      dependencies: true,// Include direct blockers/blocking
      fullChain: true,   // Include full dependency chain
      session: true      // Include session information
    }
  }
  ```
- `memory.task.list`: List tasks with filtering (status, assignee, ready-only)
- `memory.task.update`: Update task properties with batch support
  ```swift
  // Single task update
  { taskID: "uuid", update: { status: "done" } }
  
  // Batch update
  { taskIDs: ["uuid1", "uuid2"], update: { status: "done" } }
  ```
- `memory.task.reorder`: Reorder tasks within session
- `memory.task.delete`: Delete task (with optional cascade)

### Dependency Tools (Simplified from 4 to 2)

- `memory.dependency.set`: Unified add/remove dependencies
  ```swift
  {
    action: "add" | "remove",
    blockerID: "uuid",
    blockedID: "uuid"
  }
  ```
- `memory.dependency.get`: Unified dependency queries
  ```swift
  {
    taskID: "uuid",
    type: "chain" | "blockers" | "blocking" | "isBlocked"
  }
  ```

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

### Batch Operations

Update multiple tasks efficiently:

```swift
// Update multiple tasks at once
let results = try await TaskManager.shared.updateBatch(
    taskIDs: [task1.id, task2.id, task3.id],
    status: .done,
    difficulty: 2  // easy
)
```

## Error Handling

### Enhanced Error System

```swift
public enum MemoryError: LocalizedError {
    case sessionNotFound(UUID)
    case taskNotFound(UUID)
    case invalidDifficulty(Int)  // Must be 1-5
    case circularDependency(blocker: UUID, blocked: UUID)
    case duplicateParent(taskID: UUID)
    case invalidInput(field: String, reason: String)
    case databaseError(String)
}

// Each error provides:
// - Error code (e.g., "TASK_NOT_FOUND")
// - Descriptive message
// - Recovery suggestion
// - Context information

// Example error response:
MemoryError.taskNotFound(id) 
// Returns:
// - Message: "Task not found: <id>"
// - Suggestion: "Check the task ID or use memory.task.list to find available tasks"
// - Code: "TASK_NOT_FOUND"
```

### Error Mapping

All tools provide helpful error messages with recovery suggestions:

```swift
// Tool error responses include recovery suggestions
"Task not found: 123. Check the task ID or use memory.task.list to find available tasks"
```

## API Improvements

### Simplified from 15 to 13 Tools

The API has been streamlined by consolidating related operations:
- **Dependency tools**: 4 → 2 (unified set/get operations)
- **Task tools**: Enhanced with batch and include options
- **Consistent naming**: All tools follow `memory.[domain].[verb]` pattern

### Key Enhancements

1. **Flexible Information Retrieval**: Get exactly what you need with `TaskIncludeOptions`
2. **Batch Operations**: Update multiple tasks in one call
3. **Better Error Messages**: Detailed errors with recovery suggestions
4. **Type Safety**: Enums for difficulty and status prevent invalid values
5. **Unified Operations**: Fewer tools with more capabilities

## Requirements

- Swift 6.0+
- macOS 15.0+ / iOS 18.0+
- KuzuDB (via kuzu-swift-extension)

## Dependencies

- [kuzu-swift-extension](https://github.com/1amageek/kuzu-swift-extension): KuzuDB Swift bindings with macros
- [OpenFoundationModels](https://github.com/1amageek/OpenFoundationModels): AI agent tool framework

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.