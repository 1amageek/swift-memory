import Foundation
import OpenFoundationModels
import Kuzu
import KuzuSwiftExtension

public struct TaskCreateTool: Tool {
    public let name = "memory.task.create"
    public let description = "Create a new task in a session"

    public typealias Arguments = CreateTaskArguments
    public typealias Output = MemoryToolResult

    private let context: GraphContext

    public init() {
        self.context = try! SwiftMemoryContext.shared.context()
    }

    init(context: GraphContext) {
        self.context = context
    }

    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            // Validate difficulty
            let difficulty = arguments.difficulty ?? 3
            guard (1...5).contains(difficulty) else {
                throw MemoryError.invalidDifficulty(difficulty)
            }

            // Create task
            let task = Task(
                title: arguments.title,
                description: arguments.description,
                assignee: arguments.assignee,
                difficulty: difficulty
            )

            // Save task node
            context.insert(task)
            try context.save()

            // Create relationships in transaction
            try context.withRawTransaction { conn in
                // Verify session exists
                let sessionCheck = try conn.query("MATCH (s:Session {id: '\(arguments.sessionID)'}) RETURN s")
                guard sessionCheck.hasNext() else {
                    throw MemoryError.sessionNotFound(arguments.sessionID)
                }

                // Verify parent exists if specified
                if let parentID = arguments.parentTaskID {
                    let parentCheck = try conn.query("MATCH (t:Task {id: '\(parentID)'}) RETURN t")
                    guard parentCheck.hasNext() else {
                        throw MemoryError.taskNotFound(parentID)
                    }
                }

                // Get next order
                let orderResult = try conn.query("""
                    MATCH (s:Session {id: '\(arguments.sessionID)'})-[r:HasTask]->(:Task)
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
                    MATCH (s:Session {id: '\(arguments.sessionID)'}), (t:Task {id: '\(task.id)'})
                    MERGE (s)-[r:HasTask]->(t)
                    SET r.order = \(maxOrder + 1)
                    """)

                // Create SubTaskOf relationship if parent specified
                if let parentID = arguments.parentTaskID {
                    _ = try conn.query("""
                        MATCH (child:Task {id: '\(task.id)'}), (parent:Task {id: '\(parentID)'})
                        MERGE (child)-[:SubTaskOf]->(parent)
                        """)
                }
            }

            return .taskCreated(task)
        } catch {
            return .error(mapError(error))
        }
    }

    private func mapError(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription {
            return msg
        }
        return "Unexpected error occurred"
    }
}
