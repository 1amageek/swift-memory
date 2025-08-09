import Foundation
import OpenFoundationModels

@Generable
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case inProgress = "inProgress"
    case done = "done"
    case cancelled = "cancelled"
    
    public var isCompleted: Bool {
        switch self {
        case .done, .cancelled:
            return true
        case .pending, .inProgress:
            return false
        }
    }
    
    public var isActive: Bool {
        !isCompleted
    }
    
    public var displayName: String {
        switch self {
        case .pending:
            return "Pending"
        case .inProgress:
            return "In Progress"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        }
    }
}