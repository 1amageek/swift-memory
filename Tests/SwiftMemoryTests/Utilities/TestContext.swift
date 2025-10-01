import Foundation
import Testing
import KuzuSwiftExtension
@testable import SwiftMemory

/// Simplified test context with in-memory database
public final class TestContext {
    public let context: GraphContext
    private let testName: String

    /// Initialize test context with in-memory database
    public init(testName: String = #function) throws {
        self.testName = testName

        // Create in-memory GraphContainer
        let container = try GraphContainer(
            for: Session.self,
                Task.self,
                HasTask.self,
                SubTaskOf.self,
                Blocks.self,
            configuration: GraphConfiguration(databasePath: ":memory:")
        )

        self.context = GraphContext(container)
    }

    // MARK: - Helper Methods

    /// Create a test session
    public func createSession(title: String = "Test Session") throws -> Session {
        let session = Session(title: title)
        context.insert(session)
        try context.save()
        return session
    }

    /// Create a test task in a session
    public func createTask(
        in session: Session,
        title: String = "Test Task",
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: String? = nil
    ) throws -> Task {
        let task = Task(
            title: title,
            description: description,
            assignee: assignee,
            difficulty: difficulty
        )

        // Save task node
        context.insert(task)
        try context.save()

        // Create relationships in transaction
        try context.withRawTransaction { conn in
            // Get next order
            let orderResult = try conn.query("""
                MATCH (s:Session {id: '\(session.id)'})-[r:HasTask]->(:Task)
                RETURN max(r.order) as maxOrder
                """)
            let maxOrder: Int
            if orderResult.hasNext(),
               let row = try orderResult.getNext(),
               let value = try? row.getValue(0) as? Int64 {
                maxOrder = Int(value)
            } else {
                maxOrder = 0
            }

            // Create HasTask relationship
            _ = try conn.query("""
                MATCH (s:Session {id: '\(session.id)'}), (t:Task {id: '\(task.id)'})
                MERGE (s)-[r:HasTask]->(t)
                SET r.order = \(maxOrder + 1)
                """)

            // Create SubTaskOf relationship if parent specified
            if let parentID = parentTaskID {
                _ = try conn.query("""
                    MATCH (child:Task {id: '\(task.id)'}), (parent:Task {id: '\(parentID)'})
                    MERGE (child)-[:SubTaskOf]->(parent)
                    """)
            }
        }

        return task
    }

    /// Create a task hierarchy (parent -> child -> grandchild)
    public func createTaskHierarchy(
        in session: Session
    ) throws -> (parent: Task, child: Task, grandchild: Task) {
        let parent = try createTask(in: session, title: "Parent Task")
        let child = try createTask(in: session, title: "Child Task", parentTaskID: parent.id)
        let grandchild = try createTask(in: session, title: "Grandchild Task", parentTaskID: child.id)

        return (parent, child, grandchild)
    }

    /// Create a dependency chain (first blocks second blocks third)
    public func createDependencyChain(
        in session: Session
    ) throws -> (first: Task, second: Task, third: Task) {
        let first = try createTask(in: session, title: "First Task")
        let second = try createTask(in: session, title: "Second Task")
        let third = try createTask(in: session, title: "Third Task")

        // Add dependencies
        _ = try context.raw("""
            MATCH (blocker:Task {id: '\(first.id)'}), (blocked:Task {id: '\(second.id)'})
            MERGE (blocker)-[:Blocks]->(blocked)
            """)
        _ = try context.raw("""
            MATCH (blocker:Task {id: '\(second.id)'}), (blocked:Task {id: '\(third.id)'})
            MERGE (blocker)-[:Blocks]->(blocked)
            """)

        return (first, second, third)
    }

    /// Create tasks with different statuses
    public func createTasksWithStatuses(
        in session: Session
    ) throws -> (pending: Task, inProgress: Task, done: Task, cancelled: Task) {
        let pending = try createTask(in: session, title: "Pending Task")

        var inProgress = try createTask(in: session, title: "In Progress Task")
        inProgress.status = .inProgress
        inProgress.updatedAt = Date()
        context.insert(inProgress)
        try context.save()

        var done = try createTask(in: session, title: "Done Task")
        done.status = .done
        done.updatedAt = Date()
        context.insert(done)
        try context.save()

        var cancelled = try createTask(in: session, title: "Cancelled Task")
        cancelled.status = .cancelled
        cancelled.cancelReason = "Test cancellation"
        cancelled.updatedAt = Date()
        context.insert(cancelled)
        try context.save()

        return (pending, inProgress, done, cancelled)
    }

    /// Create tasks with different difficulties
    public func createTasksWithDifficulties(
        in session: Session
    ) throws -> [Task] {
        var tasks: [Task] = []

        for difficulty in 1...5 {
            let task = try createTask(
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

/// Execute a test with automatic TestContext creation
public func withTestContext(
    testName: String = #function,
    _ body: (TestContext) throws -> Void
) throws {
    let context = try TestContext(testName: testName)
    try body(context)
}
