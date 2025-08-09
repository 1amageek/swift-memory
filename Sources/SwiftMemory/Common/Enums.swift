import Foundation

// MARK: - Task Difficulty

/// Task difficulty level with clear, intuitive naming
public enum TaskDifficulty: String, Codable, CaseIterable, Sendable {
    case trivial = "trivial"
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
    case expert = "expert"
    
    /// Convert to integer value (1-5) for backward compatibility
    public var intValue: Int {
        switch self {
        case .trivial: return 1
        case .easy: return 2
        case .medium: return 3
        case .hard: return 4
        case .expert: return 5
        }
    }
    
    /// Create from integer value for backward compatibility
    public init?(intValue: Int) {
        switch intValue {
        case 1: self = .trivial
        case 2: self = .easy
        case 3: self = .medium
        case 4: self = .hard
        case 5: self = .expert
        default: return nil
        }
    }
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .trivial: return "Trivial"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .expert: return "Expert"
        }
    }
    
    /// Description for UI/logging
    public var description: String {
        "\(displayName) (\(intValue)/5)"
    }
}


// MARK: - Dependency Action

/// Actions for dependency management
public enum DependencyAction: String, Codable, Sendable {
    case add = "add"
    case remove = "remove"
}

// MARK: - Dependency Query Type

/// Types of dependency information to retrieve
public enum DependencyQueryType: String, Codable, Sendable {
    case chain = "chain"           // Full upstream and downstream chain
    case blockers = "blockers"     // Tasks that block this task
    case blocking = "blocking"     // Tasks blocked by this task
    case isBlocked = "isBlocked"   // Simple check if task is blocked
}

// MARK: - Include Options for Task Queries

/// Options for including related information in task queries
public struct TaskIncludeOptions: Codable, Sendable {
    public var parent: Bool?
    public var children: Bool?
    public var dependencies: Bool?
    public var fullChain: Bool?
    public var session: Bool?
    
    public init(
        parent: Bool? = nil,
        children: Bool? = nil,
        dependencies: Bool? = nil,
        fullChain: Bool? = nil,
        session: Bool? = nil
    ) {
        self.parent = parent
        self.children = children
        self.dependencies = dependencies
        self.fullChain = fullChain
        self.session = session
    }
    
    /// Check if any options are enabled
    public var hasAnyEnabled: Bool {
        [parent, children, dependencies, fullChain, session].contains { $0 == true }
    }
}

// MARK: - Batch Update Options

/// Options for batch updating tasks
public struct TaskBatchUpdate: Codable, Sendable {
    public var title: String?
    public var description: String?
    public var status: TaskStatus?
    public var difficulty: TaskDifficulty?
    public var assignee: String?
    public var cancelReason: String?
    
    public init(
        title: String? = nil,
        description: String? = nil,
        status: TaskStatus? = nil,
        difficulty: TaskDifficulty? = nil,
        assignee: String? = nil,
        cancelReason: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.difficulty = difficulty
        self.assignee = assignee
        self.cancelReason = cancelReason
    }
}