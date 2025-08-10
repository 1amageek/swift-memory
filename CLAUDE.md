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
- Dependency graph must remain acyclic
- Difficulty scale: 1-5 (1=easy, 5=hard, default=3)
- Single assignee per task (string)

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