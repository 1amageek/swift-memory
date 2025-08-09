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
            // Support new include options
            if let include = arguments.include {
                let fullInfo = try await TaskManager.shared.getWithIncludes(
                    taskID: arguments.taskID,
                    include: include
                )
                return .taskFullInfo(fullInfo)
            }
            // Backward compatibility: includeInfo flag
            else if arguments.includeInfo == true {
                let taskInfo = try await TaskManager.shared.getTaskInfo(taskID: arguments.taskID)
                return .taskInfo(taskInfo)
            }
            // Default: just return the task
            else {
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