import Foundation
import Testing
@testable import SwiftMemory

/// Test context specific errors
public enum TestContextError: LocalizedError {
    case notInitialized(String)
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized(let testName):
            return "TestContext for '\(testName)' is not initialized. Call initialize() first."
        }
    }
}

/// Enhanced test context that provides completely isolated managers for testing
/// Ensures proper resource management and cleanup to prevent database conflicts
public final class TestContext: @unchecked Sendable {
    public let sessionManager: SessionManager
    public let taskManager: TaskManager
    public let dependencyManager: DependencyManager
    
    private let provider: TestDatabaseProvider
    private let testName: String
    private var isInitialized = false
    
    /// Initialize test context with completely isolated database instance
    public init(testName: String) {
        self.testName = testName
        self.provider = TestDatabaseProvider(testName: testName)
        
        // Initialize managers with isolated provider
        self.sessionManager = SessionManager(contextProvider: provider)
        self.taskManager = TaskManager(contextProvider: provider)
        self.dependencyManager = DependencyManager(contextProvider: provider)
    }
    
    /// Initialize the isolated database instance
    public func initialize() async throws {
        guard !isInitialized else { return }
        try await provider.initialize()
        isInitialized = true
    }
    
    /// Clean up all resources and remove temporary database
    public func cleanup() async {
        await provider.cleanup()
        isInitialized = false
    }
    
    /// Convenience initializer that automatically initializes the context
    public static func create(testName: String) async throws -> TestContext {
        let context = TestContext(testName: testName)
        try await context.initialize()
        return context
    }
    
    deinit {
        // Note: cleanup() must be called explicitly before deallocation
        // as we cannot perform async operations in deinit
    }
    
    // MARK: - Validation
    
    /// Ensure the context is properly initialized before use
    private func ensureInitialized() throws {
        guard isInitialized else {
            throw TestContextError.notInitialized(testName)
        }
    }
    
    // MARK: - Helper Methods with Managers
    
    public func createSession(title: String = "Test Session") async throws -> Session {
        try ensureInitialized()
        return try await sessionManager.create(title: title)
    }
    
    public func createTask(
        in session: Session,
        title: String = "Test Task",
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        try ensureInitialized()
        return try await taskManager.create(
            sessionID: session.id,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
    }
    
    public func createTaskHierarchy(
        in session: Session
    ) async throws -> (parent: Task, child: Task, grandchild: Task) {
        try ensureInitialized()
        let parent = try await createTask(in: session, title: "Parent Task")
        
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
    
    public func createDependencyChain(
        in session: Session
    ) async throws -> (first: Task, second: Task, third: Task) {
        try ensureInitialized()
        let first = try await createTask(in: session, title: "First Task")
        let second = try await createTask(in: session, title: "Second Task")
        let third = try await createTask(in: session, title: "Third Task")
        
        try await dependencyManager.add(
            blockerID: first.id,
            blockedID: second.id
        )
        
        try await dependencyManager.add(
            blockerID: second.id,
            blockedID: third.id
        )
        
        return (first, second, third)
    }
    
    public func createTasksWithStatuses(
        in session: Session
    ) async throws -> (pending: Task, inProgress: Task, done: Task, cancelled: Task) {
        try ensureInitialized()
        let pending = try await createTask(in: session, title: "Pending Task")
        
        let inProgress = try await createTask(in: session, title: "In Progress Task")
        _ = try await taskManager.update(
            id: inProgress.id,
            status: .inProgress
        )
        
        let done = try await createTask(in: session, title: "Done Task")
        _ = try await taskManager.update(
            id: done.id,
            status: .done
        )
        
        let cancelled = try await createTask(in: session, title: "Cancelled Task")
        _ = try await taskManager.update(
            id: cancelled.id,
            status: .cancelled,
            cancelReason: "Test cancellation"
        )
        
        return (pending, inProgress, done, cancelled)
    }
    
    public func createTasksWithDifficulties(
        in session: Session
    ) async throws -> [Task] {
        try ensureInitialized()
        var tasks: [Task] = []
        
        for difficulty in 1...5 {
            let task = try await createTask(
                in: session,
                title: "Difficulty \(difficulty) Task",
                difficulty: difficulty
            )
            tasks.append(task)
        }
        
        return tasks
    }
}

// MARK: - Test Execution Helper

/// Execute a test with automatic TestContext creation and cleanup
/// This ensures cleanup is properly awaited before the test completes
public func withTestContext(
    testName: String = #function,
    _ body: (TestContext) async throws -> Void
) async throws {
    let context = try await TestContext.create(testName: testName)
    do {
        try await body(context)
    } catch {
        // Ensure cleanup happens even on error
        await context.cleanup()
        throw error
    }
    // Normal cleanup
    await context.cleanup()
}