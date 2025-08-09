import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Unified dependency query tool that combines chain and blocked status queries
public struct DependencyGetTool: Tool {
    public let name = "memory.dependency.get"
    public let description = "Get dependency information for a task (chain, blockers, blocking, or blocked status)"
    
    public typealias Arguments = GetDependencyArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            switch arguments.type {
            case .chain:
                let chain = try await DependencyManager.shared.getDependencyChain(taskID: arguments.taskID)
                return .dependencyChain(chain)
                
            case .blockers:
                let blockers = try await DependencyManager.shared.getBlockers(taskID: arguments.taskID)
                return .taskBlockers(taskID: arguments.taskID, blockers: blockers)
                
            case .blocking:
                let blocking = try await DependencyManager.shared.getBlocking(taskID: arguments.taskID)
                return .taskBlocking(taskID: arguments.taskID, blocking: blocking)
                
            case .isBlocked:
                let isBlocked = try await DependencyManager.shared.isTaskBlocked(taskID: arguments.taskID)
                return .taskBlockedStatus(taskID: arguments.taskID, isBlocked: isBlocked)
            }
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError {
            var message = e.errorDescription ?? "Unknown error"
            if let suggestion = e.recoverySuggestion {
                message += ". \(suggestion)"
            }
            return message
        }
        return "Unexpected error occurred"
    }
}

// MARK: - Arguments

public struct GetDependencyArguments: Codable, ConvertibleFromGeneratedContent {
    public let taskID: UUID
    public let type: DependencyQueryType
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}