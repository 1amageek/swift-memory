import Foundation

/// Thread-safe date formatters
public enum DateFormatters {
    // Thread-safe lock for DateFormatter access
    private static let lock = NSLock()
    
    // Shared formatters (accessed only through locked methods)
    private static let _display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// ISO8601 formatter for API date strings (thread-safe)
    nonisolated(unsafe) public static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Relative date formatter (thread-safe)
    nonisolated(unsafe) public static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    /// Thread-safe display date formatting
    public static func formatDisplay(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return _display.string(from: date)
    }
    
    /// Thread-safe display date parsing
    public static func parseDisplay(_ string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return _display.date(from: string)
    }
}

// MARK: - Date Extension for Formatting

public extension Date {
    /// Format date using ISO8601
    var iso8601String: String {
        DateFormatters.iso8601.string(from: self)
    }
    
    /// Format date for display (thread-safe)
    var displayString: String {
        DateFormatters.formatDisplay(self)
    }
    
    /// Format date as relative time
    var relativeString: String {
        DateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - String Extension for Parsing

public extension String {
    /// Parse ISO8601 date string
    var iso8601Date: Date? {
        DateFormatters.iso8601.date(from: self)
    }
}