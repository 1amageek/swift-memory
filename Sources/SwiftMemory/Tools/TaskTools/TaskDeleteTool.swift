import Foundation
import OpenFoundationModels

public struct TaskDeleteTool: Tool {
    public let name = "memory.task.delete"
    public let description = "Delete a task, optionally cascading to delete all its subtasks"
    
    public typealias Arguments = DeleteTaskArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            try await TaskManager.shared.delete(
                id: arguments.taskID,
                cascade: arguments.cascade ?? false
            )
            return .taskDeleted(arguments.taskID)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}