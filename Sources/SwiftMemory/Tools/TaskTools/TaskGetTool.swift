import Foundation
import OpenFoundationModels

public struct TaskGetTool: Tool {
    public let name = "memory.task.get"
    public let description = "Get a task by its ID, optionally with full relationship information"
    
    public typealias Arguments = GetTaskArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            if arguments.includeInfo == true {
                let taskInfo = try await TaskManager.shared.getTaskInfo(taskID: arguments.taskID)
                return .taskInfo(taskInfo)
            } else {
                let task = try await TaskManager.shared.get(id: arguments.taskID)
                return .taskRetrieved(task)
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