import Foundation

public enum MemoryError: LocalizedError {
    case sessionNotFound(UUID)
    case taskNotFound(UUID)
    case invalidOrder
    case circularDependency(blocker: UUID, blocked: UUID)
    case duplicateParent(taskID: UUID)
    case invalidDifficulty(Int)
    case databaseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .invalidOrder:
            return "Invalid task order"
        case .circularDependency(let blocker, let blocked):
            return "Circular dependency detected: \(blocker) -> \(blocked)"
        case .duplicateParent(let taskID):
            return "Task \(taskID) already has a parent"
        case .invalidDifficulty(let value):
            return "Invalid difficulty: \(value). Must be between 1 and 5"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}