import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

// MARK: - Task Tool Arguments

public struct CreateTaskArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID
    public let title: String
    public let description: String?
    public let difficulty: Int?
    public let assignee: String?
    public let parentTaskID: UUID?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct UpdateTaskArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID?  // Single task update (backward compatibility)
    public let taskIDs: [UUID]?  // Batch update (new)
    public let update: TaskUpdate
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct TaskUpdate: Codable, Sendable {
    public let title: String?
    public let description: String?
    public let status: TaskStatus?
    public let assignee: String?
    public let difficulty: Int?
    public let cancelReason: String?
}

public struct GetTaskArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID
    public let includeInfo: Bool? // Deprecated, use include options instead
    public let include: TaskIncludeOptions?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct DeleteTaskArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID
    public let cascade: Bool?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct ListTasksArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID?
    public let status: TaskStatus?
    public let assignee: String?
    public let parentTaskID: UUID?
    public let readyOnly: Bool?
    public let difficultyMax: Int?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct ReorderTasksArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID
    public let orderedIDs: [UUID]
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

// MARK: - Session Tool Arguments

public struct CreateSessionArguments: Codable, ConvertibleFromGeneratedContent {
    public let title: String
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct UpdateSessionArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID
    public let title: String
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct GetSessionArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct DeleteSessionArguments: Codable, ConvertibleFromGeneratedContent {
    public let sessionID: UUID
    public let cascade: Bool?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct ListSessionsArguments: Codable, ConvertibleFromGeneratedContent {
    public let startedAfter: Date?
    public let startedBefore: Date?
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

// MARK: - Dependency Tool Arguments

public struct AddDependencyArguments: Codable, ConvertibleFromGeneratedContent {
    public let blockerID: UUID
    public let blockedID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct RemoveDependencyArguments: Codable, ConvertibleFromGeneratedContent {
    public let blockerID: UUID
    public let blockedID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct GetDependencyChainArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}

public struct GetTaskBlockedStatusArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}