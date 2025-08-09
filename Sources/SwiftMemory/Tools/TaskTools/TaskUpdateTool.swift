import Foundation
import OpenFoundationModels

public struct TaskUpdateTool: Tool {
    public let name = "memory.task.update"
    public let description = "Update task properties"
    
    public typealias Arguments = UpdateTaskArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            // Validate cancellation reason if needed
            if arguments.update.status == .cancelled && arguments.update.cancelReason == nil {
                return .error("Cancellation reason is required when setting status to 'cancelled'")
            }
            
            let task = try await TaskManager.shared.update(
                id: arguments.taskID,
                title: arguments.update.title,
                description: arguments.update.description,
                status: arguments.update.status,
                assignee: arguments.update.assignee,
                difficulty: arguments.update.difficulty,
                cancelReason: arguments.update.cancelReason,
                parentTaskID: nil // Parent task ID changes not supported in update
            )
            return .taskUpdated(task)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}