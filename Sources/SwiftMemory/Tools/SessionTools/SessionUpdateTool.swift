import Foundation
import OpenFoundationModels

public struct SessionUpdateTool: Tool {
    public let name = "memory.session.update"
    public let description = "Update a session's title"
    
    public typealias Arguments = UpdateSessionArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let session = try await SessionManager.shared.update(
                id: arguments.sessionID,
                title: arguments.title
            )
            return .sessionUpdated(session)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}