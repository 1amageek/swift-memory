import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct SessionListTool: Tool {
    public let name = "memory.session.list"
    public let description = "List all sessions with optional filtering"

    public typealias Arguments = ListSessionsArguments
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
            var query = "MATCH (s:Session)"
            var bindings: [String: any Sendable] = [:]
            var conditions: [String] = []

            if let after = arguments.startedAfter {
                conditions.append("s.startedAt >= $after")
                bindings["after"] = after
            }
            if let before = arguments.startedBefore {
                conditions.append("s.startedAt <= $before")
                bindings["before"] = before
            }

            if !conditions.isEmpty {
                query += " WHERE " + conditions.joined(separator: " AND ")
            }

            query += " RETURN s ORDER BY s.startedAt DESC"

            let result = try context.raw(query, bindings: bindings)
            let sessions = try result.map(to: Session.self)
            return .sessionList(sessions)
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
