import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct TaskGetTool: Tool {
    public let name = "memory.task.get"
    public let description = "Get a task by its ID, optionally with full relationship information"

    public typealias Arguments = GetTaskArguments
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
            // Get the task
            let result = try context.raw(
                "MATCH (t:Task {id: $id}) RETURN t",
                bindings: ["id": arguments.taskID]
            )
            guard let task = try result.mapFirst(to: Task.self) else {
                throw MemoryError.taskNotFound(arguments.taskID)
            }

            // Check if include options requested
            guard let include = arguments.include else {
                return .taskRetrieved(task)
            }

            // Build full info
            var session: Session? = nil
            var parent: Task? = nil
            var children: [Task] = []
            var blockers: [Task] = []
            var blocking: [Task] = []

            if include.session == true {
                let sessionResult = try context.raw("""
                    MATCH (s:Session)-[:HasTask]->(t:Task {id: $taskID})
                    RETURN s
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                session = try sessionResult.mapFirst(to: Session.self)
            }

            if include.parent == true {
                let parentResult = try context.raw("""
                    MATCH (child:Task {id: $taskID})-[:SubTaskOf]->(parent:Task)
                    RETURN parent
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                parent = try parentResult.mapFirst(to: Task.self)
            }

            if include.children == true {
                let childrenResult = try context.raw("""
                    MATCH (child:Task)-[:SubTaskOf]->(parent:Task {id: $taskID})
                    RETURN child
                    ORDER BY child.createdAt ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                children = try childrenResult.map(to: Task.self)
            }

            if include.blockers == true {
                let blockersResult = try context.raw("""
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    RETURN blocker
                    ORDER BY blocker.createdAt ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                blockers = try blockersResult.map(to: Task.self)
            }

            if include.blocking == true {
                let blockingResult = try context.raw("""
                    MATCH (blocker:Task {id: $taskID})-[:Blocks]->(blocked:Task)
                    RETURN blocked
                    ORDER BY blocked.createdAt ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                blocking = try blockingResult.map(to: Task.self)
            }

            let fullInfo = TaskFullInfo(
                task: task,
                session: session,
                parent: parent,
                children: children,
                blockers: blockers,
                blocking: blocking
            )

            return .taskFullInfo(fullInfo)
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
