import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct SessionUpdateTool: Tool {
    public let name = "memory.session.update"
    public let description = "Update an existing session"

    public typealias Arguments = UpdateSessionArguments
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
            // Find existing session
            let result = try context.raw(
                "MATCH (s:Session {id: $id}) RETURN s",
                bindings: ["id": arguments.sessionID]
            )
            guard var session = try result.mapFirst(to: Session.self) else {
                throw MemoryError.sessionNotFound(arguments.sessionID)
            }

            // Update title
            session.title = arguments.title

            // Save
            context.insert(session)
            try context.save()

            return .sessionUpdated(session)
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
