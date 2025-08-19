import Foundation
import Kuzu
import KuzuSwiftExtension

public actor TaskManager {
    public static let shared = TaskManager()
    
    private let contextProvider: DatabaseContextProvider
    
    public init(contextProvider: DatabaseContextProvider = DefaultDatabaseProvider.shared) {
        self.contextProvider = contextProvider
    }
    
    private init() {
        self.contextProvider = DefaultDatabaseProvider.shared
    }
    
    // MARK: - CRUD Operations
    
    public func create(
        sessionID: String,
        title: String,
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: String? = nil
    ) async throws -> Task {
        // Validate inputs first (before transaction)
        guard (1...5).contains(difficulty) else {
            throw MemoryError.invalidDifficulty(difficulty)
        }
        
        // Execute the entire creation in a transaction for atomicity
        return try await TransactionManager.executeInTransaction(
            using: contextProvider
        ) { context in
            // Validate session exists
            guard let _ = try await context.fetchOne(Session.self, id: sessionID) else {
                throw MemoryError.sessionNotFound(sessionID)
            }
            
            // Validate parent if specified
            if let parentTaskID = parentTaskID {
                guard let _ = try await context.fetchOne(Task.self, id: parentTaskID) else {
                    throw MemoryError.taskNotFound(parentTaskID)
                }
            }
            
            // Create task object
            let task = Task(
                title: title,
                description: description,
                assignee: assignee,
                difficulty: difficulty
            )
            
            // Save task
            let savedTask = try await context.save(task)
            
            // Get next order for HasTask edge
            let maxOrderResult = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
                RETURN max(r.`order`) as maxOrder
                """,
                bindings: ["sessionID": sessionID]
            )
            
            let maxOrder: Int
            if let orderValue = try? maxOrderResult.mapFirstRequired(to: Int64.self, at: 0) {
                maxOrder = Int(orderValue)
            } else {
                maxOrder = 0
            }
            let nextOrder = maxOrder + 1
            
            // Create HasTask relationship using MERGE to ensure (s,t) uniqueness
            _ = try await context.raw(
                """
                MATCH (s:Session {id: $sessionID}), (t:Task {id: $taskID})
                MERGE (s)-[r:HasTask]->(t)
                SET r.`order` = $orderValue
                RETURN r
                """,
                bindings: ["sessionID": sessionID, "taskID": savedTask.id, "orderValue": nextOrder]
            )
            
            // Handle parent relationship if specified
            if let parentTaskID = parentTaskID {
                // Check for self-loop (task cannot be its own parent)
                guard parentTaskID != savedTask.id else {
                    throw MemoryError.invalidInput(
                        field: "parentTaskID",
                        reason: "Task cannot be its own parent (self-loop detected)"
                    )
                }
                
                // Check for cycle - would making parentTaskID the parent of this task create a cycle?
                let cycleResult = try await context.raw(
                    """
                    MATCH p = (parent:Task {id: $parentID})-[:SubTaskOf*]->(child:Task {id: $childID})
                    RETURN COUNT(p) > 0 AS hasCycle
                    """,
                    bindings: ["parentID": parentTaskID, "childID": savedTask.id]
                )
                
                let hasCycle = try cycleResult.mapFirstRequired(to: Bool.self, at: 0)
                
                if hasCycle {
                    throw MemoryError.circularDependency(blocker: parentTaskID, blocked: savedTask.id)
                }
                
                // Create parent relationship using MERGE
                _ = try await context.raw(
                    """
                    MATCH (child:Task {id: $childID}), (parent:Task {id: $parentID})
                    MERGE (child)-[r:SubTaskOf]->(parent)
                    RETURN r
                    """,
                    bindings: ["childID": savedTask.id, "parentID": parentTaskID]
                )
            }
            
            return savedTask
        }
    }
    
    public func get(id: String) async throws -> Task {
        let context = try await contextProvider.context()
        guard let task = try await context.fetchOne(Task.self, id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        return task
    }
    
    public func list(
        sessionID: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        parentTaskID: String? = nil,
        readyOnly: Bool = false,
        difficultyMax: Int? = nil
    ) async throws -> [Task] {
        let context = try await contextProvider.context()
        
        if let sessionID = sessionID {
            // Tasks for a specific session
            var query = """
                MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
                """
            
            var whereConditions: [String] = []
            var bindings: [String: any Sendable] = ["sessionID": sessionID]
            
            if let status = status {
                whereConditions.append("t.status = $status")
                bindings["status"] = status.rawValue
            }
            
            if let assignee = assignee {
                whereConditions.append("t.assignee = $assignee")
                bindings["assignee"] = assignee
            }
            
            if let difficultyMax = difficultyMax {
                whereConditions.append("t.difficulty <= $difficultyMax")
                bindings["difficultyMax"] = difficultyMax
            }
            
            if readyOnly {
                whereConditions.append("t.status IN ['pending', 'inProgress']")
                whereConditions.append("NOT EXISTS { MATCH (blocker:Task)-[:Blocks]->(t) WHERE blocker.status IN ['pending', 'inProgress'] }")
            }
            
            if !whereConditions.isEmpty {
                query += " WHERE " + whereConditions.joined(separator: " AND ")
            }
            
            query += " RETURN t ORDER BY r.`order` ASC"
            
            let result = try await context.raw(query, bindings: bindings)
            return try result.map(to: Task.self)
            
        } else if let parentTaskID = parentTaskID {
            // Get subtasks
            let result = try await context.raw(
                """
                MATCH (t:Task)-[:SubTaskOf]->(parent:Task {id: $parentID})
                RETURN t
                ORDER BY t.createdAt ASC
                """,
                bindings: ["parentID": parentTaskID]
            )
            return try result.map(to: Task.self)
            
        } else {
            // General task listing
            if status == nil && assignee == nil && difficultyMax == nil && !readyOnly {
                // Simple case - fetch all tasks
                return try await context.fetch(Task.self)
            } else {
                // Build filtered query
                var query = "MATCH (t:Task)"
                var whereConditions: [String] = []
                var bindings: [String: any Sendable] = [:]
                
                if let status = status {
                    whereConditions.append("t.status = $status")
                    bindings["status"] = status.rawValue
                }
                
                if let assignee = assignee {
                    whereConditions.append("t.assignee = $assignee")
                    bindings["assignee"] = assignee
                }
                
                if let difficultyMax = difficultyMax {
                    whereConditions.append("t.difficulty <= $difficultyMax")
                    bindings["difficultyMax"] = difficultyMax
                }
                
                if readyOnly {
                    whereConditions.append("t.status IN ['pending', 'inProgress']")
                    whereConditions.append("NOT EXISTS { MATCH (blocker:Task)-[:Blocks]->(t) WHERE blocker.status IN ['pending', 'inProgress'] }")
                }
                
                if !whereConditions.isEmpty {
                    query += " WHERE " + whereConditions.joined(separator: " AND ")
                }
                
                query += " RETURN t ORDER BY t.createdAt DESC"
                
                let result = try await context.raw(query, bindings: bindings)
                return try result.map(to: Task.self)
            }
        }
    }
    
    public func update(
        id: String,
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        difficulty: Int? = nil,
        cancelReason: String? = nil,
        parentTaskID: String? = nil
    ) async throws -> Task {
        let context = try await contextProvider.context()
        
        guard var task = try await context.fetchOne(Task.self, id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        
        // Update fields with validation
        if let title = title { task.title = title }
        if let description = description { task.description = description }
        if let status = status { task.status = status }
        if let assignee = assignee { task.assignee = assignee }
        if let difficulty = difficulty {
            guard (1...5).contains(difficulty) else {
                throw MemoryError.invalidDifficulty(difficulty)
            }
            task.difficulty = difficulty
        }
        
        // Validate cancelReason consistency
        if task.status == .cancelled && cancelReason == nil && task.cancelReason == nil {
            throw MemoryError.databaseError("Cancellation reason required when status is 'cancelled'")
        }
        
        if let cancelReason = cancelReason {
            if task.status != .cancelled {
                throw MemoryError.databaseError("cancelReason is only allowed when status is 'cancelled'")
            }
            task.cancelReason = cancelReason
        }
        
        task.updatedAt = Date()
        
        // Update task
        let updated = try await context.save(task)
        
        // Update parent relationship if specified
        if let parentTaskID = parentTaskID {
            // Check for self-loop (task cannot be its own parent)
            guard parentTaskID != id else {
                throw MemoryError.invalidInput(
                    field: "parentTaskID",
                    reason: "Task cannot be its own parent (self-loop detected)"
                )
            }
            
            // Verify new parent exists
            guard let _ = try await context.fetchOne(Task.self, id: parentTaskID) else {
                throw MemoryError.taskNotFound(parentTaskID)
            }
            
            // Check for cycle - would making parentTaskID the parent create a cycle?
            let cycleResult = try await context.raw(
                """
                MATCH p = (parent:Task {id: $parentID})-[:SubTaskOf*]->(child:Task {id: $childID})
                RETURN COUNT(p) > 0 AS hasCycle
                """,
                bindings: ["parentID": parentTaskID, "childID": id]
            )
            
            let hasCycle = try cycleResult.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasCycle {
                throw MemoryError.circularDependency(blocker: parentTaskID, blocked: id)
            }
            
            // Remove existing parent relationship
            _ = try await context.raw(
                """
                MATCH (child:Task {id: $childID})-[r:SubTaskOf]->(:Task)
                WITH r
                DELETE r
                RETURN COUNT(*) as deleted
                """,
                bindings: ["childID": id]
            )
            
            // Create new parent relationship using MERGE
            _ = try await context.raw(
                """
                MATCH (child:Task {id: $childID}), (parent:Task {id: $parentID})
                MERGE (child)-[r:SubTaskOf]->(parent)
                RETURN r
                """,
                bindings: ["childID": id, "parentID": parentTaskID]
            )
        }
        
        return updated
    }
    
    public func reorder(sessionID: String, orderedIds: [String]) async throws {
        let context = try await contextProvider.context()
        
        // Verify session exists
        guard let _ = try await context.fetchOne(Session.self, id: sessionID) else {
            throw MemoryError.sessionNotFound(sessionID)
        }
        
        // Batch validate all tasks exist in the session
        let validationResult = try await context.raw(
            """
            UNWIND $taskIDs AS taskID
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task {id: taskID})
            RETURN collect(t.id) as validIDs
            """,
            bindings: ["sessionID": sessionID, "taskIDs": orderedIds]
        )
        
        let validIDs: Set<String>
        if let row = try validationResult.mapFirst() {
            let idArray = row["validIDs"] as? [Any] ?? []
            validIDs = Set(idArray.compactMap { $0 as? String })
        } else {
            validIDs = []
        }
        
        // Check for missing tasks
        let requestedIDs = Set(orderedIds)
        let missingIDs = requestedIDs.subtracting(validIDs)
        if !missingIDs.isEmpty {
            throw MemoryError.taskNotFound(missingIDs.first!)
        }
        
        // Check for duplicate IDs in the input
        if orderedIds.count != requestedIDs.count {
            throw MemoryError.invalidInput(
                field: "orderedIds",
                reason: "Duplicate task IDs provided"
            )
        }
        
        // Prepare pairs for batch update
        let pairs: [[String: any Sendable]] = orderedIds.enumerated().map { index, taskID in
            ["id": taskID, "orderValue": index + 1]
        }
        
        // Update all orders in a single query using UNWIND
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
    
    public func delete(id: String, cascade: Bool = false) async throws {
        let context = try await contextProvider.context()
        
        // Verify task exists
        guard let _ = try await context.fetchOne(Task.self, id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        
        if cascade {
            // Cascade delete: delete all subtasks first
            // Use [:SubTaskOf*1..] to match only descendants (depth 1 or more)
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*1..]->(t)
                WHERE descendant IS NOT NULL
                DETACH DELETE descendant
                """,
                bindings: ["taskID": id]
            )
        } else {
            // Check if task has subtasks
            let subtaskResult = try await context.raw(
                """
                MATCH (subtask:Task)-[:SubTaskOf]->(parent:Task {id: $taskID})
                RETURN COUNT(subtask) > 0 AS hasSubtasks
                """,
                bindings: ["taskID": id]
            )
            
            let hasSubtasks = try subtaskResult.mapFirstRequired(to: Bool.self, at: 0)
            
            if hasSubtasks {
                throw MemoryError.databaseError("Cannot delete task with subtasks. Use cascade option to delete all subtasks.")
            }
        }
        
        // Delete the task using raw query (will also delete all relationships)
        _ = try await context.raw(
            "MATCH (t:Task {id: $taskID}) DETACH DELETE t",
            bindings: ["taskID": id]
        )
    }
    
    // MARK: - Batch Operations
    
    public func updateBatch(
        taskIDs: [String],
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        difficulty: Int? = nil,
        cancelReason: String? = nil
    ) async throws -> [Task] {
        var updatedTasks: [Task] = []
        
        // Validate difficulty once if provided
        if let difficulty = difficulty {
            guard (1...5).contains(difficulty) else {
                throw MemoryError.invalidDifficulty(difficulty)
            }
        }
        
        // Update each task
        for taskID in taskIDs {
            do {
                let updated = try await update(
                    id: taskID,
                    title: title,
                    description: description,
                    status: status,
                    assignee: assignee,
                    difficulty: difficulty,
                    cancelReason: cancelReason,
                    parentTaskID: nil  // Don't change parent in batch updates
                )
                updatedTasks.append(updated)
            } catch {
                // Continue with other tasks even if one fails
                // Could optionally collect errors and return them
                continue
            }
        }
        
        if updatedTasks.isEmpty && !taskIDs.isEmpty {
            throw MemoryError.databaseError("Failed to update any tasks")
        }
        
        return updatedTasks
    }
    
    // MARK: - Enhanced Get with Include Options
    
    public func getWithIncludes(taskID: String, include: TaskIncludeOptions?) async throws -> TaskFullInfo {
        let task = try await get(id: taskID)
        
        var fullInfo = TaskFullInfo(task: task)
        
        guard let include = include else {
            return fullInfo
        }
        
        let context = try await contextProvider.context()
        
        // Include session if requested
        if include.session == true {
            let sessionResult = try await context.raw(
                """
                MATCH (s:Session)-[:HasTask]->(t:Task {id: $taskID})
                RETURN s
                """,
                bindings: ["taskID": taskID]
            )
            fullInfo.session = try? sessionResult.mapFirst(to: Session.self)
        }
        
        // Include parent if requested
        if include.parent == true {
            let parentResult = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})-[:SubTaskOf]->(parent:Task)
                RETURN parent
                """,
                bindings: ["taskID": taskID]
            )
            fullInfo.parent = try? parentResult.mapFirst(to: Task.self)
        }
        
        // Include children if requested
        if include.children == true {
            let childrenResult = try await context.raw(
                """
                MATCH (child:Task)-[:SubTaskOf]->(t:Task {id: $taskID})
                RETURN child
                ORDER BY child.createdAt ASC
                """,
                bindings: ["taskID": taskID]
            )
            fullInfo.children = try? childrenResult.map(to: Task.self)
        }
        
        // Include blockers if requested
        if include.blockers == true {
            fullInfo.blockers = try await DependencyManager.shared.getBlockers(taskID: taskID)
        }
        
        // Include blocking if requested
        if include.blocking == true {
            let blockingResult = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})-[:Blocks]->(blocked:Task)
                RETURN blocked
                ORDER BY blocked.createdAt ASC
                """,
                bindings: ["taskID": taskID]
            )
            fullInfo.blocking = try? blockingResult.map(to: Task.self)
        }
        
        // Include full chain if requested
        if include.fullChain == true {
            fullInfo.fullChain = try await DependencyManager.shared.getFullChain(taskID: taskID)
        }
        
        return fullInfo
    }
}