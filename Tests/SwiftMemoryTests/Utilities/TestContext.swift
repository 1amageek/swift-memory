import Foundation
import Testing
@testable import SwiftMemory

/// Test context that provides isolated managers for testing
public struct TestContext {
    public let sessionManager: SessionManager
    public let taskManager: TaskManager
    public let dependencyManager: DependencyManager
    
    private let factory: TestManagerFactory
    
    public init(testName: String) {
        self.factory = TestManagerFactory(testName: testName)
        self.sessionManager = factory.sessionManager()
        self.taskManager = factory.taskManager()
        self.dependencyManager = factory.dependencyManager()
    }
    
    public func cleanup() async {
        await factory.cleanup()
    }
    
    // MARK: - Helper Methods with Managers
    
    public func createSession(title: String = "Test Session") async throws -> Session {
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