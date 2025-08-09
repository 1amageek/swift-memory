import Foundation
import OpenFoundationModels

public struct DependencyRemoveTool: Tool {
    public let name = "memory.dependency.remove"
    public let description = "Remove a dependency between tasks"
    
    public typealias Arguments = RemoveDependencyArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            try await DependencyManager.shared.remove(
                blockerID: arguments.blockerID,
                blockedID: arguments.blockedID
            )
            return .dependencyRemoved(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}