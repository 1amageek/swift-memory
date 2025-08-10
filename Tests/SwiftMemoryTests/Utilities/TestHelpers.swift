import Foundation
import Testing
@testable import SwiftMemory

/// Common test utilities and helper functions
public enum TestHelpers {
    
    // MARK: - Sample Data Creation
    
    /// Create a sample session with default or custom title (using dependency injection)
    public static func createSampleSession(
        using sessionManager: SessionManager,
        title: String = "Test Session"
    ) async throws -> Session {
        return try await sessionManager.create(title: title)
    }
    
    /// Create a sample session with default or custom title (using shared manager)
    public static func createSampleSession(
        title: String = "Test Session"
    ) async throws -> Session {
        return try await SessionManager.shared.create(title: title)
    }
    
    /// Create a sample task with default or custom properties (using dependency injection)
    public static func createSampleTask(
        using taskManager: TaskManager,
        in session: Session,
        title: String = "Test Task",
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        return try await taskManager.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
    }
    
    /// Create a sample task with default or custom properties (using shared manager)
    public static func createSampleTask(
        in session: Session,
        title: String = "Test Task",
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        return try await TaskManager.shared.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
    }
    
    /// Create a task hierarchy (parent → child → grandchild)
    public static func createTaskHierarchy(
        using taskManager: TaskManager,
        in session: Session
    ) async throws -> (parent: Task, child: Task, grandchild: Task) {
        let parent = try await createSampleTask(using: taskManager, in: session, title: "Parent Task")
        
        let child = try await taskManager.create(
            sessionID: session.id,
            title: "Child Task",
            parentTaskID: parent.id
        )
        
        let grandchild = try await taskManager.create(
            sessionID: session.id,
            title: "Grandchild Task",
            parentTaskID: child.id
        )
        
        return (parent, child, grandchild)
    }
    
    /// Create a task hierarchy using shared manager
    public static func createTaskHierarchy(
        in session: Session
    ) async throws -> (parent: Task, child: Task, grandchild: Task) {
        let parent = try await createSampleTask(in: session, title: "Parent Task")
        
        let child = try await TaskManager.shared.create(
            sessionID: session.id,
            title: "Child Task",
            parentTaskID: parent.id
        )
        
        let grandchild = try await TaskManager.shared.create(
            sessionID: session.id,
            title: "Grandchild Task",
            parentTaskID: child.id
        )
        
        return (parent, child, grandchild)
    }
    
    /// Create a dependency chain (first → second → third)
    public static func createDependencyChain(
        using taskManager: TaskManager,
        in session: Session
    ) async throws -> (first: Task, second: Task, third: Task) {
        let first = try await createSampleTask(using: taskManager, in: session, title: "First Task")
        let second = try await createSampleTask(using: taskManager, in: session, title: "Second Task")
        let third = try await createSampleTask(using: taskManager, in: session, title: "Third Task")
        
        try await DependencyManager.shared.add(
            blockerID: first.id,
            blockedID: second.id
        )
        
        try await DependencyManager.shared.add(
            blockerID: second.id,
            blockedID: third.id
        )
        
        return (first, second, third)
    }
    
    /// Create a dependency chain using shared managers
    public static func createDependencyChain(
        in session: Session
    ) async throws -> (first: Task, second: Task, third: Task) {
        let first = try await createSampleTask(in: session, title: "First Task")
        let second = try await createSampleTask(in: session, title: "Second Task")
        let third = try await createSampleTask(in: session, title: "Third Task")
        
        try await DependencyManager.shared.add(
            blockerID: first.id,
            blockedID: second.id
        )
        
        try await DependencyManager.shared.add(
            blockerID: second.id,
            blockedID: third.id
        )
        
        return (first, second, third)
    }
    
    /// Create multiple tasks with various statuses
    public static func createTasksWithStatuses(
        using taskManager: TaskManager,
        in session: Session
    ) async throws -> (pending: Task, inProgress: Task, done: Task, cancelled: Task) {
        let pending = try await createSampleTask(using: taskManager, in: session, title: "Pending Task")
        
        let inProgress = try await createSampleTask(using: taskManager, in: session, title: "In Progress Task")
        _ = try await taskManager.update(
            id: inProgress.id,
            status: .inProgress
        )
        
        let done = try await createSampleTask(using: taskManager, in: session, title: "Done Task")
        _ = try await taskManager.update(
            id: done.id,
            status: .done
        )
        
        let cancelled = try await createSampleTask(using: taskManager, in: session, title: "Cancelled Task")
        _ = try await taskManager.update(
            id: cancelled.id,
            status: .cancelled,
            cancelReason: "Test cancellation"
        )
        
        return (pending, inProgress, done, cancelled)
    }
    
    /// Create multiple tasks with various statuses using shared manager
    public static func createTasksWithStatuses(
        in session: Session
    ) async throws -> (pending: Task, inProgress: Task, done: Task, cancelled: Task) {
        let pending = try await createSampleTask(in: session, title: "Pending Task")
        
        let inProgress = try await createSampleTask(in: session, title: "In Progress Task")
        _ = try await TaskManager.shared.update(
            id: inProgress.id,
            status: .inProgress
        )
        
        let done = try await createSampleTask(in: session, title: "Done Task")
        _ = try await TaskManager.shared.update(
            id: done.id,
            status: .done
        )
        
        let cancelled = try await createSampleTask(in: session, title: "Cancelled Task")
        _ = try await TaskManager.shared.update(
            id: cancelled.id,
            status: .cancelled,
            cancelReason: "Test cancellation"
        )
        
        return (pending, inProgress, done, cancelled)
    }
    
