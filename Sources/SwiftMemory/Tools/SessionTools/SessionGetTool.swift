import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct SessionGetTool: Tool {
    public let name = "memory.session.get"
    public let description = "Get a session by ID"

    public typealias Arguments = GetSessionArguments
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
            let result = try context.raw(
                "MATCH (s:Session {id: $id}) RETURN s",
                bindings: ["id": arguments.sessionID]
            )
            guard let session = try result.mapFirst(to: Session.self) else {
                throw MemoryError.sessionNotFound(arguments.sessionID)
            }
            return .sessionRetrieved(session)
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
