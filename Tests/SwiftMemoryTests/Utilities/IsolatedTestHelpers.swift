import Foundation
import Testing
@testable import SwiftMemory

/// Isolated test helpers that work exclusively with TestContext
/// This ensures complete test isolation and prevents database conflicts
public struct IsolatedTestHelpers {
    private let context: TestContext
    
    public init(_ context: TestContext) {
        self.context = context
    }
    
    // MARK: - Session Helpers
    
    /// Create a sample session with default or custom title
    public func createSampleSession(
        title: String = "Test Session"
    ) async throws -> Session {
        return try await context.createSession(title: title)
    }
    
    // MARK: - Task Helpers
    
    /// Create a sample task with default or custom properties
    public func createSampleTask(
        in session: Session,
        title: String = "Test Task",
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        return try await context.createTask(
            in: session,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
    }
    
    /// Create a task hierarchy (parent → child → grandchild)
    public func createTaskHierarchy(
        in session: Session
    ) async throws -> (parent: Task, child: Task, grandchild: Task) {
        return try await context.createTaskHierarchy(in: session)
    }
    
    /// Create a dependency chain (first → second → third)
    public func createDependencyChain(
        in session: Session
    ) async throws -> (first: Task, second: Task, third: Task) {
        return try await context.createDependencyChain(in: session)
    }
    
    /// Create multiple tasks with various statuses
    public func createTasksWithStatuses(
        in session: Session
    ) async throws -> (pending: Task, inProgress: Task, done: Task, cancelled: Task) {
        return try await context.createTasksWithStatuses(in: session)
    }
    
    /// Create tasks with different difficulties
    public func createTasksWithDifficulties(
        in session: Session
    ) async throws -> [Task] {
        return try await context.createTasksWithDifficulties(in: session)
    }
    
    // MARK: - Assertions
    
    /// Assert that two tasks are equal (comparing relevant properties)
    public func assertTasksEqual(
        _ actual: Task,
        _ expected: Task
    ) {
        #expect(actual.id == expected.id)
        #expect(actual.title == expected.title)
        #expect(actual.status == expected.status)
        #expect(actual.difficulty == expected.difficulty)
        #expect(actual.assignee == expected.assignee)
    }
    
    /// Assert that a task array contains a specific task
    public func assertContainsTask(
        _ tasks: [Task],
        withID taskID: UUID
    ) {
        #expect(
            tasks.contains { $0.id == taskID },
            "Tasks array should contain task with ID \(taskID)"
        )
    }
    
    /// Assert that a task array does not contain a specific task
    public func assertDoesNotContainTask(
        _ tasks: [Task],
        withID taskID: UUID
    ) {
        #expect(
            !tasks.contains { $0.id == taskID },
            "Tasks array should not contain task with ID \(taskID)"
        )
    }
    
    // MARK: - Error Testing
    
    /// Test that an async expression throws a MemoryError with specific code
    public func expectMemoryError(
        code expectedCode: MemoryErrorCode,
        when expression: () async throws -> Void
    ) async {
        do {
            try await expression()
            Issue.record("Expected MemoryError with code \(expectedCode) to be thrown, but no error was thrown")
        } catch let error as MemoryError {
            #expect(
                error.code == expectedCode,
                "Expected error code \(expectedCode) but got \(error.code)"
            )
        } catch {
            Issue.record("Expected MemoryError with code \(expectedCode) but got \(error)")
        }
    }
    
    /// Legacy method for backward compatibility - prefer code-based version
    public func expectMemoryError<T>(
        _ expectedError: MemoryError,
        when expression: () async throws -> T
    ) async {
        await expectMemoryError(code: expectedError.code) {
            _ = try await expression()
        }
    }
}

// MARK: - Builder Pattern Support

/// Builder pattern for creating test tasks with custom properties using isolated context
public struct IsolatedTaskBuilder {
    public var title = "Test Task"
    public var description: String? = nil
    public var difficulty = 3
    public var status = TaskStatus.pending
    public var assignee: String? = nil
    public var parentTaskID: UUID? = nil
    
    private let context: TestContext
    
    public init(context: TestContext) {
        self.context = context
    }
    
    public func with(title: String) -> IsolatedTaskBuilder {
        var builder = self
        builder.title = title
        return builder
    }
    
    public func with(description: String) -> IsolatedTaskBuilder {
        var builder = self
        builder.description = description
        return builder
    }
    
    public func with(difficulty: Int) -> IsolatedTaskBuilder {
        var builder = self
        builder.difficulty = difficulty
        return builder
    }
    
    public func with(status: TaskStatus) -> IsolatedTaskBuilder {
        var builder = self
        builder.status = status
        return builder
    }
    
    public func with(assignee: String) -> IsolatedTaskBuilder {
        var builder = self
        builder.assignee = assignee
        return builder
    }
    
    public func with(parentTaskID: UUID) -> IsolatedTaskBuilder {
        var builder = self
        builder.parentTaskID = parentTaskID
        return builder
    }
    
    public func build(in session: Session) async throws -> Task {
        let task = try await context.taskManager.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
        
        // Update status if needed
        if status != .pending {
            return try await context.taskManager.update(
                id: task.id,
                status: status,
                cancelReason: status == .cancelled ? "Test cancellation" : nil
            )
        }
        
        return task
    }
}

// MARK: - TestContext Extensions

extension TestContext {
    /// Get isolated test helpers for this context
    public var helpers: IsolatedTestHelpers {
        return IsolatedTestHelpers(self)
    }
    
    /// Create a task builder for this context
    public func taskBuilder() -> IsolatedTaskBuilder {
        return IsolatedTaskBuilder(context: self)
    }
}