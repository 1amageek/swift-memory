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
        var sessions: [Session] = []
        while result.hasNext() {
            if let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let sessionDict = dict["s"] as? [String: Any?] {
                let session = try KuzuDecoder().decode(Session.self, from: sessionDict)
                sessions.append(session)
            }
        }
        return sessions
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
            // Cascade delete with proper pattern and safety
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})
                OPTIONAL MATCH (s)-[:HasTask]->(t:Task)
                OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*]->(t)
                WITH s, COLLECT(DISTINCT t) AS tasks, COLLECT(DISTINCT descendant) AS descendants
                FOREACH (d IN descendants | DETACH DELETE d)
                FOREACH (task IN tasks | DETACH DELETE task)
                DETACH DELETE s
                RETURN 1 as deleted
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
            RETURN t, r.order as taskOrder
            ORDER BY r.order ASC
            """,
            bindings: ["sessionID": sessionID]
        )
        
        var taskOrderPairs: [(task: Task, order: Int)] = []
        while result.hasNext() {
            if let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let taskDict = dict["t"] as? [String: Any?],
               let order = dict["taskOrder"] as? Int64 {
                let task = try KuzuDecoder().decode(Task.self, from: taskDict)
                taskOrderPairs.append((task: task, order: Int(order)))
            }
        }
        
        return taskOrderPairs
    }
}