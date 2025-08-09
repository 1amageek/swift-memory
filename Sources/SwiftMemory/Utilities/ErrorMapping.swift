import Foundation

/// Shared utility for mapping errors to user-friendly messages with recovery suggestions
public enum ErrorMapping {
    /// Maps an error to a user-friendly message string with recovery suggestions if available
    public static func map(_ error: Error) -> String {
        if let memoryError = error as? MemoryError {
            var message = memoryError.errorDescription ?? "Unknown error"
            if let suggestion = memoryError.recoverySuggestion {
                message += ". \(suggestion)"
            }
            return message
        }
        return "Unexpected error occurred"
    }
}