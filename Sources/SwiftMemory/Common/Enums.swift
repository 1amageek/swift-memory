import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore
import OpenFoundationModelsMacros

// MARK: - Task Difficulty

/// Task difficulty level with clear, intuitive naming
@Generable
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

@Generable
public enum DependencyAction: String, Sendable {
    case add = "add"
    case remove = "remove"
}

// MARK: - Dependency Query Type

@Generable
public enum DependencyQueryType: String, Sendable {
    case chain = "chain"           // Full upstream and downstream chain
    case blockers = "blockers"     // Tasks that block this task
    case blocking = "blocking"     // Tasks blocked by this task
    case isBlocked = "isBlocked"   // Simple check if task is blocked
}

// MARK: - Include Options for Task Queries

/// Options for including related information in task queries
@Generable
public struct TaskIncludeOptions: Codable, Sendable {
    @Guide(description: "Include parent task information")
    public var parent: Bool?
    
    @Guide(description: "Include child tasks")
    public var children: Bool?
    
    @Guide(description: "Include tasks that block this task")
    public var blockers: Bool?
    
    @Guide(description: "Include tasks blocked by this task")
    public var blocking: Bool?
    
    @Guide(description: "Include full dependency chain")
    public var fullChain: Bool?
    
    @Guide(description: "Include session information")
    public var session: Bool?
}

extension TaskIncludeOptions {
    /// Check if any options are enabled
    public var hasAnyEnabled: Bool {
        [parent, children, blockers, blocking, fullChain, session].contains { $0 == true }
    }
    
    /// Convenience initializer for regular Swift usage
    /// Creates TaskIncludeOptions from individual parameters
    public static func create(
        parent: Bool? = nil,
        children: Bool? = nil,
        dependencies: Bool? = nil,
        blockers: Bool? = nil,
        blocking: Bool? = nil,
        fullChain: Bool? = nil,
        session: Bool? = nil
    ) -> TaskIncludeOptions {
        // Build JSON dictionary
        var json: [String: Any] = [:]
        if let parent = parent { json["parent"] = parent }
        if let children = children { json["children"] = children }
        // Handle 'dependencies' for backward compatibility - sets both blockers and blocking
        if let dependencies = dependencies {
            json["blockers"] = dependencies
            json["blocking"] = dependencies
        }
        if let blockers = blockers { json["blockers"] = blockers }
        if let blocking = blocking { json["blocking"] = blocking }
        if let fullChain = fullChain { json["fullChain"] = fullChain }
        if let session = session { json["session"] = session }
        
        // Convert to JSON string
        let jsonData = try! JSONSerialization.data(withJSONObject: json, options: [])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Use the @Generable initializer
        return try! TaskIncludeOptions(GeneratedContent(json: jsonString))
    }
}

// MARK: - Batch Update Options

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
