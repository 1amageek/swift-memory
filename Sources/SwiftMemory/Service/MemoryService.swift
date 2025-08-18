import Foundation
import KuzuSwiftExtension

/// Unified service for SwiftMemory operations
public actor MemoryService {
    private let sessionRepo: SessionRepository
    private let taskRepo: TaskRepository
    private let dependencyRepo: DependencyRepository
    private let context: GraphContext
    
    /// Initialize with repositories and context
    public init(
        sessionRepo: SessionRepository,
        taskRepo: TaskRepository,
        dependencyRepo: DependencyRepository,
        context: GraphContext
    ) {
        self.sessionRepo = sessionRepo
        self.taskRepo = taskRepo
        self.dependencyRepo = dependencyRepo
        self.context = context
    }
    
    /// Create from SwiftMemoryContext
    public static func create(from memoryContext: SwiftMemoryContext) async throws -> MemoryService {
        let graphContext = try await memoryContext.context()
        
        let sessionRepo = KuzuSessionRepository(context: graphContext)
        let taskRepo = KuzuTaskRepository(context: graphContext)
        let dependencyRepo = KuzuDependencyRepository(context: graphContext)
        
        return MemoryService(
            sessionRepo: sessionRepo,
            taskRepo: taskRepo,
            dependencyRepo: dependencyRepo,
            context: graphContext
        )
    }
    
    // MARK: - Session Operations
    
    public func createSession(title: String) async throws -> Session {
        let session = Session(title: title)
        return try await sessionRepo.create(session)
    }
    
    public func getSession(id: UUID) async throws -> Session {
        guard let session = try await sessionRepo.find(id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        return session
    }
    
    public func listSessions(filter: SessionFilter? = nil) async throws -> [Session] {
        return try await sessionRepo.findAll(filter: filter)
    }
    
    public func updateSession(id: UUID, title: String) async throws -> Session {
        guard var session = try await sessionRepo.find(id: id) else {
            throw MemoryError.sessionNotFound(id)
        }
        session.title = title
        return try await sessionRepo.update(session)
    }
    
    public func deleteSession(id: UUID, cascade: Bool = false) async throws {
        try await sessionRepo.delete(id: id, cascade: cascade)
    }
    
    // MARK: - Task Operations
    
    public func createTask(
        sessionID: UUID,
        title: String,
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        // Validate difficulty
        guard (1...5).contains(difficulty) else {
            throw MemoryError.invalidDifficulty(difficulty)
        }
        
        // Verify session exists
        guard let _ = try await sessionRepo.find(id: sessionID) else {
            throw MemoryError.sessionNotFound(sessionID)
        }
        
        let task = Task(
            title: title,
            description: description,
            assignee: assignee,
            difficulty: difficulty
        )
        
        return try await taskRepo.create(task, sessionID: sessionID, parentTaskID: parentTaskID)
    }
    
    public func getTask(id: UUID) async throws -> Task {
        guard let task = try await taskRepo.find(id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        return task
    }
    
    public func listTasks(filter: TaskFilter? = nil) async throws -> [Task] {
        return try await taskRepo.findAll(filter: filter)
    }
    
    public func updateTask(
        id: UUID,
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        assignee: String? = nil,
        difficulty: Int? = nil,
        cancelReason: String? = nil,
        parentTaskID: UUID? = nil
    ) async throws -> Task {
        guard var task = try await taskRepo.find(id: id) else {
            throw MemoryError.taskNotFound(id)
        }
        
        // Apply updates
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
        if let cancelReason = cancelReason { task.cancelReason = cancelReason }
        
        task.updatedAt = Date()
        
        // Update task
        let updated = try await taskRepo.update(task)
        
        // Update parent if specified
        if parentTaskID != nil {
            try await taskRepo.setParent(taskID: id, parentID: parentTaskID)
        }
        
        return updated
    }
    
    public func deleteTask(id: UUID, cascade: Bool = false) async throws {
        try await taskRepo.delete(id: id, cascade: cascade)
    }
    
    public func reorderTasks(sessionID: UUID, orderedTaskIDs: [UUID]) async throws {
        try await taskRepo.reorder(sessionID: sessionID, orderedTaskIDs: orderedTaskIDs)
    }
    
    // MARK: - Complex Operations
    
    /// Create a task with dependencies in a single transaction
    public func createTaskWithDependencies(
        sessionID: UUID,
        title: String,
        description: String? = nil,
        difficulty: Int = 3,
        assignee: String? = nil,
        parentTaskID: UUID? = nil,
        blockerIDs: [UUID] = []
    ) async throws -> Task {
        // Create the task first
        let task = try await self.createTask(
            sessionID: sessionID,
            title: title,
            description: description,
            difficulty: difficulty,
            assignee: assignee,
            parentTaskID: parentTaskID
        )
        
        // Add dependencies
        for blockerID in blockerIDs {
            try await self.dependencyRepo.add(blockerID: blockerID, blockedID: task.id)
        }
        
        return task
    }
    
    /// Get ready tasks in a session (not blocked by active tasks)
    public func getReadyTasks(
        sessionID: UUID,
        assignee: String? = nil,
        difficultyMax: Int? = nil
    ) async throws -> [Task] {
        let filter = TaskFilter(
            sessionID: sessionID,
            assignee: assignee,
            difficultyMax: difficultyMax,
            readyOnly: true
        )
        
        return try await taskRepo.findAll(filter: filter)
    }
    
    /// Get task with full information including dependencies and hierarchy
    public func getTaskWithFullInfo(taskID: UUID, include: TaskIncludeOptions?) async throws -> TaskFullInfo {
        let task = try await getTask(id: taskID)
        
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
        let parent = include.parent == true ? try await taskRepo.getParent(taskID: taskID) : nil
        let children = include.children == true ? try await taskRepo.getChildren(taskID: taskID) : nil
        
        var blockers: [Task]? = nil
        var blocking: [Task]? = nil
        if include.dependencies == true {
            blockers = try await dependencyRepo.getBlockers(taskID: taskID)
            blocking = try await dependencyRepo.getBlocking(taskID: taskID)
        }
        
        let fullChain = include.fullChain == true ?
            try await dependencyRepo.getDependencyChain(taskID: taskID) : nil
        
        var session: Session? = nil
        if include.session == true {
            let result = try await context.raw(
                """
                MATCH (s:Session)-[:HasTask]->(t:Task {id: $taskID})
                RETURN s
                """,
                bindings: ["taskID": taskID]
            )
            
            session = try result.mapFirst(to: Session.self)
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
    
    /// Batch update multiple tasks
    public func batchUpdateTasks(
        taskIDs: [UUID],
        updates: TaskUpdateData
    ) async throws -> [Task] {
        return try await taskRepo.batchUpdate(taskIDs: taskIDs, updates: updates)
    }
    
    // MARK: - Dependency Operations
    
    public func addDependency(blockerID: UUID, blockedID: UUID) async throws {
        try await dependencyRepo.add(blockerID: blockerID, blockedID: blockedID)
    }
    
    public func removeDependency(blockerID: UUID, blockedID: UUID) async throws {
        try await dependencyRepo.remove(blockerID: blockerID, blockedID: blockedID)
    }
    
    public func getTaskBlockers(taskID: UUID) async throws -> [Task] {
        return try await dependencyRepo.getBlockers(taskID: taskID)
    }
    
    public func getTasksBlockedBy(taskID: UUID) async throws -> [Task] {
        return try await dependencyRepo.getBlocking(taskID: taskID)
    }
    
    public func isTaskBlocked(taskID: UUID) async throws -> Bool {
        return try await dependencyRepo.isTaskBlocked(taskID: taskID)
    }
    
    public func getDependencyChain(taskID: UUID) async throws -> DependencyChain {
        return try await dependencyRepo.getDependencyChain(taskID: taskID)
    }
    
    // MARK: - Session Task Management
    
    public func getSessionTasks(sessionID: UUID) async throws -> [TaskWithOrder] {
        return try await sessionRepo.getTasks(sessionID: sessionID)
    }
    
    public func getSessionTaskCount(sessionID: UUID) async throws -> Int {
        return try await sessionRepo.getTaskCount(sessionID: sessionID)
    }
}