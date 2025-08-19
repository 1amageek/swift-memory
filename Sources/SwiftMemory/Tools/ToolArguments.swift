import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import OpenFoundationModelsMacros

// MARK: - Task Tool Arguments

@Generable
public struct CreateTaskArguments: Sendable {
    @Guide(description: "The session ID this task belongs to")
    public let sessionID: String
    
    @Guide(description: "Task title")
    public let title: String
    
    @Guide(description: "Optional task description")
    public let description: String?
    
    @Guide(description: "Task difficulty level", .range(1...5))
    public let difficulty: Int?
    
    @Guide(description: "Person assigned to this task")
    public let assignee: String?
    
    @Guide(description: "Optional parent task ID for subtasks")
    public let parentTaskID: String?
}

@Generable
public struct UpdateTaskArguments: Sendable {
    @Guide(description: "Single task ID for backward compatibility")
    public let taskID: String?
    
    @Guide(description: "Multiple task IDs for batch update")
    public let taskIDs: [String]?
    
    @Guide(description: "Updates to apply to the task(s)")
    public let update: TaskUpdate
}

@Generable
public struct TaskUpdate: Codable, Sendable {
    @Guide(description: "New task title")
    public let title: String?
    
    @Guide(description: "New task description")
    public let description: String?
    
    @Guide(description: "New task status")
    public let status: TaskStatus?
    
    @Guide(description: "New assignee")
    public let assignee: String?
    
    @Guide(description: "New difficulty level", .range(1...5))
    public let difficulty: Int?
    
    @Guide(description: "Reason for cancellation")
    public let cancelReason: String?
}

@Generable
public struct GetTaskArguments: Sendable {
    @Guide(description: "The task ID to retrieve")
    public let taskID: String
    
    @Guide(description: "Optional data to include in response")
    public let include: TaskIncludeOptions?
}

@Generable
public struct DeleteTaskArguments: Sendable {
    @Guide(description: "The task ID to delete")
    public let taskID: String
    
    @Guide(description: "Whether to cascade delete subtasks")
    public let cascade: Bool?
}

@Generable
public struct ListTasksArguments: Sendable {
    @Guide(description: "Filter by session ID")
    public let sessionID: String?
    
    @Guide(description: "Filter by task status")
    public let status: TaskStatus?
    
    @Guide(description: "Filter by assignee")
    public let assignee: String?
    
    @Guide(description: "Filter by parent task ID")
    public let parentTaskID: String?
    
    @Guide(description: "Only show tasks ready to start")
    public let readyOnly: Bool?
    
    @Guide(description: "Maximum difficulty level", .range(1...5))
    public let difficultyMax: Int?
}

@Generable
public struct ReorderTasksArguments: Sendable {
    @Guide(description: "The session ID containing the tasks")
    public let sessionID: String
    
    @Guide(description: "Task IDs in the desired order")
    public let orderedIDs: [String]
}

// MARK: - Session Tool Arguments

@Generable
public struct CreateSessionArguments: Sendable {
    @Guide(description: "Session title")
    public let title: String
}

@Generable
public struct UpdateSessionArguments: Sendable {
    @Guide(description: "The session ID to update")
    public let sessionID: String
    
    @Guide(description: "New session title")
    public let title: String
}

@Generable
public struct GetSessionArguments: Sendable {
    @Guide(description: "The session ID to retrieve")
    public let sessionID: String
}

@Generable
public struct DeleteSessionArguments: Sendable {
    @Guide(description: "The session ID to delete")
    public let sessionID: String
    
    @Guide(description: "Whether to cascade delete all tasks")
    public let cascade: Bool?
}

@Generable
public struct ListSessionsArguments: Sendable {
    @Guide(description: "Filter sessions started after this date")
    public let startedAfter: Date?
    
    @Guide(description: "Filter sessions started before this date")
    public let startedBefore: Date?
}

// MARK: - Dependency Tool Arguments
// Note: Old dependency arguments removed. Use SetDependencyArguments and GetDependencyArguments from the new tools.