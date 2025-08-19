import Foundation
import Kuzu
import KuzuSwiftExtension

public actor DependencyManager {
    public static let shared = DependencyManager()
    
    private let contextProvider: DatabaseContextProvider
    
    public init(contextProvider: DatabaseContextProvider = DefaultDatabaseProvider.shared) {
        self.contextProvider = contextProvider
    }
    
    private init() {
        self.contextProvider = DefaultDatabaseProvider.shared
    }
    
    // MARK: - Dependency Operations
    
    public func add(blockerID: String, blockedID: String) async throws {
        // Check for self-loop first (before any database operations)
        guard blockerID != blockedID else {
            throw MemoryError.invalidInput(
                field: "dependency",
                reason: "Task cannot block itself (self-loop detected)"
            )
        }
        
        // Execute in a transaction for atomicity
        try await TransactionManager.executeInTransaction(
            using: contextProvider
        ) { context in
            // Verify both tasks exist
            guard let _ = try await context.fetchOne(Task.self, id: blockerID) else {
                throw MemoryError.taskNotFound(blockerID)
            }
            
            guard let _ = try await context.fetchOne(Task.self, id: blockedID) else {
                throw MemoryError.taskNotFound(blockedID)
            }
            
            // Check for circular dependency - would adding blocker->blocked create a cycle?
            // We need to check if there's already a path from blocked->blocker
            let result = try await context.raw(
                """
                MATCH p = (blocked:Task {id: $blockedID})-[:Blocks*]->(blocker:Task {id: $blockerID})
                RETURN COUNT(p) > 0 AS hasCycle
                """,
                bindings: ["blockedID": blockedID, "blockerID": blockerID]
            )
            
            let hasCycle = try result.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasCycle {
                throw MemoryError.circularDependency(blocker: blockerID, blocked: blockedID)
            }
            
            // Create Blocks relationship using MERGE to prevent duplicates
            _ = try await context.raw(
                """
                MATCH (blocker:Task {id: $blockerID}), (blocked:Task {id: $blockedID})
                MERGE (blocker)-[r:Blocks]->(blocked)
                RETURN r
                """,
                bindings: ["blockerID": blockerID, "blockedID": blockedID]
            )
        }
    }
    
    public func remove(blockerID: String, blockedID: String) async throws {
        let context = try await contextProvider.context()
        
        // Remove the dependency safely
        _ = try await context.raw(
            """
            MATCH (blocker:Task {id: $blockerID})-[r:Blocks]->(blocked:Task {id: $blockedID})
            WITH r
            DELETE r
            RETURN COUNT(*) as deleted
            """,
            bindings: ["blockerID": blockerID, "blockedID": blockedID]
        )
    }
    
    // MARK: - Query Operations
    
    public func getBlockers(taskID: String) async throws -> [Task] {
        let context = try await contextProvider.context()
        
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            RETURN blocker
            ORDER BY blocker.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.map(to: Task.self)
    }
    
    public func getBlocking(taskID: String) async throws -> [Task] {
        let context = try await contextProvider.context()
        
        let result = try await context.raw(
            """
            MATCH (blocker:Task {id: $taskID})-[:Blocks]->(blocked:Task)
            RETURN blocked
            ORDER BY blocked.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.map(to: Task.self)
    }
    
    public func isBlocked(taskID: String) async throws -> Bool {
        let context = try await contextProvider.context()
        
        // A task is blocked if there are any active (pending or in-progress) blockers
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            WHERE blocker.status IN ['pending', 'inProgress']
            RETURN COUNT(blocker) > 0 AS isBlocked
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.mapFirstRequired(to: Bool.self, at: 0)
    }
    
    // Alias for compatibility
    public func isTaskBlocked(taskID: String) async throws -> Bool {
        return try await isBlocked(taskID: taskID)
    }
    
    // Alias for compatibility
    public func getDependencyChain(taskID: String) async throws -> DependencyChain {
        return try await getFullChain(taskID: taskID)
    }
    
    // MARK: - Chain Operations
    
    public func getFullChain(taskID: String) async throws -> DependencyChain {
        let context = try await contextProvider.context()
        
        // Get all upstream dependencies (tasks that block this task, directly or indirectly)
        let upstreamResult = try await context.raw(
            """
            MATCH (t:Task {id: $taskID})
            OPTIONAL MATCH path = (upstream:Task)-[:Blocks*]->(t)
            WHERE upstream.id <> $taskID
            WITH upstream, length(path) as depth
            WHERE upstream IS NOT NULL
            RETURN DISTINCT upstream, depth
            ORDER BY depth ASC, upstream.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        var upstream: [DependencyChainItem] = []
        let decoder = KuzuDecoder()
        for row in try upstreamResult.mapRows() {
            if let taskData = row["upstream"] as? [String: Any],
               let task = try? decoder.decode(Task.self, from: taskData),
               let depth = row["depth"] as? Int64 {
                upstream.append(DependencyChainItem(task: task, depth: Int(depth)))
            }
        }
        
        // Get all downstream dependencies (tasks that this task blocks, directly or indirectly)
        let downstreamResult = try await context.raw(
            """
            MATCH (t:Task {id: $taskID})
            OPTIONAL MATCH path = (t)-[:Blocks*]->(downstream:Task)
            WHERE downstream.id <> $taskID
            WITH downstream, length(path) as depth
            WHERE downstream IS NOT NULL
            RETURN DISTINCT downstream, depth
            ORDER BY depth ASC, downstream.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        var downstream: [DependencyChainItem] = []
        for row in try downstreamResult.mapRows() {
            if let taskData = row["downstream"] as? [String: Any],
               let task = try? decoder.decode(Task.self, from: taskData),
               let depth = row["depth"] as? Int64 {
                downstream.append(DependencyChainItem(task: task, depth: Int(depth)))
            }
        }
        
        return DependencyChain(
            taskID: taskID,
            upstream: upstream,
            downstream: downstream
        )
    }
    
    // MARK: - Batch Operations
    
    public func addMultiple(dependencies: [(blockerID: String, blockedID: String)]) async throws {
        for (blockerID, blockedID) in dependencies {
            try await add(blockerID: blockerID, blockedID: blockedID)
        }
    }
    
    public func removeAll(taskID: String) async throws {
        let context = try await contextProvider.context()
        
        // Remove all dependencies where task is either blocker or blocked
        _ = try await context.raw(
            """
            MATCH (t:Task {id: $taskID})
            OPTIONAL MATCH (t)-[r:Blocks]->(:Task)
            DELETE r
            """,
            bindings: ["taskID": taskID]
        )
        
        _ = try await context.raw(
            """
            MATCH (t:Task {id: $taskID})
            OPTIONAL MATCH (:Task)-[r:Blocks]->(t)
            DELETE r
            """,
            bindings: ["taskID": taskID]
        )
    }
}

// MARK: - Supporting Types

public struct DependencyChain: Codable, Sendable {
    public let taskID: String
    public let upstream: [DependencyChainItem]    // Tasks that block this task
    public let downstream: [DependencyChainItem]  // Tasks that this task blocks
    
    public init(taskID: String, upstream: [DependencyChainItem] = [], downstream: [DependencyChainItem] = []) {
        self.taskID = taskID
        self.upstream = upstream
        self.downstream = downstream
    }
}

public struct DependencyChainItem: Codable, Sendable {
    public let task: Task
    public let depth: Int  // How many levels away from the main task
    
    public init(task: Task, depth: Int) {
        self.task = task
        self.depth = depth
    }
}

public struct TaskFullInfo: Codable, Sendable {
    public let task: Task
    public var session: Session?
    public var parent: Task?
    public var children: [Task]?
    public var blockers: [Task]?
    public var blocking: [Task]?
    public var fullChain: DependencyChain?
    
    public init(task: Task) {
        self.task = task
    }
    
    public init(
        task: Task,
        session: Session? = nil,
        parent: Task? = nil,
        children: [Task]? = nil,
        blockers: [Task]? = nil,
        blocking: [Task]? = nil,
        fullChain: DependencyChain? = nil
    ) {
        self.task = task
        self.session = session
        self.parent = parent
        self.children = children
        self.blockers = blockers
        self.blocking = blocking
        self.fullChain = fullChain
    }
}