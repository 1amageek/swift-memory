import Foundation
import Kuzu
import KuzuSwiftExtension

/// Efficient query patterns using Beta 2 features and optimizations
public struct EfficientQueries {
    
    // MARK: - Batch Validation
    
    /// Validate that multiple tasks exist in a session using UNWIND
    public static func validateTasksExist(
        taskIDs: [UUID],
        sessionID: UUID,
        context: GraphContext
    ) async throws -> Set<UUID> {
        let result = try await context.raw(
            """
            UNWIND $taskIDs AS taskID
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task {id: taskID})
            RETURN t.id as validID
            """,
            bindings: [
                "taskIDs": taskIDs,
                "sessionID": sessionID
            ]
        )
        
        // Beta 2: Direct column extraction
        let validIDs = try result.column("validID", as: UUID.self)
        return Set(validIDs)
    }
    
    /// Validate tasks exist globally
    public static func validateTasksExistGlobal(
        taskIDs: [UUID],
        context: GraphContext
    ) async throws -> Set<UUID> {
        let result = try await context.raw(
            """
            UNWIND $taskIDs AS taskID
            MATCH (t:Task {id: taskID})
            RETURN t.id as validID
            """,
            bindings: ["taskIDs": taskIDs]
        )
        
        let validIDs = try result.column("validID", as: UUID.self)
        return Set(validIDs)
    }
    
    // MARK: - Hierarchical Queries
    
    /// Get complete task hierarchy efficiently
    public static func getTaskHierarchy(
        rootTaskID: UUID,
        context: GraphContext
    ) async throws -> TaskHierarchy {
        let result = try await context.raw(
            """
            MATCH (root:Task {id: $rootID})
            OPTIONAL MATCH path = (descendant:Task)-[:SubTaskOf*]->(root)
            WITH root,
                 collect(DISTINCT descendant) as descendants,
                 collect(length(path)) as depths
            RETURN root,
                   descendants,
                   depths
            """,
            bindings: ["rootID": rootTaskID]
        )
        
        guard let row = try result.mapFirst() else {
            throw MemoryError.taskNotFound(rootTaskID)
        }
        
        let decoder = KuzuDecoder()
        let root = try decoder.decode(
            Task.self,
            from: row["root"] as! [String: Any]
        )
        
        // Process descendants with depths
        let descendantDicts = row["descendants"] as? [[String: Any]] ?? []
        let depths = row["depths"] as? [Int64] ?? []
        
        let descendants = try zip(descendantDicts, depths).map { dict, depth in
            TaskWithDepth(
                task: try decoder.decode(Task.self, from: dict),
                depth: Int(depth)
            )
        }
        
        return TaskHierarchy(root: root, descendants: descendants)
    }
    
