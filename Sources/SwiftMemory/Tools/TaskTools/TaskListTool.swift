import Foundation
import OpenFoundationModels

public struct TaskListTool: Tool {
    public let name = "memory.task.list"
    public let description = "List tasks with various filters"
    
    public typealias Arguments = ListTasksArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let tasks = try await TaskManager.shared.list(
                sessionID: arguments.sessionID,
                status: arguments.status,
                assignee: arguments.assignee,
                parentTaskID: arguments.parentTaskID,
                readyOnly: arguments.readyOnly ?? false,
                difficultyMax: arguments.difficultyMax
            )
            return .taskList(tasks)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}