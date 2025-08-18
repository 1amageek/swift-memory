import Foundation
import Kuzu
import KuzuSwiftExtension

/// Improved DependencyManager using Query DSL and Beta 2 features
public actor DependencyManagerV2 {
    public static let shared = DependencyManagerV2()
    
    private init() {}
    
    // MARK: - Dependency Operations
    
    public func add(blockerID: UUID, blockedID: UUID) async throws {
        // Check for self-loop first
        guard blockerID != blockedID else {
            throw MemoryError.invalidInput(
                field: "dependency",
                reason: "Task cannot block itself (self-loop detected)"
            )
        }
        
        let context = try await SwiftMemoryContext.shared.context()
        
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
            
            // Check for circular dependency using Beta 2's mapFirstRequired
            let result = try tx.raw(
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
            
            // Create Blocks relationship using MERGE
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
    
    public func remove(blockerID: UUID, blockedID: UUID) async throws {
        let context = try await SwiftMemoryContext.shared.context()
        
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
    
    // MARK: - Query Operations with Beta 2 Features
    
    public func getBlockers(taskID: UUID) async throws -> [Task] {
        let context = try await SwiftMemoryContext.shared.context()
        
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            RETURN blocker
            ORDER BY blocker.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        // Beta 2's map(to:) automatically handles KuzuNode extraction
        return try result.map(to: Task.self)
    }
    
    public func getBlocking(taskID: UUID) async throws -> [Task] {
        let context = try await SwiftMemoryContext.shared.context()
        
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
    
    public func isTaskBlocked(taskID: UUID) async throws -> Bool {
        let context = try await SwiftMemoryContext.shared.context()
        
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
    
    public func getDependencyChain(taskID: UUID) async throws -> DependencyChain {
        let context = try await SwiftMemoryContext.shared.context()
        
        // Get upstream dependencies
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
            return TaskWithDepth(task: task, depth: depth)
        }
        
        // Get downstream dependencies
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
            return TaskWithDepth(task: task, depth: depth)
        }
        
        return DependencyChain(
            taskID: taskID,
            upstream: upstream,
            downstream: downstream
        )
    }
}