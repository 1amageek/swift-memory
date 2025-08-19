import Foundation
import Kuzu
import KuzuSwiftExtension

public actor SessionManager {
    public static let shared = SessionManager()
    
    private let contextProvider: DatabaseContextProvider
    
    public init(contextProvider: DatabaseContextProvider = DefaultDatabaseProvider.shared) {
        self.contextProvider = contextProvider
    }
    
    private init() {
        self.contextProvider = DefaultDatabaseProvider.shared
    }
    
    // MARK: - CRUD Operations
    
    public func create(title: String) async throws -> Session {
        let context = try await contextProvider.context()
        let session = Session(title: title)
        return try await context.save(session)
    }
    
    public func get(id: String) async throws -> Session {
        let context = try await contextProvider.context()
        guard let session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        return session
    }
    
    public func list(
        startedAfter: Date? = nil,
        startedBefore: Date? = nil
    ) async throws -> [Session] {
        let context = try await contextProvider.context()
        
        // Build query directly
        var query = "MATCH (s:Session)"
        var whereConditions: [String] = []
        var bindings: [String: any Sendable] = [:]
        
        if let after = startedAfter {
            whereConditions.append("s.startedAt >= $startedAfter")
            bindings["startedAfter"] = after
        }
        
        if let before = startedBefore {
            whereConditions.append("s.startedAt <= $startedBefore")
            bindings["startedBefore"] = before
        }
        
        if !whereConditions.isEmpty {
            query += " WHERE " + whereConditions.joined(separator: " AND ")
        }
        
        query += " RETURN s ORDER BY s.startedAt DESC"
        
        let result = try await context.raw(query, bindings: bindings)
        return try result.map(to: Session.self)
    }
    
    public func update(id: String, title: String) async throws -> Session {
        let context = try await contextProvider.context()
        
        guard var session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        
        session.title = title
        return try await context.save(session)
    }
    
    public func delete(id: String, cascade: Bool = false) async throws {
        let context = try await contextProvider.context()
        
        // Verify session exists
        guard let session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        
        if cascade {
            // Cascade delete with separate queries for safety
            // First delete all descendants (subtasks)
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
                OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*]->(t)
                WHERE descendant IS NOT NULL
                DETACH DELETE descendant
                """,
                bindings: ["sessionID": id]
            )
            
            // Then delete all direct tasks
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
                DETACH DELETE t
                """,
                bindings: ["sessionID": id]
            )
        } else {
            // Check if session has tasks
            let hasTasksResult = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
                RETURN COUNT(t) > 0 AS hasTasks
                """,
                bindings: ["sessionID": id]
            )
            
            let hasTasks = try hasTasksResult.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasTasks {
                throw MemoryError.databaseError("Cannot delete session with tasks. Use cascade option to delete all tasks.")
            }
        }
        
        // Delete the session using raw query
        _ = try await context.raw(
            "MATCH (s:Session {id: $sessionID}) DETACH DELETE s",
            bindings: ["sessionID": id]
        )
    }
    
    // MARK: - Helper Methods
    
    public func getTaskCount(sessionID: String) async throws -> Int {
        let context = try await contextProvider.context()
        
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN COUNT(t) as count
            """,
            bindings: ["sessionID": sessionID]
        )
        
        return try result.mapFirstRequired(to: Int64.self, at: 0).asInt()
    }
    
    public func getStats(sessionID: String) async throws -> SessionStats {
        let context = try await contextProvider.context()
        
        // Get session
        guard let session = try await context.fetchOne(Session.self, id: sessionID) else {
            throw MemoryError.sessionNotFound(sessionID)
        }
        
        // Get task counts by status
        let statsResult = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN t.status as status, COUNT(t) as count
            """,
            bindings: ["sessionID": sessionID]
        )
        
        var pending = 0
        var inProgress = 0
        var done = 0
        var cancelled = 0
        
        for row in try statsResult.mapRows() {
            if let status = row["status"] as? String,
               let count = row["count"] as? Int64 {
                switch status {
                case "pending": pending = Int(count)
                case "inProgress": inProgress = Int(count)
                case "done": done = Int(count)
                case "cancelled": cancelled = Int(count)
                default: break
                }
            }
        }
        
        return SessionStats(
            session: session,
            totalTasks: pending + inProgress + done + cancelled,
            pendingTasks: pending,
            inProgressTasks: inProgress,
            completedTasks: done,
            cancelledTasks: cancelled
        )
    }
}

// MARK: - Supporting Types

public struct SessionStats: Sendable {
    public let session: Session
    public let totalTasks: Int
    public let pendingTasks: Int
    public let inProgressTasks: Int
    public let completedTasks: Int
    public let cancelledTasks: Int
}

extension Int64 {
    func asInt() -> Int {
        Int(self)
    }
}