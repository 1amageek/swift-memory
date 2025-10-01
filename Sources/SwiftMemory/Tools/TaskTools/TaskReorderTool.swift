import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct TaskReorderTool: Tool {
    public let name = "memory.task.reorder"
    public let description = "Reorder tasks within a session"

    public typealias Arguments = ReorderTasksArguments
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
            // Validate all tasks exist in session
            let validationResult = try context.raw("""
                UNWIND $taskIDs AS taskID
                MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task {id: taskID})
                RETURN collect(t.id) as validIDs
                """,
                bindings: ["sessionID": arguments.sessionID, "taskIDs": arguments.orderedIDs]
            )

            guard let row = try validationResult.getNext(),
                  let validIDs = try? row.getValue(0) as? [String],
                  validIDs.count == arguments.orderedIDs.count else {
                throw MemoryError.invalidInput(
                    field: "orderedTaskIDs",
                    reason: "Some task IDs do not exist in the session"
                )
            }

            // Check for duplicates
            let uniqueIDs = Set(arguments.orderedIDs)
            guard uniqueIDs.count == arguments.orderedIDs.count else {
                throw MemoryError.invalidInput(
                    field: "orderedTaskIDs",
                    reason: "Duplicate task IDs found"
                )
            }

            // Update orders
            let pairs: [[String: any Sendable]] = arguments.orderedIDs.enumerated().map { index, taskID in
                ["id": taskID, "orderValue": index + 1]
            }

            _ = try context.raw("""
                UNWIND $pairs AS pair
                MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task {id: pair.id})
                SET r.order = pair.orderValue
                RETURN COUNT(*) as updated
                """,
                bindings: ["sessionID": arguments.sessionID, "pairs": pairs]
            )

            return .taskReordered(sessionID: arguments.sessionID, orderedIds: arguments.orderedIDs)
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
