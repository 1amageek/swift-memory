import Foundation

/// Shared date formatters to avoid recreation overhead
public enum DateFormatters {
    /// ISO8601 formatter for API date strings
    nonisolated(unsafe) public static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// User-friendly date formatter
    public static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    /// Relative date formatter (e.g., "2 hours ago")
    nonisolated(unsafe) public static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

// MARK: - Date Extension for Formatting

public extension Date {
    /// Format date using ISO8601
    var iso8601String: String {
        DateFormatters.iso8601.string(from: self)
    }
    
    /// Format date for display
    var displayString: String {
        DateFormatters.display.string(from: self)
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