    /// Get all ancestors of a task
    public static func getTaskAncestors(
        taskID: UUID,
        context: GraphContext
    ) async throws -> [TaskWithDepth] {
        let result = try await context.raw(
            """
            MATCH path = (t:Task {id: $taskID})-[:SubTaskOf*]->(ancestor:Task)
            WITH ancestor, length(path) as depth
            RETURN ancestor, depth
            ORDER BY depth ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        let rows = try result.mapRows()
        let decoder = KuzuDecoder()
        
        return try rows.map { row in
            let task = try decoder.decode(
                Task.self,
                from: row["ancestor"] as! [String: Any]
            )
            let depth = (row["depth"] as? Int64).map(Int.init) ?? 0
            return TaskWithDepth(task: task, depth: depth)
        }
    }
    
    // MARK: - Dependency Analysis
    
    /// Get critical path (longest dependency chain) to a task
    public static func getCriticalPath(
        taskID: UUID,
        context: GraphContext
    ) async throws -> [Task] {
        let result = try await context.raw(
            """
            MATCH path = (start:Task)-[:Blocks*]->(end:Task {id: $taskID})
            WHERE start.status IN ['pending', 'inProgress']
            WITH path, length(path) as pathLength
            ORDER BY pathLength DESC
            LIMIT 1
            UNWIND nodes(path) as node
            WITH node, pathLength
            WHERE node.label = 'Task'
            RETURN node
            ORDER BY node.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.map(to: Task.self)
    }
    
    /// Find tasks with complex dependencies
    public static func findComplexDependencies(
        minBlockers: Int = 2,
        maxDepth: Int = 3,
        context: GraphContext
    ) async throws -> [(task: Task, blockerCount: Int, maxDepth: Int)] {
        let result = try await context.raw(
            """
            MATCH (t:Task)
            OPTIONAL MATCH (blocker:Task)-[:Blocks]->(t)
            WITH t, count(blocker) as blockerCount
            WHERE blockerCount >= $minBlockers
            OPTIONAL MATCH path = (upstream:Task)-[:Blocks*1..\(maxDepth)]->(t)
            WITH t, blockerCount, max(length(path)) as maxChainDepth
            WHERE maxChainDepth IS NOT NULL AND maxChainDepth <= $maxDepth
            RETURN t, blockerCount, maxChainDepth
            ORDER BY blockerCount DESC
            """,
            bindings: [
                "minBlockers": minBlockers,
                "maxDepth": maxDepth
            ]
        )
        
        let rows = try result.mapRows()
        let decoder = KuzuDecoder()
        
        return try rows.map { row in
            let task = try decoder.decode(
                Task.self,
                from: row["t"] as! [String: Any]
            )
            let blockerCount = (row["blockerCount"] as? Int64).map(Int.init) ?? 0
            let maxDepth = (row["maxChainDepth"] as? Int64).map(Int.init) ?? 0
            return (task: task, blockerCount: blockerCount, maxDepth: maxDepth)
        }
    }
    
    // MARK: - Batch Operations
    
    /// Update multiple tasks status efficiently
    public static func batchUpdateStatus(
        taskIDs: [UUID],
        newStatus: TaskStatus,
        context: GraphContext
    ) async throws -> Int {
        let result = try await context.raw(
            """
            UNWIND $taskIDs AS taskID
            MATCH (t:Task {id: taskID})
            SET t.status = $status, t.updatedAt = $updatedAt
            RETURN COUNT(t) as updated
            """,
            bindings: [
                "taskIDs": taskIDs,
                "status": newStatus.rawValue,
                "updatedAt": Date()
            ]
        )
        
        return Int(try result.mapFirstRequired(to: Int64.self, at: 0))
    }
    
    /// Batch create dependencies
    public static func batchCreateDependencies(
        dependencies: [(blockerID: UUID, blockedID: UUID)],
        context: GraphContext
    ) async throws {
        // Convert to format suitable for UNWIND
        let pairs = dependencies.map { dep in
            ["blockerID": dep.blockerID, "blockedID": dep.blockedID]
        }
        
        _ = try await context.raw(
            """
            UNWIND $pairs AS pair
            MATCH (blocker:Task {id: pair.blockerID}), (blocked:Task {id: pair.blockedID})
            WHERE blocker.id != blocked.id
            MERGE (blocker)-[r:Blocks]->(blocked)
            RETURN COUNT(r) as created
            """,
            bindings: ["pairs": pairs]
        )
    }
    
    // MARK: - Analytics Queries
    
    /// Get session statistics
    public static func getSessionStatistics(
        sessionID: UUID,
        context: GraphContext
    ) async throws -> SessionStatistics {
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            WITH s, t
            RETURN 
                COUNT(t) as totalTasks,
                COUNT(CASE WHEN t.status = 'done' THEN 1 END) as completedTasks,
                COUNT(CASE WHEN t.status = 'cancelled' THEN 1 END) as cancelledTasks,
                COUNT(CASE WHEN t.status = 'pending' THEN 1 END) as pendingTasks,
                COUNT(CASE WHEN t.status = 'inProgress' THEN 1 END) as inProgressTasks,
                AVG(t.difficulty) as avgDifficulty,
                COUNT(DISTINCT t.assignee) as uniqueAssignees
            """,
            bindings: ["sessionID": sessionID]
        )
        
        guard let row = try result.mapFirst() else {
            throw MemoryError.sessionNotFound(sessionID)
        }
        
        return SessionStatistics(
            sessionID: sessionID,
            totalTasks: Int((row["totalTasks"] as? Int64) ?? 0),
            completedTasks: Int((row["completedTasks"] as? Int64) ?? 0),
            cancelledTasks: Int((row["cancelledTasks"] as? Int64) ?? 0),
            pendingTasks: Int((row["pendingTasks"] as? Int64) ?? 0),
            inProgressTasks: Int((row["inProgressTasks"] as? Int64) ?? 0),
            averageDifficulty: (row["avgDifficulty"] as? Double) ?? 0,
            uniqueAssignees: Int((row["uniqueAssignees"] as? Int64) ?? 0)
        )
    }
    
    /// Find bottleneck tasks (blocking many others)
    public static func findBottleneckTasks(
        minBlocked: Int = 3,
        context: GraphContext
    ) async throws -> [(task: Task, blockedCount: Int)] {
        let result = try await context.raw(
            """
            MATCH (t:Task)-[:Blocks]->(blocked:Task)
            WHERE t.status IN ['pending', 'inProgress']
            WITH t, count(DISTINCT blocked) as blockedCount
            WHERE blockedCount >= $minBlocked
            RETURN t, blockedCount
            ORDER BY blockedCount DESC
            """,
            bindings: ["minBlocked": minBlocked]
        )
        
        let rows = try result.mapRows()
        let decoder = KuzuDecoder()
        
        return try rows.map { row in
            let task = try decoder.decode(
                Task.self,
                from: row["t"] as! [String: Any]
            )
            let blockedCount = Int((row["blockedCount"] as? Int64) ?? 0)
            return (task: task, blockedCount: blockedCount)
        }
    }
}

// MARK: - Supporting Types

public struct TaskHierarchy: Sendable {
    public let root: Task
    public let descendants: [TaskWithDepth]
    
    public init(root: Task, descendants: [TaskWithDepth]) {
        self.root = root
        self.descendants = descendants
    }
}

public struct SessionStatistics: Sendable {
    public let sessionID: UUID
    public let totalTasks: Int
    public let completedTasks: Int
    public let cancelledTasks: Int
    public let pendingTasks: Int
    public let inProgressTasks: Int
    public let averageDifficulty: Double
    public let uniqueAssignees: Int
    
    public var completionRate: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }
    
    public var activeTasks: Int {
        return pendingTasks + inProgressTasks
    }
}