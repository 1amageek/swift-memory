import Foundation
import OpenFoundationModels

public struct TaskReorderTool: Tool {
    public let name = "memory.task.reorder"
    public let description = "Reorder tasks within a session"
    
    public typealias Arguments = ReorderTasksArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            try await TaskManager.shared.reorder(
                sessionID: arguments.sessionID,
                orderedIds: arguments.orderedIDs
            )
            return .taskReordered(sessionID: arguments.sessionID, orderedIds: arguments.orderedIDs)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}