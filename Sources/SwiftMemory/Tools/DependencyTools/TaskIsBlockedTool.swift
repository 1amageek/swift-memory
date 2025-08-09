import Foundation
import OpenFoundationModels

@available(*, deprecated, message: "Use DependencyGetTool with type: .isBlocked instead")
public struct TaskIsBlockedTool: Tool {
    public let name = "memory.task.isBlocked"
    public let description = "Check if a task is currently blocked by active dependencies"
    
    public typealias Arguments = GetTaskBlockedStatusArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let blocked = try await DependencyManager.shared.isTaskBlocked(taskID: arguments.taskID)
            return .taskBlockedStatus(taskID: arguments.taskID, isBlocked: blocked)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}