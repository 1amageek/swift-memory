import Foundation
import Kuzu
import KuzuSwiftExtension

/// Kuzu-based implementation of TaskRepository
public actor KuzuTaskRepository: TaskRepository {
    private let context: GraphContext
    
    public init(context: GraphContext) {
        self.context = context
    }
    
    public func create(_ task: Task, sessionID: UUID, parentTaskID: UUID?) async throws -> Task {
        // Save the task node first
        let savedTask = try await context.save(task)
        
        return try await context.withTransaction { tx in
            
            // Get next order for HasTask edge
            let orderResult = try tx.raw(
                """
                MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
                RETURN max(r.`order`) as maxOrder
                """,
                bindings: ["sessionID": sessionID]
            )
            
            let maxOrder: Int
            if let orderValue = try? orderResult.mapFirstRequired(to: Int64.self, at: 0) {
                maxOrder = Int(orderValue)
            } else {
                maxOrder = 0
            }
            let nextOrder = maxOrder + 1
            
            // Create HasTask relationship
            _ = try tx.raw(
                """
                MATCH (s:Session {id: $sessionID}), (t:Task {id: $taskID})
                MERGE (s)-[r:HasTask]->(t)
                SET r.`order` = $orderValue
                RETURN r
                """,
                bindings: [
                    "sessionID": sessionID,
                    "taskID": savedTask.id,
                    "orderValue": nextOrder
                ]
            )
            
            // Handle parent relationship if specified
            if let parentID = parentTaskID {
                // Check for self-loop
                guard parentID != savedTask.id else {
                    throw MemoryError.invalidInput(
                        field: "parentTaskID",
                        reason: "Task cannot be its own parent"
                    )
                }
                
                // Check for cycle
                let cycleResult = try tx.raw(
                    """
                    MATCH p = (parent:Task {id: $parentID})-[:SubTaskOf*]->(child:Task {id: $childID})
                    RETURN COUNT(p) > 0 AS hasCycle
                    """,
                    bindings: ["parentID": parentID, "childID": savedTask.id]
                )
                
                let hasCycle = try cycleResult.mapFirstRequired(to: Bool.self, at: 0)
                
                if hasCycle {
                    throw MemoryError.circularDependency(
                        blocker: parentID,
                        blocked: savedTask.id
                    )
                }
                
                // Create parent relationship
                _ = try tx.raw(
                    """
                    MATCH (child:Task {id: $childID}), (parent:Task {id: $parentID})
                    MERGE (child)-[r:SubTaskOf]->(parent)
                    RETURN r
                    """,
                    bindings: ["childID": savedTask.id, "parentID": parentID]
                )
            }
            
            return savedTask
        }
    }
    
    public func find(id: UUID) async throws -> Task? {
        return try await context.fetchOne(Task.self, id: id)
    }
    
    public func findAll(filter: TaskFilter?) async throws -> [Task] {
        guard let filter = filter else {
            return try await context.fetch(Task.self)
        }
        
        if let sessionID = filter.sessionID {
            return try await findTasksInSession(sessionID: sessionID, filter: filter)
        } else if let parentID = filter.parentTaskID {
            return try await findSubtasks(parentID: parentID)
        } else {
            return try await findTasksGeneral(filter: filter)
        }
    }
    
    private func findTasksInSession(sessionID: UUID, filter: TaskFilter) async throws -> [Task] {
        var query = "MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)"
        var bindings: [String: any Sendable] = ["sessionID": sessionID]
        var conditions: [String] = []
        
        if let status = filter.status {
            conditions.append("t.status = $status")
            bindings["status"] = status.rawValue
        }
        
        if let assignee = filter.assignee {
            conditions.append("t.assignee = $assignee")
            bindings["assignee"] = assignee
        }
        
        if let maxDifficulty = filter.difficultyMax {
            conditions.append("t.difficulty <= $maxDifficulty")
            bindings["maxDifficulty"] = maxDifficulty
        }
        
        if filter.readyOnly {
            conditions.append("t.status IN ['pending', 'inProgress']")
            conditions.append("""
                NOT EXISTS {
                    MATCH (blocker:Task)-[:Blocks]->(t)
                    WHERE blocker.status IN ['pending', 'inProgress']
                }
                """)
        }
        
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        query += " RETURN t ORDER BY r.`order` ASC"
        
        if let limit = filter.limit {
            query += " LIMIT \(limit)"
        }
        
        let result = try await context.raw(query, bindings: bindings)
        return try result.map(to: Task.self)
    }
    
    private func findSubtasks(parentID: UUID) async throws -> [Task] {
        let result = try await context.raw(
            """
            MATCH (t:Task)-[:SubTaskOf]->(parent:Task {id: $parentID})
            RETURN t
            ORDER BY t.createdAt ASC
            """,
            bindings: ["parentID": parentID]
        )
        return try result.map(to: Task.self)
    }
    
    private func findTasksGeneral(filter: TaskFilter) async throws -> [Task] {
        var query = "MATCH (t:Task)"
        var bindings: [String: any Sendable] = [:]
        var conditions: [String] = []
        
        if let status = filter.status {
            conditions.append("t.status = $status")
            bindings["status"] = status.rawValue
        }
        
        if let assignee = filter.assignee {
            conditions.append("t.assignee = $assignee")
            bindings["assignee"] = assignee
        }
        
        if let maxDifficulty = filter.difficultyMax {
            conditions.append("t.difficulty <= $maxDifficulty")
            bindings["maxDifficulty"] = maxDifficulty
        }
        
        if filter.readyOnly {
            conditions.append("t.status IN ['pending', 'inProgress']")
            conditions.append("""
                NOT EXISTS {
                    MATCH (blocker:Task)-[:Blocks]->(t)
                    WHERE blocker.status IN ['pending', 'inProgress']
                }
                """)
        }
        
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        query += " RETURN t ORDER BY t.createdAt DESC"
        
        if let limit = filter.limit {
            query += " LIMIT \(limit)"
        }
        
        let result = try await context.raw(query, bindings: bindings)
        return try result.map(to: Task.self)
    }
    
    public func update(_ task: Task) async throws -> Task {
        // Validate cancelReason consistency
        if task.status == .cancelled && task.cancelReason == nil {
            throw MemoryError.invalidInput(
                field: "cancelReason",
                reason: "Cancellation reason required when status is 'cancelled'"
            )
        }
        
        if task.cancelReason != nil && task.status != .cancelled {
            throw MemoryError.invalidInput(
                field: "cancelReason",
                reason: "cancelReason is only allowed when status is 'cancelled'"
            )
        }
        
        return try await context.save(task)
    }
    
    public func delete(id: UUID, cascade: Bool) async throws {
        if cascade {
            // Cascade delete all subtasks
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*1..]->(t)
                WHERE descendant IS NOT NULL
                DETACH DELETE descendant
                """,
                bindings: ["taskID": id]
            )
            
            // Delete the task itself
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                DETACH DELETE t
                """,
                bindings: ["taskID": id]
            )
        } else {
            // Simple delete
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                DETACH DELETE t
                """,
                bindings: ["taskID": id]
            )
        }
    }
    
    public func setParent(taskID: UUID, parentID: UUID?) async throws {
        if let parentID = parentID {
            // Check for self-loop
            guard parentID != taskID else {
                throw MemoryError.invalidInput(
                    field: "parentTaskID",
                    reason: "Task cannot be its own parent"
                )
            }
            
            // Check for cycle
            let cycleResult = try await context.raw(
                """
                MATCH p = (parent:Task {id: $parentID})-[:SubTaskOf*]->(child:Task {id: $childID})
                RETURN COUNT(p) > 0 AS hasCycle
                """,
                bindings: ["parentID": parentID, "childID": taskID]
            )
            
            let hasCycle = try cycleResult.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasCycle {
                throw MemoryError.circularDependency(blocker: parentID, blocked: taskID)
            }
            
            // Remove existing parent relationship
            _ = try await context.raw(
                """
                MATCH (child:Task {id: $childID})-[r:SubTaskOf]->(:Task)
                DELETE r
                """,
                bindings: ["childID": taskID]
            )
            
            // Create new parent relationship
            _ = try await context.raw(
                """
                MATCH (child:Task {id: $childID}), (parent:Task {id: $parentID})
                MERGE (child)-[r:SubTaskOf]->(parent)
                RETURN r
                """,
                bindings: ["childID": taskID, "parentID": parentID]
            )
        } else {
            // Remove parent relationship
            _ = try await context.raw(
                """
                MATCH (child:Task {id: $childID})-[r:SubTaskOf]->(:Task)
                DELETE r
                """,
                bindings: ["childID": taskID]
            )
        }
    }
    
    public func getParent(taskID: UUID) async throws -> Task? {
        let result = try await context.raw(
            """
            MATCH (child:Task {id: $taskID})-[:SubTaskOf]->(parent:Task)
            RETURN parent
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.mapFirst(to: Task.self)
    }
    
    public func getChildren(taskID: UUID) async throws -> [Task] {
        let result = try await context.raw(
            """
            MATCH (child:Task)-[:SubTaskOf]->(parent:Task {id: $taskID})
            RETURN child
            ORDER BY child.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        return try result.map(to: Task.self)
    }
    
    public func reorder(sessionID: UUID, orderedTaskIDs: [UUID]) async throws {
        // Validate all tasks exist in the session using UNWIND
        let validationResult = try await context.raw(
            """
            UNWIND $taskIDs AS taskID
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task {id: taskID})
            RETURN collect(t.id) as validIDs
            """,
            bindings: ["sessionID": sessionID, "taskIDs": orderedTaskIDs]
        )
        
        let validIDs: Set<UUID>
        if let row = try validationResult.mapFirst() {
            let idArray = row["validIDs"] as? [Any] ?? []
            validIDs = Set(idArray.compactMap { id in
                if let uuidString = id as? String {
                    return UUID(uuidString: uuidString)
                } else if let uuid = id as? UUID {
                    return uuid
                }
                return nil
            })
        } else {
            validIDs = []
        }
        
        // Check for missing tasks
        let requestedIDs = Set(orderedTaskIDs)
        let missingIDs = requestedIDs.subtracting(validIDs)
        if !missingIDs.isEmpty {
            throw MemoryError.taskNotFound(missingIDs.first!)
        }
        
        // Check for duplicate IDs
        if orderedTaskIDs.count != requestedIDs.count {
            throw MemoryError.invalidInput(
                field: "orderedTaskIDs",
                reason: "Duplicate task IDs provided"
            )
        }
        
        // Update all orders in a single query using UNWIND
        let pairs: [[String: any Sendable]] = orderedTaskIDs.enumerated().map { index, taskID in
            ["id": taskID, "orderValue": index + 1]
        }
        
        _ = try await context.raw(
            """
            UNWIND $pairs AS pair
            MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task {id: pair.id})
            SET r.`order` = pair.orderValue
            RETURN COUNT(*) as updated
            """,
            bindings: ["sessionID": sessionID, "pairs": pairs]
        )
    }
    
    public func batchUpdate(taskIDs: [UUID], updates: TaskUpdateData) async throws -> [Task] {
        var updatedTasks: [Task] = []
        
        // Validate difficulty once if provided
        if let difficulty = updates.difficulty {
            guard (1...5).contains(difficulty) else {
                throw MemoryError.invalidDifficulty(difficulty)
            }
        }
        
        for taskID in taskIDs {
            guard var task = try await find(id: taskID) else {
                continue  // Skip non-existent tasks
            }
            
            // Apply updates
            if let title = updates.title { task.title = title }
            if let description = updates.description { task.description = description }
            if let status = updates.status { task.status = status }
            if let assignee = updates.assignee { task.assignee = assignee }
            if let difficulty = updates.difficulty { task.difficulty = difficulty }
            if let cancelReason = updates.cancelReason { task.cancelReason = cancelReason }
            
            task.updatedAt = Date()
            
            let updated = try await update(task)
            updatedTasks.append(updated)
        }
        
        if updatedTasks.isEmpty && !taskIDs.isEmpty {
            throw MemoryError.databaseError("Failed to update any tasks")
        }
        
        return updatedTasks
    }
}