import Foundation
import OpenFoundationModels

public struct TaskUpdateTool: Tool {
    public let name = "memory.task.update"
    public let description = "Update task properties (supports batch updates)"
    
    public typealias Arguments = UpdateTaskArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            // Validate cancellation reason if needed
            if arguments.update.status == .cancelled && arguments.update.cancelReason == nil {
                return .error("Cancellation reason is required when setting status to 'cancelled'")
            }
            
            // Handle batch update if multiple IDs provided
            if let taskIDs = arguments.taskIDs, !taskIDs.isEmpty {
                let tasks = try await TaskManager.shared.updateBatch(
                    taskIDs: taskIDs,
                    title: arguments.update.title,
                    description: arguments.update.description,
                    status: arguments.update.status,
                    assignee: arguments.update.assignee,
                    difficulty: arguments.update.difficulty,
                    cancelReason: arguments.update.cancelReason
                )
                
                if tasks.count == 1 {
                    return .taskUpdated(tasks[0])
                } else {
                    return .taskBatchUpdated(tasks)
                }
            }
            // Handle single task update (backward compatibility)
            else if let taskID = arguments.taskID {
                let task = try await TaskManager.shared.update(
                    id: taskID,
                    title: arguments.update.title,
                    description: arguments.update.description,
                    status: arguments.update.status,
                    assignee: arguments.update.assignee,
                    difficulty: arguments.update.difficulty,
                    cancelReason: arguments.update.cancelReason,
                    parentTaskID: nil // Parent task ID changes not supported in update
                )
                return .taskUpdated(task)
            }
            // No IDs provided
            else {
                return .error("Either taskID or taskIDs must be provided")
            }
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}