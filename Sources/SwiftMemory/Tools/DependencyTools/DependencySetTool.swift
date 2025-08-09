import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// Unified dependency management tool that combines add and remove operations
public struct DependencySetTool: Tool {
    public let name = "memory.dependency.set"
    public let description = "Add or remove task dependencies"
    
    public typealias Arguments = SetDependencyArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            switch arguments.action {
            case .add:
                try await DependencyManager.shared.add(
                    blockerID: arguments.blockerID,
                    blockedID: arguments.blockedID
                )
                return .dependencyAdded(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
                
            case .remove:
                try await DependencyManager.shared.remove(
                    blockerID: arguments.blockerID,
                    blockedID: arguments.blockedID
                )
                return .dependencyRemoved(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
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

public struct SetDependencyArguments: Codable, ConvertibleFromGeneratedContent {
    public let action: DependencyAction
    public let blockerID: UUID
    public let blockedID: UUID
    
    public init(_ content: GeneratedContent) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self = try decoder.decode(Self.self, from: data)
    }
}