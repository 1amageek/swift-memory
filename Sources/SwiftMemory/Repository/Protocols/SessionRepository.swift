import Foundation

/// Repository protocol for Session operations
public protocol SessionRepository: Sendable {
    /// Create a new session
    func create(_ session: Session) async throws -> Session
    
    /// Find a session by ID
    func find(id: UUID) async throws -> Session?
    
    /// Find all sessions with optional filtering
    func findAll(filter: SessionFilter?) async throws -> [Session]
    
    /// Update an existing session
    func update(_ session: Session) async throws -> Session
    
    /// Delete a session by ID
    func delete(id: UUID, cascade: Bool) async throws
    
    /// Get all tasks in a session with their order
    func getTasks(sessionID: UUID) async throws -> [TaskWithOrder]
    
    /// Get the count of tasks in a session
    func getTaskCount(sessionID: UUID) async throws -> Int
}

/// Filter options for session queries
public struct SessionFilter: Sendable {
    public let startedAfter: Date?
    public let startedBefore: Date?
    public let limit: Int?
    
    public init(
        startedAfter: Date? = nil,
        startedBefore: Date? = nil,
        limit: Int? = nil
    ) {
        self.startedAfter = startedAfter
        self.startedBefore = startedBefore
        self.limit = limit
    }
}

/// Task with its order in the session
public struct TaskWithOrder: Sendable {
    public let task: Task
    public let order: Int
    
    public init(task: Task, order: Int) {
        self.task = task
        self.order = order
    }
}