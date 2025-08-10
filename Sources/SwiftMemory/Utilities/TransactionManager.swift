import Foundation
import KuzuSwiftExtension

/// Manages database transactions with retry logic and error handling
public struct TransactionManager {
    public static let defaultMaxAttempts = 3
    public static let defaultDelay = Duration.milliseconds(100)
    
    /// Execute an operation with automatic retry on transaction failures
    public static func executeWithRetry<T>(
        maxAttempts: Int = defaultMaxAttempts,
        delay: Duration = defaultDelay,
        operation: @Sendable () async throws -> T
    ) async throws -> T where T: Sendable {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if error is retryable
                if isRetryableError(error) && attempt < maxAttempts {
                    // Exponential backoff
                    let backoffDelay = delay * attempt
                    // Use Foundation's Task.sleep method
                    try await _Concurrency.Task.sleep(for: backoffDelay)
                } else {
                    // Non-retryable error or max attempts reached
                    throw mapError(error)
                }
            }
        }
        
        // This should never be reached, but for safety
        throw mapError(lastError ?? MemoryError.databaseError("Unknown transaction error"))
    }
    
    /// Execute multiple operations in a single transaction
    public static func executeInTransaction<T>(
        using contextProvider: DatabaseContextProvider,
        operations: @Sendable (GraphContext) async throws -> T
    ) async throws -> T where T: Sendable {
        let context = try await contextProvider.context()
        
        // Start transaction
        _ = try await context.raw("BEGIN TRANSACTION")
        
        do {
            let result = try await operations(context)
            
            // Commit transaction
            _ = try await context.raw("COMMIT")
            
            return result
        } catch {
            // Rollback transaction on error
            _ = try? await context.raw("ROLLBACK")
            throw mapError(error)
        }
    }
    
    /// Execute with both transaction and retry logic
    public static func executeWithTransactionAndRetry<T>(
        using contextProvider: DatabaseContextProvider,
        maxAttempts: Int = defaultMaxAttempts,
        delay: Duration = defaultDelay,
        operations: @escaping @Sendable (GraphContext) async throws -> T
    ) async throws -> T where T: Sendable {
        return try await executeWithRetry(
            maxAttempts: maxAttempts,
            delay: delay
        ) {
            try await executeInTransaction(
                using: contextProvider,
                operations: operations
            )
        }
    }
    
    // MARK: - Private Helpers
    
    /// Check if an error is retryable
    private static func isRetryableError(_ error: Error) -> Bool {
        // Check for specific error types that are retryable
        if let memoryError = error as? MemoryError {
            switch memoryError {
            case .databaseError(let message):
                // Check for transaction-related errors
                return message.lowercased().contains("transaction") ||
                       message.lowercased().contains("lock") ||
                       message.lowercased().contains("concurrent") ||
                       message.lowercased().contains("conflict")
            default:
                return false
            }
        }
        
        // Check for Kuzu-specific errors
        let errorDescription = String(describing: error).lowercased()
        return errorDescription.contains("transaction") ||
               errorDescription.contains("concurrent") ||
               errorDescription.contains("lock") ||
               errorDescription.contains("conflict")
    }
    
    /// Map errors to appropriate MemoryError types
    private static func mapError(_ error: Error) -> Error {
        // If already a MemoryError, return as is
        if error is MemoryError {
            return error
        }
        
        // Map Kuzu errors to MemoryError
        let errorDescription = String(describing: error)
        
        if errorDescription.contains("transactionFailed") {
            return MemoryError.databaseError("Transaction failed: \(errorDescription)")
        }
        
        if errorDescription.contains("KuzuError") {
            // Extract the error code if possible
            if let range = errorDescription.range(of: "error \\d+", options: .regularExpression) {
                let errorCode = String(errorDescription[range])
                return MemoryError.databaseError("Database error (\(errorCode)): Please retry the operation")
            }
            return MemoryError.databaseError("Database operation failed: \(errorDescription)")
        }
        
        // Default to generic database error
        return MemoryError.databaseError("Unexpected error: \(errorDescription)")
    }
}

// MARK: - Extensions for Managers

extension SessionManager {
    /// Execute a session operation with retry logic
    public func executeWithRetry<T>(
        _ operation: @escaping @Sendable (SessionManager) async throws -> T
    ) async throws -> T where T: Sendable {
        return try await TransactionManager.executeWithRetry {
            try await operation(self)
        }
    }
}

extension TaskManager {
    /// Execute a task operation with retry logic
    public func executeWithRetry<T>(
        _ operation: @escaping @Sendable (TaskManager) async throws -> T
    ) async throws -> T where T: Sendable {
        return try await TransactionManager.executeWithRetry {
            try await operation(self)
        }
    }
}

extension DependencyManager {
    /// Execute a dependency operation with retry logic
    public func executeWithRetry<T>(
        _ operation: @escaping @Sendable (DependencyManager) async throws -> T
    ) async throws -> T where T: Sendable {
        return try await TransactionManager.executeWithRetry {
            try await operation(self)
        }
    }
}