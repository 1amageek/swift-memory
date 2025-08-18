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
    
    public func get(id: UUID) async throws -> Session {
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
        
        // Use QueryBuilder for cleaner query construction
        let (query, bindings) = CypherQueryBuilder.SessionQueries.list(
            startedAfter: startedAfter,
            startedBefore: startedBefore
        )
        
        let result = try await context.raw(query, bindings: bindings)
        return try result.map(to: Session.self)
    }
    
    public func update(id: UUID, title: String) async throws -> Session {
        let context = try await contextProvider.context()
        
        guard var session = try await context.fetchOne(Session.self, id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        
        session.title = title
        return try await context.save(session)
    }
    
    public func delete(id: UUID, cascade: Bool = false) async throws {
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
            
            // Finally delete the session
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})
                DETACH DELETE s
                """,
                bindings: ["sessionID": id]
            )
        } else {
            // Simple delete
            try await context.delete(session)
        }
    }
    
    // MARK: - Session Task Management
    
    public func getTaskCount(sessionID: UUID) async throws -> Int {
        let context = try await contextProvider.context()
        
        // Count tasks for session
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN COUNT(t) as count
            """,
            bindings: ["sessionID": sessionID]
        )
        
        if result.hasNext(),
           let tuple = try result.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let count = dict["count"] as? Int64 {
            return Int(count)
        }
        return 0
    }
    
    public func getTasks(sessionID: UUID) async throws -> [(task: Task, order: Int)] {
        let context = try await contextProvider.context()
        
        // Get tasks with their order
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
            RETURN t, r.`order` as taskOrder
            ORDER BY r.`order` ASC
            """,
            bindings: ["sessionID": sessionID]
        )
        
        let rows = try result.mapRows()
        return try rows.map { row in
            // Beta 2: "t" column now contains node properties automatically
            let task = try KuzuDecoder().decode(Task.self, from: row["t"] as! [String: Any])
            let order = (row["taskOrder"] as? Int64).map(Int.init) ?? 0
            return (task: task, order: order)
        }
    }
}