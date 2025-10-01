import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct SessionCreateTool: Tool {
    public let name = "memory.session.create"
    public let description = "Create a new session"

    public typealias Arguments = CreateSessionArguments
    public typealias Output = MemoryToolResult

    private let context: GraphContext

    public init() {
        self.context = try! SwiftMemoryContext.shared.context()
    }

    init(context: GraphContext) {
        self.context = context
    }

    public func call(arguments: Arguments) async throws -> MemoryToolResult {
        do {
            let session = Session(title: arguments.title)
            context.insert(session)
            try context.save()
            return .sessionCreated(session)
        } catch {
            return .error(mapError(error))
        }
    }

    private func mapError(_ error: Error) -> String {
        if let e = error as? MemoryError, let msg = e.errorDescription {
            return msg
        }
        return "Unexpected error occurred"
    }
}
