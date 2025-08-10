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
        sessionID: UUID,
        title: String,
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        let context = try await contextProvider.context()
        
        // Validate inputs first
        guard (1...5).contains(difficulty) else {
            throw MemoryError.invalidDifficulty(difficulty)
        }
        
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
        
        var maxOrder = 0
        if maxOrderResult.hasNext(),
           let tuple = try maxOrderResult.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let orderValue = dict["maxOrder"] as? Int64 {
            maxOrder = Int(orderValue)
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
                // Clean up the created task since we can't establish the parent relationship
                try await context.delete(savedTask)
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
            
            var hasCycle = false
            if cycleResult.hasNext(),
               let tuple = try cycleResult.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let cycleValue = dict["hasCycle"] as? Bool {
                hasCycle = cycleValue
            }
            
            if hasCycle {
                // Clean up the created task since we can't establish the parent relationship
                try await context.delete(savedTask)
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
    
    public func get(id: UUID) async throws -> Task {
        let context = try await contextProvider.context()
        guard let task = try await context.fetchOne(Task.self, id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        return task
    }
    
    public func list(
        sessionID: UUID? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        parentTaskID: UUID? = nil,
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
            var tasks: [Task] = []
            while result.hasNext() {
                if let tuple = try result.getNext(),
                   let dict = try? tuple.getAsDictionary(),
                   let taskNode = dict["t"],
                   let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: taskNode) {
                    let task = try KuzuDecoder().decode(Task.self, from: properties)
                    tasks.append(task)
                }
            }
            return tasks
            
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
            var tasks: [Task] = []
            while result.hasNext() {
                if let tuple = try result.getNext(),
                   let dict = try? tuple.getAsDictionary(),
                   let taskNode = dict["t"],
                   let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: taskNode) {
                    let task = try KuzuDecoder().decode(Task.self, from: properties)
                    tasks.append(task)
                }
            }
            return tasks
            
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
                var tasks: [Task] = []
                while result.hasNext() {
                    if let tuple = try result.getNext(),
                       let dict = try? tuple.getAsDictionary(),
                       let taskNode = dict["t"],
                       let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: taskNode) {
                        let task = try KuzuDecoder().decode(Task.self, from: properties)
                        tasks.append(task)
                    }
                }
                return tasks
            }
        }
    }
    
    public func update(
        id: UUID,
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        difficulty: Int? = nil,
        cancelReason: String? = nil,
        parentTaskID: UUID? = nil
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
            
            var hasCycle = false
            if cycleResult.hasNext(),
               let tuple = try cycleResult.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let cycleValue = dict["hasCycle"] as? Bool {
                hasCycle = cycleValue
            }
            
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
    
    public func reorder(sessionID: UUID, orderedIds: [UUID]) async throws {
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
        
        var validIDs: Set<UUID> = []
        if validationResult.hasNext(),
           let tuple = try validationResult.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let idArray = dict["validIDs"] as? [Any] {
            for id in idArray {
                if let uuidString = id as? String,
                   let uuid = UUID(uuidString: uuidString) {
                    validIDs.insert(uuid)
                } else if let uuid = id as? UUID {
                    validIDs.insert(uuid)
                }
            }
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
    
    public func delete(id: UUID, cascade: Bool = false) async throws {
        let context = try await contextProvider.context()
        
        // Verify task exists
        guard let _ = try await context.fetchOne(Task.self, id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        
        if cascade {
            // Cascade delete all subtasks with separate queries
            // First delete all descendants (subtasks)
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*]->(t)
                WHERE descendant IS NOT NULL
                DETACH DELETE descendant
                """,
                bindings: ["taskID": id]
            )
            
            // Then delete the task itself
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                DETACH DELETE t
                """,
                bindings: ["taskID": id]
            )
        } else {
            // Simple delete - use DETACH DELETE to handle relationships
            _ = try await context.raw(
                """
                MATCH (t:Task {id: $taskID})
                DETACH DELETE t
                RETURN 1 as deleted
                """,
                bindings: ["taskID": id]
            )
        }
    }
    
    // MARK: - Task Relationships
    
    public func getParent(taskID: UUID) async throws -> Task? {
        let context = try await contextProvider.context()
        
        // Find parent task
        let result = try await context.raw(
            """
            MATCH (child:Task {id: $taskID})-[:SubTaskOf]->(parent:Task)
            RETURN parent
            """,
            bindings: ["taskID": taskID]
        )
        
        if result.hasNext(),
           let tuple = try result.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let parentNode = dict["parent"],
           let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: parentNode) {
            return try KuzuDecoder().decode(Task.self, from: properties)
        }
        return nil
    }
    
    public func getChildren(taskID: UUID) async throws -> [Task] {
        let context = try await contextProvider.context()
        
        // Find child tasks
        let result = try await context.raw(
            """
            MATCH (child:Task)-[:SubTaskOf]->(parent:Task {id: $taskID})
            RETURN child
            ORDER BY child.createdAt ASC
            """,
            bindings: ["taskID": taskID]
        )
        
        var children: [Task] = []
        while result.hasNext() {
            if let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let childNode = dict["child"],
               let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: childNode) {
                let child = try KuzuDecoder().decode(Task.self, from: properties)
                children.append(child)
            }
        }
        return children
    }
    
    // MARK: - Batch Operations
    
    public func updateBatch(
        taskIDs: [UUID],
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
    
    public func getWithIncludes(taskID: UUID, include: TaskIncludeOptions?) async throws -> TaskFullInfo {
        let task = try await get(id: taskID)
        
        // Default: return just the task if no includes specified
        guard let include = include, include.hasAnyEnabled else {
            return TaskFullInfo(
                task: task,
                parent: nil,
                children: nil,
                blockers: nil,
                blocking: nil,
                fullChain: nil,
                session: nil
            )
        }
        
        // Fetch requested information
        let parent = include.parent == true ? try await getParent(taskID: taskID) : nil
        let children = include.children == true ? try await getChildren(taskID: taskID) : nil
        
        var blockers: [Task]? = nil
        var blocking: [Task]? = nil
        if include.dependencies == true {
            blockers = try await DependencyManager.shared.getBlockers(taskID: taskID)
            blocking = try await DependencyManager.shared.getBlocking(taskID: taskID)
        }
        
        let fullChain = include.fullChain == true ? 
            try await DependencyManager.shared.getDependencyChain(taskID: taskID) : nil
        
        var session: Session? = nil
        if include.session == true {
            let context = try await contextProvider.context()
            let result = try await context.raw(
                """
                MATCH (s:Session)-[:HasTask]->(t:Task {id: $taskID})
                RETURN s
                """,
                bindings: ["taskID": taskID]
            )
            
            if result.hasNext(),
               let tuple = try result.getNext(),
               let dict = try? tuple.getAsDictionary(),
               let sessionNode = dict["s"],
               let properties = KuzuNodeExtractor.extractNodeOrDictionary(from: sessionNode) {
                session = try KuzuDecoder().decode(Session.self, from: properties)
            }
        }
        
        return TaskFullInfo(
            task: task,
            parent: parent,
            children: children,
            blockers: blockers,
            blocking: blocking,
            fullChain: fullChain,
            session: session
        )
    }
    
    // MARK: - Private Helpers (removed - now using KuzuSwiftExtension declarative APIs)
}

// MARK: - Supporting Types

public struct TaskFullInfo: Codable, Sendable {
    public let task: Task
    public let parent: Task?
    public let children: [Task]?
    public let blockers: [Task]?
    public let blocking: [Task]?
    public let fullChain: DependencyChain?
    public let session: Session?
}