    /// Create tasks with different difficulties
    public static func createTasksWithDifficulties(
        using taskManager: TaskManager,
        in session: Session
    ) async throws -> [Task] {
        var tasks: [Task] = []
        
        for difficulty in 1...5 {
            let task = try await createSampleTask(
                using: taskManager,
                in: session,
                title: "Difficulty \(difficulty) Task",
                difficulty: difficulty
            )
            tasks.append(task)
        }
        
        return tasks
    }
    
    /// Create tasks with different difficulties using shared manager
    public static func createTasksWithDifficulties(
        in session: Session
    ) async throws -> [Task] {
        var tasks: [Task] = []
        
        for difficulty in 1...5 {
            let task = try await createSampleTask(
                in: session,
                title: "Difficulty \(difficulty) Task",
                difficulty: difficulty
            )
            tasks.append(task)
        }
        
        return tasks
    }
    
    // MARK: - Assertions
    
    /// Assert that two tasks are equal (comparing relevant properties)
    public static func assertTasksEqual(
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
    public static func assertContainsTask(
        _ tasks: [Task],
        withID taskID: UUID
    ) {
        #expect(
            tasks.contains { $0.id == taskID },
            "Tasks array should contain task with ID \(taskID)"
        )
    }
    
    /// Assert that a task array does not contain a specific task
    public static func assertDoesNotContainTask(
        _ tasks: [Task],
        withID taskID: UUID
    ) {
        #expect(
            !tasks.contains { $0.id == taskID },
            "Tasks array should not contain task with ID \(taskID)"
        )
    }
    
    // MARK: - Error Testing
    
    /// Test that an async expression throws a specific MemoryError
    public static func expectMemoryError<T>(
        _ expectedError: MemoryError,
        when expression: () async throws -> T
    ) async {
        do {
            _ = try await expression()
            Issue.record("Expected \(expectedError) to be thrown, but no error was thrown")
        } catch let error as MemoryError {
            // Compare error cases without associated values for simplicity
            let actualErrorName = String(describing: error).components(separatedBy: "(").first ?? ""
            let expectedErrorName = String(describing: expectedError).components(separatedBy: "(").first ?? ""
            
            #expect(
                actualErrorName == expectedErrorName,
                "Expected \(expectedError) but got \(error)"
            )
        } catch {
            Issue.record("Expected MemoryError.\(expectedError) but got \(error)")
        }
    }
}

// MARK: - Test Data Builder

/// Builder pattern for creating test tasks with custom properties
public struct TaskBuilder {
    public var title = "Test Task"
    public var description: String? = nil
    public var difficulty = 3
    public var status = TaskStatus.pending
    public var assignee: String? = nil
    public var parentTaskID: UUID? = nil
    
    public init() {}
    
    public func with(title: String) -> TaskBuilder {
        var builder = self
        builder.title = title
        return builder
    }
    
    public func with(description: String) -> TaskBuilder {
        var builder = self
        builder.description = description
        return builder
    }
    
    public func with(difficulty: Int) -> TaskBuilder {
        var builder = self
        builder.difficulty = difficulty
        return builder
    }
    
    public func with(status: TaskStatus) -> TaskBuilder {
        var builder = self
        builder.status = status
        return builder
    }
    
    public func with(assignee: String) -> TaskBuilder {
        var builder = self
        builder.assignee = assignee
        return builder
    }
    
    public func with(parentTaskID: UUID) -> TaskBuilder {
        var builder = self
        builder.parentTaskID = parentTaskID
        return builder
    }
    
    public func build(
        using taskManager: TaskManager,
        in session: Session
    ) async throws -> Task {
        let task = try await taskManager.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
        
        // Update status if needed
        if status != .pending {
            return try await taskManager.update(
                id: task.id,
                status: status,
                cancelReason: status == .cancelled ? "Test cancellation" : nil
            )
        }
        
        return task
    }
    
    /// Build task using shared manager
    public func build(in session: Session) async throws -> Task {
        let task = try await TaskManager.shared.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
        
        // Update status if needed
        if status != .pending {
            return try await TaskManager.shared.update(
                id: task.id,
                status: status,
                cancelReason: status == .cancelled ? "Test cancellation" : nil
            )
        }
        
        return task
    }
}

// MARK: - Test Fixtures

public enum TestFixtures {
    public static let sampleSessionTitles = [
        "Sprint Planning",
        "Q1 Goals",
        "Feature Development",
        "Bug Fixes",
        "Testing Phase"
    ]
    
    public static let sampleTaskTitles = [
        "Design UI",
        "Implement Backend",
        "Write Tests",
        "Code Review",
        "Deploy to Production"
    ]
    
    public static let sampleAssignees = [
        "Alice",
        "Bob",
        "Charlie",
        "Diana",
        "Eve"
    ]
    
    public static let sampleDescriptions = [
        "Create mockups and wireframes",
        "Set up database schema",
        "Write unit and integration tests",
        "Review pull request",
        "Deploy to AWS"
    ]
}