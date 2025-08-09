import Foundation
import OpenFoundationModels

@available(*, deprecated, message: "Use DependencyGetTool with type: .chain instead")
public struct DependencyChainTool: Tool {
    public let name = "memory.dependency.chain"
    public let description = "Get full dependency chain (upstream/downstream) for a task"
    
    public typealias Arguments = GetDependencyChainArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let chain = try await DependencyManager.shared.getDependencyChain(taskID: arguments.taskID)
            return .dependencyChain(chain)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}