import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct SessionDeleteTool: Tool {
    public let name = "memory.session.delete"
    public let description = "Delete a session and optionally its tasks"

    public typealias Arguments = DeleteSessionArguments
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
            if arguments.cascade == true {
                // Cascade delete: session + all tasks + subtasks
                try context.withRawTransaction { conn in
                    // Delete all descendant tasks first
                    _ = try conn.query("""
                        MATCH (s:Session {id: '\(arguments.sessionID)'})-[:HasTask]->(t:Task)
                        OPTIONAL MATCH (descendant:Task)-[:SubTaskOf*]->(t)
                        WHERE descendant IS NOT NULL
                        DETACH DELETE descendant
                        """)

                    // Delete direct tasks
                    _ = try conn.query("""
                        MATCH (s:Session {id: '\(arguments.sessionID)'})-[:HasTask]->(t:Task)
                        DETACH DELETE t
                        """)

                    // Delete the session itself
                    _ = try conn.query("""
                        MATCH (s:Session {id: '\(arguments.sessionID)'})
                        DETACH DELETE s
                        """)
                }
            } else {
                // Simple delete
                _ = try context.raw(
                    "MATCH (s:Session {id: $sessionID}) DETACH DELETE s",
                    bindings: ["sessionID": arguments.sessionID]
                )
            }

            return .sessionDeleted(arguments.sessionID)
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
