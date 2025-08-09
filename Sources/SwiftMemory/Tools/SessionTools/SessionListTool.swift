import Foundation
import OpenFoundationModels

public struct SessionListTool: Tool {
    public let name = "memory.session.list"
    public let description = "List sessions with optional date filters"
    
    public typealias Arguments = ListSessionsArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let sessions = try await SessionManager.shared.list(
                startedAfter: arguments.startedAfter,
                startedBefore: arguments.startedBefore
            )
            return .sessionList(sessions)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}