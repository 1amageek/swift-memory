import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct TaskUpdateTool: Tool {
    public let name = "memory.task.update"
    public let description = "Update task properties (supports batch updates)"

    public typealias Arguments = UpdateTaskArguments
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
            // Validate cancellation reason
            if arguments.update.status == .cancelled && arguments.update.cancelReason == nil {
                return .error("Cancellation reason is required when setting status to 'cancelled'")
            }
            if arguments.update.status != .cancelled && arguments.update.cancelReason != nil {
                return .error("Cancellation reason is only allowed when status is 'cancelled'")
            }

            // Validate difficulty if provided
            if let difficulty = arguments.update.difficulty {
                guard (1...5).contains(difficulty) else {
                    throw MemoryError.invalidDifficulty(difficulty)
                }
            }

            // Determine which tasks to update
            let taskIDs: [String]
            if let ids = arguments.taskIDs, !ids.isEmpty {
                taskIDs = ids
            } else if let id = arguments.taskID {
                taskIDs = [id]
            } else {
                return .error("Either taskID or taskIDs must be provided")
            }

            // Update each task
            var updatedTasks: [Task] = []
            for taskID in taskIDs {
                // Get existing task
                let result = try context.raw(
                    "MATCH (t:Task {id: $id}) RETURN t",
                    bindings: ["id": taskID]
                )
                guard var task = try result.mapFirst(to: Task.self) else {
                    throw MemoryError.taskNotFound(taskID)
                }

                // Apply updates
                if let title = arguments.update.title {
                    task.title = title
                }
                if let description = arguments.update.description {
                    task.description = description
                }
                if let status = arguments.update.status {
                    task.status = status
                }
                if let assignee = arguments.update.assignee {
                    task.assignee = assignee
                }
                if let difficulty = arguments.update.difficulty {
                    task.difficulty = difficulty
                }
                if let cancelReason = arguments.update.cancelReason {
                    task.cancelReason = cancelReason
                }

                // Update timestamp
                task.updatedAt = Date()

                // Save
                context.insert(task)
                try context.save()

                updatedTasks.append(task)
            }

            // Return appropriate result
            if updatedTasks.count == 1 {
                return .taskUpdated(updatedTasks[0])
            } else {
                return .taskBatchUpdated(updatedTasks)
            }
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
