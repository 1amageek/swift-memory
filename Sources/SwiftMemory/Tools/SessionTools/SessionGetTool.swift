import Foundation
import OpenFoundationModels

public struct SessionGetTool: Tool {
    public let name = "memory.session.get"
    public let description = "Get a session by its ID"
    
    public typealias Arguments = GetSessionArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let session = try await SessionManager.shared.get(id: arguments.sessionID)
            return .sessionRetrieved(session)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}