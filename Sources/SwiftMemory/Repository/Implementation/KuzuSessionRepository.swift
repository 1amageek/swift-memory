import Foundation
import Kuzu
import KuzuSwiftExtension

/// Kuzu-based implementation of SessionRepository
public actor KuzuSessionRepository: SessionRepository {
    private let context: GraphContext
    
    public init(context: GraphContext) {
        self.context = context
    }
    
    public func create(_ session: Session) async throws -> Session {
        return try await context.save(session)
    }
    
    public func find(id: UUID) async throws -> Session? {
        return try await context.fetchOne(Session.self, id: id)
    }
    
    public func findAll(filter: SessionFilter?) async throws -> [Session] {
        var query = "MATCH (s:Session)"
        var bindings: [String: any Sendable] = [:]
        var conditions: [String] = []
        
        if let filter = filter {
            if let after = filter.startedAfter {
                conditions.append("s.startedAt >= $after")
                bindings["after"] = after
            }
            if let before = filter.startedBefore {
                conditions.append("s.startedAt <= $before")
                bindings["before"] = before
            }
        }
        
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        query += " RETURN s ORDER BY s.startedAt DESC"
        
        if let limit = filter?.limit {
            query += " LIMIT \(limit)"
        }
        
        let result = try await context.raw(query, bindings: bindings)
        
        // Beta 2: Automatic KuzuNode to Session mapping
        return try result.map(to: Session.self)
    }
    
    public func update(_ session: Session) async throws -> Session {
        return try await context.save(session)
    }
    
    public func delete(id: UUID, cascade: Bool) async throws {
        if cascade {
            // Use transaction for cascade delete
            try await context.withTransaction { tx in
                // Delete all descendant tasks first
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
                
                // Delete the session itself
                _ = try tx.raw(
                    """
                    MATCH (s:Session {id: $sessionID})
                    DETACH DELETE s
                    """,
                    bindings: ["sessionID": id]
                )
            }
        } else {
            // Simple delete
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})
                DETACH DELETE s
                """,
                bindings: ["sessionID": id]
            )
        }
    }
    
    public func getTasks(sessionID: UUID) async throws -> [TaskWithOrder] {
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
            RETURN t, r.`order` as taskOrder
            ORDER BY r.`order` ASC
            """,
            bindings: ["sessionID": sessionID]
        )
        
        // Beta 2: Efficient mapping with automatic node extraction
        let rows = try result.mapRows()
        return try rows.map { row in
            let task = try KuzuDecoder().decode(
                Task.self,
                from: row["t"] as! [String: Any]
            )
            let order = (row["taskOrder"] as? Int64).map(Int.init) ?? 0
            return TaskWithOrder(task: task, order: order)
        }
    }
    
    public func getTaskCount(sessionID: UUID) async throws -> Int {
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN COUNT(t) as count
            """,
            bindings: ["sessionID": sessionID]
        )
        
        // Beta 2: Direct extraction of single value
        return Int(try result.mapFirstRequired(to: Int64.self, at: 0))
    }
}