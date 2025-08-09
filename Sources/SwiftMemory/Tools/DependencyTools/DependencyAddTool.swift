import Foundation
import OpenFoundationModels

public struct DependencyAddTool: Tool {
    public let name = "memory.dependency.add"
    public let description = "Add a dependency between tasks (blocker blocks blocked)"
    
    public typealias Arguments = AddDependencyArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            try await DependencyManager.shared.add(
                blockerID: arguments.blockerID,
                blockedID: arguments.blockedID
            )
            return .dependencyAdded(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}