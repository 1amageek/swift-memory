import Foundation

/// Repository protocol for Dependency operations
public protocol DependencyRepository: Sendable {
    /// Add a dependency between tasks
    func add(blockerID: String, blockedID: String) async throws
    
    /// Remove a dependency between tasks
    func remove(blockerID: String, blockedID: String) async throws
    
    /// Get tasks that block the given task
    func getBlockers(taskID: String) async throws -> [Task]
    
    /// Get tasks blocked by the given task
    func getBlocking(taskID: String) async throws -> [Task]
    
    /// Check if a task is blocked by any active tasks
    func isTaskBlocked(taskID: String) async throws -> Bool
    
    /// Get the full dependency chain for a task
    func getDependencyChain(taskID: String) async throws -> DependencyChain
    
    /// Check if adding a dependency would create a cycle
    func wouldCreateCycle(blockerID: String, blockedID: String) async throws -> Bool
}