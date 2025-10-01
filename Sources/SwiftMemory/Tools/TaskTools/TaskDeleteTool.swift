import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct TaskDeleteTool: Tool {
    public let name = "memory.task.delete"
    public let description = "Delete a task and optionally its subtasks"

    public typealias Arguments = DeleteTaskArguments
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
            if arguments.cascade == true {
                // Cascade delete: task + all subtasks
                _ = try context.raw("""
                    MATCH (t:Task {id: $taskID})
                    OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*1..]->(t)
                    WHERE descendant IS NOT NULL
                    DETACH DELETE descendant
                    """,
                    bindings: ["taskID": arguments.taskID]
                )

                // Delete the task itself
                _ = try context.raw(
                    "MATCH (t:Task {id: $taskID}) DETACH DELETE t",
                    bindings: ["taskID": arguments.taskID]
                )
            } else {
                // Simple delete
                _ = try context.raw(
                    "MATCH (t:Task {id: $taskID}) DETACH DELETE t",
                    bindings: ["taskID": arguments.taskID]
                )
            }

            return .taskDeleted(arguments.taskID)
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
