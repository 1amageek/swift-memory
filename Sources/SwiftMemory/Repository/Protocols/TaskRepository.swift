import Foundation

/// Repository protocol for Task operations
public protocol TaskRepository: Sendable {
    /// Create a new task in a session
    func create(_ task: Task, sessionID: UUID, parentTaskID: UUID?) async throws -> Task
    
    /// Find a task by ID
    func find(id: UUID) async throws -> Task?
    
    /// Find all tasks with optional filtering
    func findAll(filter: TaskFilter?) async throws -> [Task]
    
    /// Update an existing task
    func update(_ task: Task) async throws -> Task
    
    /// Delete a task by ID
    func delete(id: UUID, cascade: Bool) async throws
    
    /// Set parent relationship for a task
    func setParent(taskID: UUID, parentID: UUID?) async throws
    
    /// Get parent task
    func getParent(taskID: UUID) async throws -> Task?
    
    /// Get child tasks
    func getChildren(taskID: UUID) async throws -> [Task]
    
    /// Reorder tasks in a session
    func reorder(sessionID: UUID, orderedTaskIDs: [UUID]) async throws
    
    /// Batch update tasks
    func batchUpdate(taskIDs: [UUID], updates: TaskUpdateData) async throws -> [Task]
}

/// Filter options for task queries
public struct TaskFilter: Sendable {
    public let sessionID: UUID?
    public let status: TaskStatus?
    public let assignee: String?
    public let parentTaskID: UUID?
    public let difficultyMax: Int?
    public let readyOnly: Bool
    public let limit: Int?
    
    public init(
        sessionID: UUID? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        parentTaskID: UUID? = nil,
        difficultyMax: Int? = nil,
        readyOnly: Bool = false,
        limit: Int? = nil
    ) {
        self.sessionID = sessionID
        self.status = status
        self.assignee = assignee
        self.parentTaskID = parentTaskID
        self.difficultyMax = difficultyMax
        self.readyOnly = readyOnly
        self.limit = limit
    }
}

/// Updates to apply to tasks
public struct TaskUpdateData: Sendable {
    public let title: String?
    public let description: String?
    public let status: TaskStatus?
    public let assignee: String?
    public let difficulty: Int?
    public let cancelReason: String?
    
    public init(
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        difficulty: Int? = nil,
        cancelReason: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.assignee = assignee
        self.difficulty = difficulty
        self.cancelReason = cancelReason
    }
}