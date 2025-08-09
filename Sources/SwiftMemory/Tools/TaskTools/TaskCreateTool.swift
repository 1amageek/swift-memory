import Foundation
import OpenFoundationModels

public struct TaskCreateTool: Tool {
    public let name = "memory.task.create"
    public let description = "Create a new task in a session"
    
    public typealias Arguments = CreateTaskArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let task = try await TaskManager.shared.create(
                sessionID: arguments.sessionID,
                title: arguments.title,
                description: arguments.description,
                difficulty: arguments.difficulty ?? 3,
                assignee: arguments.assignee,
                parentTaskID: arguments.parentTaskID
            )
            return .taskCreated(task)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}