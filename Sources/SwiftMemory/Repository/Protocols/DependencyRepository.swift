import Foundation

/// Repository protocol for Dependency operations
public protocol DependencyRepository: Sendable {
    /// Add a dependency between tasks
    func add(blockerID: UUID, blockedID: UUID) async throws
    
    /// Remove a dependency between tasks
    func remove(blockerID: UUID, blockedID: UUID) async throws
    
    /// Get tasks that block the given task
    func getBlockers(taskID: UUID) async throws -> [Task]
    
    /// Get tasks blocked by the given task
    func getBlocking(taskID: UUID) async throws -> [Task]
    
    /// Check if a task is blocked by any active tasks
    func isTaskBlocked(taskID: UUID) async throws -> Bool
    
    /// Get the full dependency chain for a task
    func getDependencyChain(taskID: UUID) async throws -> DependencyChain
    
    /// Check if adding a dependency would create a cycle
    func wouldCreateCycle(blockerID: UUID, blockedID: UUID) async throws -> Bool
}