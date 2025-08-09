import Foundation
import Kuzu
import KuzuSwiftExtension

public actor DependencyManager {
    public static let shared = DependencyManager()
    
    private init() {}
    
    // MARK: - Dependency Operations
    
    public func add(blockerID: UUID, blockedID: UUID) async throws {
        let context = try await GraphDatabaseSetup.shared.context()
        
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
        
        var hasCycle = false
        if result.hasNext(),
           let tuple = try result.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let cycleValue = dict["hasCycle"] as? Bool {
            hasCycle = cycleValue
        }
        
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
    
    public func remove(blockerID: UUID, blockedID: UUID) async throws {
        let context = try await GraphDatabaseSetup.shared.context()
        
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
    
    public func getBlockers(taskID: UUID) async throws -> [Task] {
        let context = try await GraphDatabaseSetup.shared.context()
        
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            RETURN blocker
            ORDER BY blocker.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        var blockers: [Task] = []
        while result.hasNext() {
            if let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let blockerDict = dict["blocker"] as? [String: Any?] {
                let blocker = try KuzuDecoder().decode(Task.self, from: blockerDict)
                blockers.append(blocker)
            }
        }
        return blockers
    }
    
    public func getBlocking(taskID: UUID) async throws -> [Task] {
        let context = try await GraphDatabaseSetup.shared.context()
        
        let result = try await context.raw(
            """
            MATCH (blocker:Task {id: $taskID})-[:Blocks]->(blocked:Task)
            RETURN blocked
            ORDER BY blocked.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        var blocked: [Task] = []
        while result.hasNext() {
            if let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let blockedDict = dict["blocked"] as? [String: Any?] {
                let task = try KuzuDecoder().decode(Task.self, from: blockedDict)
                blocked.append(task)
            }
        }
        return blocked
    }
    
    public func isTaskBlocked(taskID: UUID) async throws -> Bool {
        let context = try await GraphDatabaseSetup.shared.context()
        
        // Only consider pending or inProgress tasks as active blockers
        let result = try await context.raw(
            """
            MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
            WHERE blocker.status IN ['pending', 'inProgress']
            RETURN COUNT(blocker) > 0 AS isBlocked
            """,
            bindings: ["taskID": taskID]
        )
        
        if result.hasNext(),
           let tuple = try result.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let isBlocked = dict["isBlocked"] as? Bool {
            return isBlocked
        }
        return false
    }
    
    public func getDependencyChain(taskID: UUID) async throws -> DependencyChain {
        let context = try await GraphDatabaseSetup.shared.context()
        
        // Get all upstream dependencies with DISTINCT and min depth
        let upstreamResult = try await context.raw(
            """
            MATCH path = (blocker:Task)-[:Blocks*]->(blocked:Task {id: $taskID})
            WITH blocker, min(length(path)) as depth
            RETURN blocker, depth
            ORDER BY depth DESC
            """,
            bindings: ["taskID": taskID]
        )
        
        // Convert upstream rows to TaskWithDepth
        let decoder = KuzuDecoder()
        var upstreamData: [TaskWithDepth] = []
        while upstreamResult.hasNext() {
            if let tuple = try upstreamResult.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let blockerDict = dict["blocker"] as? [String: Any?],
               let task = try? decoder.decode(Task.self, from: blockerDict),
               let depth = dict["depth"] as? Int64 {
                upstreamData.append(TaskWithDepth(task: task, depth: Int(depth)))
            }
        }
        
        // Get all downstream dependencies with DISTINCT and min depth
        let downstreamResult = try await context.raw(
            """
            MATCH path = (blocker:Task {id: $taskID})-[:Blocks*]->(blocked:Task)
            WITH blocked, min(length(path)) as depth
            RETURN blocked, depth
            ORDER BY depth ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        // Convert downstream rows to TaskWithDepth
        var downstreamData: [TaskWithDepth] = []
        while downstreamResult.hasNext() {
            if let tuple = try downstreamResult.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let blockedDict = dict["blocked"] as? [String: Any?],
               let task = try? decoder.decode(Task.self, from: blockedDict),
               let depth = dict["depth"] as? Int64 {
                downstreamData.append(TaskWithDepth(task: task, depth: Int(depth)))
            }
        }
        
        return DependencyChain(
            taskID: taskID,
            upstream: upstreamData,
            downstream: downstreamData
        )
    }
    
    // MARK: - Private Helpers (removed - now using KuzuSwiftExtension declarative APIs)
}

// MARK: - Supporting Types

public struct DependencyChain: Codable, Sendable {
    public let taskID: UUID
    public let upstream: [TaskWithDepth]
    public let downstream: [TaskWithDepth]
    
    public var maxUpstreamDepth: Int {
        upstream.map { $0.depth }.max() ?? 0
    }
    
    public var maxDownstreamDepth: Int {
        downstream.map { $0.depth }.max() ?? 0
    }
}

public struct TaskWithDepth: Codable, Sendable {
    public let task: Task
    public let depth: Int
    
    public init(task: Task, depth: Int) {
        self.task = task
        self.depth = depth
    }
}
