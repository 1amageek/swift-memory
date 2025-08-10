# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Design Philosophy

swift-memory is designed as an LLM tool library with four core principles:

### 1. LLM Tool-First Design
- **Purpose**: Enable LLM agents to manage hierarchical TODO lists with clear dependencies
- **Simplicity**: Each tool performs one clear operation (create, get, list, update, delete, reorder)
- **Namespace Safety**: All tools prefixed with `memory.` to prevent naming conflicts with other agent tools

### 2. Concurrent Multi-Agent Safety
- **Thread-Safe Operations**: All managers use Swift actors for safe concurrent access
- **Session Isolation**: Multiple LLM agents can work in separate sessions simultaneously
- **Dependency Integrity**: DAG constraints prevent circular dependencies across all agents

### 3. Radical Simplicity
- **Clear Mental Model**: Sessions contain ordered tasks, tasks can depend on other tasks
- **Minimal Concepts**: Only 3 node types (Session, Task) and 3 relationship types (HasTask, SubTaskOf, Blocks)
- **Intuitive Status**: Tasks are `pending`, `inProgress`, `done`, or `cancelled`

### 4. Dependency Transparency
- **Ready Tasks**: Automatically filter tasks with no incomplete dependencies
- **Blocking Relationships**: Clear visibility of what prevents task execution
- **Hierarchical Structure**: Parent-child relationships for task breakdown

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

### Data Model
- **Session**: Work context with title and timestamp
- **Task**: Individual task with status, difficulty, assignee, and optional description
- **HasTask**: Session contains ordered tasks
- **SubTaskOf**: Parent-child task relationships (single parent only)
- **Blocks**: Dependency relationships maintaining DAG (no cycles)

### Tool Suite
All tools follow `memory.[domain].[verb]` naming:
- **Session**: create, get, list, update, delete
- **Task**: create, get, list, update, reorder, delete
- **Dependency**: add, remove

### Key Constraints
- Tasks ordered within sessions via `HasTask.order`
- Dependency graph must remain acyclic (DAG)
- Tasks cannot be their own parent (self-loop prevention)
- Dependencies cannot create cycles (automatic detection)
- Difficulty scale: 1-5 (1=easy, 5=hard, default=3)
- Single assignee per task (string)
- Cascade deletion uses [:SubTaskOf*1..] pattern to exclude self

## LLM Agent Usage Patterns

### Basic Workflow
1. Create session for work context
2. Add tasks with descriptions and difficulty levels
3. Set dependencies between tasks
4. Query ready tasks (no incomplete dependencies)
5. Update task status as work progresses

### Multi-Agent Considerations
- Each LLM agent should work in separate sessions
- Use difficulty filtering to match tasks to agent capabilities
- Ready task queries automatically handle dependency management
- Session isolation prevents agents from interfering with each other

### Example Usage
```swift
// Create work session
memory.session.create { title: "API Development" }

// Add tasks with dependencies  
memory.task.create { sessionID: "S1", title: "Design API", difficulty: 4 }
memory.task.create { sessionID: "S1", title: "Implement API", difficulty: 3 }
memory.dependency.add { blockerID: "T1", blockedID: "T2" }

// Find ready tasks for difficulty level 3 or below
memory.task.list { sessionID: "S1", readyOnly: true, difficultyMax: 3 }
```

## Data Integrity Safeguards

### Self-Loop Prevention
- **TaskManager**: Tasks cannot be their own parent
- **DependencyManager**: Tasks cannot block themselves
- Both managers check for self-loops before any database operations
- Error: `MemoryError.invalidInput` with descriptive reason

### Cycle Detection
- Parent-child relationships (SubTaskOf) prevent cycles
- Dependency relationships (Blocks) maintain DAG property
- Uses path queries to detect potential cycles before creating relationships
- Error: `MemoryError.circularDependency` with involved task IDs

### Transaction Atomicity
- `TaskManager.create()` wraps all operations in a transaction
- `DependencyManager.add()` ensures atomic validation and creation
- Automatic rollback on any failure during compound operations

## Performance Optimizations

### Batch Validation
- Task reordering uses single UNWIND query instead of N individual queries
- Example: Validating 100 tasks reduced from 100 queries to 1 query
- Pattern: `UNWIND $taskIDs AS taskID ... RETURN collect(t.id)`

### Query Optimization Patterns
- Use MERGE instead of CREATE for idempotent edge creation
- Batch operations with UNWIND for multiple updates
- Indexed lookups on UUID fields for O(1) access

## Thread Safety & Concurrency

### DateFormatter Thread Safety
- All shared DateFormatter instances protected with NSLock
- Thread-safe access methods: `formatDisplay()`, `parseDisplay()`
- ISO8601 and RelativeDateTimeFormatter are inherently thread-safe

### KuzuDB Transaction Limitations
- **Important**: KuzuDB does not support concurrent transactions on the same connection
- Concurrent read operations are safe
- Write operations should be executed sequentially
- For concurrent writes, use separate database connections

### Actor-Based Concurrency
- All managers (SessionManager, TaskManager, DependencyManager) are Swift actors
- Ensures thread-safe access to manager methods
- Database operations are serialized at the actor level

## Testing Guidelines

### TestContext Pattern
```swift
// Use withTestContext for automatic cleanup
try await withTestContext(testName: #function) { context in
    // Test code here
    let session = try await context.sessionManager.create(title: "Test")
    // Context automatically cleaned up after block
}
```

### Test Helpers
- `expectMemoryError(code:when:)` - Validate specific error codes
- `assertTasksEqual()` - Compare tasks with tolerance for timestamps
- `withTestContext()` - Ensure proper async cleanup
- Isolated database per test for true isolation

### Concurrent Test Considerations
- Test concurrent reads, not concurrent writes
- Use sequential operations for write-heavy tests
- TaskGroup for testing concurrent read patterns