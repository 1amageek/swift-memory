import Foundation
import Kuzu
import KuzuSwiftExtension

/// Kuzu-based implementation of DependencyRepository
public actor KuzuDependencyRepository: DependencyRepository {
    private let context: GraphContext
    
    public init(context: GraphContext) {
        self.context = context
    }
    
    public func add(blockerID: String, blockedID: String) async throws {
        // Check for self-loop first
        guard blockerID != blockedID else {
            throw MemoryError.invalidInput(
                field: "dependency",
                reason: "Task cannot block itself (self-loop detected)"
            )
        }
        
        // Use transaction for atomicity
        try await context.withTransaction { tx in
            // Verify both tasks exist
            let blockerResult = try tx.raw(
                "MATCH (t:Task {id: $id}) RETURN t",
                bindings: ["id": blockerID]
            )
            
            guard blockerResult.hasNext() else {
                throw MemoryError.taskNotFound(blockerID)
            }
            
            let blockedResult = try tx.raw(
                "MATCH (t:Task {id: $id}) RETURN t",
                bindings: ["id": blockedID]
            )
            
            guard blockedResult.hasNext() else {
                throw MemoryError.taskNotFound(blockedID)
            }
            
            // Check for circular dependency
            let cycleResult = try tx.raw(
                """
                MATCH p = (blocked:Task {id: $blockedID})-[:Blocks*]->(blocker:Task {id: $blockerID})
                RETURN COUNT(p) > 0 AS hasCycle
                """,
                bindings: ["blockedID": blockedID, "blockerID": blockerID]
            )
            
            let hasCycle = try cycleResult.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasCycle {
                throw MemoryError.circularDependency(blocker: blockerID, blocked: blockedID)
            }
            
            // Create Blocks relationship using MERGE to prevent duplicates
            _ = try tx.raw(
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
    
    public func getBlockers(taskID: String) async throws -> [Task] {
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            RETURN blocker
            ORDER BY blocker.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        // Beta 2: Automatic KuzuNode to Task mapping
        return try result.map(to: Task.self)
    }
    
    public func getBlocking(taskID: String) async throws -> [Task] {
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
    
    public func isTaskBlocked(taskID: String) async throws -> Bool {
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
    
    public func getDependencyChain(taskID: String) async throws -> DependencyChain {
        // Get upstream dependencies with depth
        let upstreamResult = try await context.raw(
            """
            MATCH path = (blocker:Task)-[:Blocks*]->(blocked:Task {id: $taskID})
            WITH blocker, min(length(path)) as depth
            RETURN blocker, depth
            ORDER BY depth DESC
            """,
            bindings: ["taskID": taskID]
        )
        
        // Use Beta 2's enhanced result mapping
        let upstreamRows = try upstreamResult.mapRows()
        let decoder = KuzuDecoder()
        let upstream = try upstreamRows.map { row in
            // Beta 2 automatically extracts node properties from "blocker" column
            let task = try decoder.decode(Task.self, from: row["blocker"] as! [String: Any])
            let depth = (row["depth"] as? Int64).map(Int.init) ?? 0
            return DependencyChainItem(task: task, depth: depth)
        }
        
        // Get downstream dependencies with depth
        let downstreamResult = try await context.raw(
            """
            MATCH path = (blocker:Task {id: $taskID})-[:Blocks*]->(blocked:Task)
            WITH blocked, min(length(path)) as depth
            RETURN blocked, depth
            ORDER BY depth ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        let downstreamRows = try downstreamResult.mapRows()
        let downstream = try downstreamRows.map { row in
            let task = try decoder.decode(Task.self, from: row["blocked"] as! [String: Any])
            let depth = (row["depth"] as? Int64).map(Int.init) ?? 0
            return DependencyChainItem(task: task, depth: depth)
        }
        
        return DependencyChain(
            taskID: taskID,
            upstream: upstream,
            downstream: downstream
        )
    }
    
    public func wouldCreateCycle(blockerID: String, blockedID: String) async throws -> Bool {
        // Check if there's already a path from blocked to blocker
        let result = try await context.raw(
            """
            MATCH p = (blocked:Task {id: $blockedID})-[:Blocks*]->(blocker:Task {id: $blockerID})
            RETURN COUNT(p) > 0 AS hasCycle
            """,
            bindings: ["blockedID": blockedID, "blockerID": blockerID]
        )
        
        return try result.mapFirstRequired(to: Bool.self, at: 0)
    }
}