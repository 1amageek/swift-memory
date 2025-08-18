import Foundation
import Kuzu
import KuzuSwiftExtension

/// Improved SessionManager using Query DSL and Beta 2 features
public actor SessionManagerV2 {
    public static let shared = SessionManagerV2()
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    public func create(title: String) async throws -> Session {
        let context = try await SwiftMemoryContext.shared.context()
        let session = Session(title: title)
        return try await context.save(session)
    }
    
    public func get(id: UUID) async throws -> Session {
        let context = try await SwiftMemoryContext.shared.context()
        guard let session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        return session
    }
    
    public func list(
        startedAfter: Date? = nil,
        startedBefore: Date? = nil
    ) async throws -> [Session] {
        let context = try await SwiftMemoryContext.shared.context()
        
        // Build conditions
        var bindings: [String: any Sendable] = [:]
        var whereConditions: [String] = []
        
        if let after = startedAfter {
            whereConditions.append("s.startedAt >= $startedAfter")
            bindings["startedAfter"] = after
        }
        
        if let before = startedBefore {
            whereConditions.append("s.startedAt <= $startedBefore")
            bindings["startedBefore"] = before
        }
        
        // Build query
        var query = "MATCH (s:Session)"
        if !whereConditions.isEmpty {
            query += " WHERE " + whereConditions.joined(separator: " AND ")
        }
        query += " RETURN s ORDER BY s.startedAt DESC"
        
        // Execute and use Beta 2's automatic node mapping
        let result = try await context.raw(query, bindings: bindings)
        return try result.map(to: Session.self)
    }
    
    public func update(id: UUID, title: String) async throws -> Session {
        let context = try await SwiftMemoryContext.shared.context()
        
        guard var session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        
        session.title = title
        return try await context.save(session)
    }
    
    public func delete(id: UUID, cascade: Bool = false) async throws {
        let context = try await SwiftMemoryContext.shared.context()
        
        // Verify session exists
        guard let session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        
        if cascade {
            // Use transaction for cascade delete
            try await context.withTransaction { tx in
                // Delete all descendants first
                _ = try tx.raw(
                    """
                    MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
                    OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*]->(t)
                    WHERE descendant IS NOT NULL
                    DETACH DELETE descendant
                    """,
                    bindings: ["sessionID": id]
                )
                
                // Delete direct tasks
                _ = try tx.raw(
                    """
                    MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
                    DETACH DELETE t
                    """,
                    bindings: ["sessionID": id]
                )
                
                // Delete session
                _ = try tx.raw(
                    """
                    MATCH (s:Session {id: $sessionID})
                    DETACH DELETE s
                    """,
                    bindings: ["sessionID": id]
                )
            }
        } else {
            try await context.delete(session)
        }
    }
    
    // MARK: - Session Task Management
    
    public func getTaskCount(sessionID: UUID) async throws -> Int {
        let context = try await SwiftMemoryContext.shared.context()
        
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN COUNT(t) as count
            """,
            bindings: ["sessionID": sessionID]
        )
        
        // Use Beta 2's mapFirstRequired for single value extraction
        return Int(try result.mapFirstRequired(to: Int64.self, at: 0))
    }
    
    public func getTasks(sessionID: UUID) async throws -> [(task: Task, order: Int)] {
        let context = try await SwiftMemoryContext.shared.context()
        
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
            RETURN t, r.`order` as taskOrder
            ORDER BY r.`order` ASC
            """,
            bindings: ["sessionID": sessionID]
        )
        
        // Use Beta 2's mapRows for efficient processing
        let rows = try result.mapRows()
        return try rows.map { row in
            // Beta 2 automatically extracts node properties from column "t"
            let task = try KuzuDecoder().decode(Task.self, from: row["t"] as! [String: Any])
            let order = (row["taskOrder"] as? Int64).map(Int.init) ?? 0
            return (task: task, order: order)
        }
    }
}