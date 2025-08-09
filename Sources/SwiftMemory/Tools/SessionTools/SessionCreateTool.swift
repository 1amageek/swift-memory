import Foundation
import OpenFoundationModels

public struct SessionCreateTool: Tool {
    public let name = "memory.session.create"
    public let description = "Create a new session with a title"
    
    public typealias Arguments = CreateSessionArguments
    public typealias Output = MemoryToolResult
    
    public init() {}
    
    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let session = try await SessionManager.shared.create(title: arguments.title)
            return .sessionCreated(session)
        } catch {
            return .error(Self.map(error))
        }
    }
    
    private static func map(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription { return msg }
        return "Unexpected error occurred"
    }
}