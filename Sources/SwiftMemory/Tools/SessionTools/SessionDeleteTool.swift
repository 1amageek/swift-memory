import Foundation
import OpenFoundationModels

public struct SessionDeleteTool: Tool {
    public let name = "memory.session.delete"
    public let description = "Delete a session, optionally cascading to delete all its tasks"
    
    public typealias Arguments = DeleteSessionArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            try await SessionManager.shared.delete(
                id: arguments.sessionID,
                cascade: arguments.cascade ?? false
            )
            return .sessionDeleted(arguments.sessionID)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}