import Foundation

// MARK: - Error Codes

public enum MemoryErrorCode: String, Codable {
    case sessionNotFound = "SESSION_NOT_FOUND"
    case taskNotFound = "TASK_NOT_FOUND"
    case invalidOrder = "INVALID_ORDER"
    case circularDependency = "CIRCULAR_DEPENDENCY"
    case duplicateParent = "DUPLICATE_PARENT"
    case invalidDifficulty = "INVALID_DIFFICULTY"
    case invalidStatus = "INVALID_STATUS"
    case invalidInput = "INVALID_INPUT"
    case databaseError = "DATABASE_ERROR"
    case transactionFailed = "TRANSACTION_FAILED"
    case transactionConflict = "TRANSACTION_CONFLICT"
}

// MARK: - Memory Error

public enum MemoryError: LocalizedError {
    case sessionNotFound(UUID)
    case taskNotFound(UUID)
    case invalidOrder
    case circularDependency(blocker: UUID, blocked: UUID)
    case duplicateParent(taskID: UUID)
    case invalidDifficulty(Int)
    case invalidInput(field: String, reason: String)
    case databaseError(String)
    case transactionFailed(reason: String)
    case transactionConflict(operation: String)
    
    // MARK: - Error Code
    
    public var code: MemoryErrorCode {
        switch self {
        case .sessionNotFound: return .sessionNotFound
        case .taskNotFound: return .taskNotFound
        case .invalidOrder: return .invalidOrder
        case .circularDependency: return .circularDependency
        case .duplicateParent: return .duplicateParent
        case .invalidDifficulty: return .invalidDifficulty
        case .invalidInput: return .invalidInput
        case .databaseError: return .databaseError
        case .transactionFailed: return .transactionFailed
        case .transactionConflict: return .transactionConflict
        }
    }
    
    // MARK: - Error Description
    
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
        case .invalidInput(let field, let reason):
            return "Invalid input for \(field): \(reason)"
        case .databaseError(let message):
            return "Database error: \(message)"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .transactionConflict(let operation):
            return "Transaction conflict in \(operation): concurrent modification detected"
        }
    }
    
    // MARK: - Recovery Suggestion
    
    public var recoverySuggestion: String? {
        switch self {
        case .sessionNotFound:
            return "Verify the session ID or create a new session using memory.session.create"
        case .taskNotFound:
            return "Check the task ID or use memory.task.list to find available tasks"
        case .invalidOrder:
            return "Ensure all task IDs belong to the same session and are in the correct sequence"
        case .circularDependency:
            return "Remove intermediate dependencies to break the cycle, or reconsider the task relationships"
        case .duplicateParent:
            return "Remove the existing parent relationship before assigning a new one"
        case .invalidDifficulty:
            return "Use a value between 1-5, or use TaskDifficulty enum values (trivial, easy, medium, hard, expert)"
        case .invalidInput:
            return "Check the input format and ensure all required fields are provided correctly"
        case .databaseError:
            return "Check database connection and try again. If the problem persists, restart the service"
        case .transactionFailed:
            return "Retry the operation or check for database connectivity issues"
        case .transactionConflict:
            return "Retry the operation as another process may have modified the data concurrently"
        }
    }
    
    // MARK: - Context Information
    
    public var contextInfo: [String: String] {
        switch self {
        case .sessionNotFound(let id):
            return ["sessionID": id.uuidString]
        case .taskNotFound(let id):
            return ["taskID": id.uuidString]
        case .invalidOrder:
            return [:]
        case .circularDependency(let blocker, let blocked):
            return ["blockerID": blocker.uuidString, "blockedID": blocked.uuidString]
        case .duplicateParent(let taskID):
            return ["taskID": taskID.uuidString]
        case .invalidDifficulty(let value):
            return ["providedValue": String(value), "validRange": "1-5"]
        case .invalidInput(let field, let reason):
            return ["field": field, "reason": reason]
        case .databaseError(let message):
            return ["details": message]
        case .transactionFailed(let reason):
            return ["reason": reason]
        case .transactionConflict(let operation):
            return ["operation": operation]
        }
    }
    
    // MARK: - Structured Error Response
    
    public var structuredError: StructuredMemoryError {
        StructuredMemoryError(
            code: code.rawValue,
            message: errorDescription ?? "Unknown error",
            suggestion: recoverySuggestion,
            context: contextInfo
        )
    }
}

// MARK: - Structured Error for API Responses

public struct StructuredMemoryError: Codable, Sendable {
    public let code: String
    public let message: String
    public let suggestion: String?
    public let context: [String: String]
    
    public init(
        code: String,
        message: String,
        suggestion: String? = nil,
        context: [String: String] = [:]
    ) {
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.context = context
    }
}