import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct TaskListTool: Tool {
    public let name = "memory.task.list"
    public let description = "List tasks with various filters"

    public typealias Arguments = ListTasksArguments
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
            var query = ""
            var bindings: [String: any Sendable] = [:]
            var conditions: [String] = []

            // Build query based on filters
            if let sessionID = arguments.sessionID {
                query = "MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)"
                bindings["sessionID"] = sessionID
            } else if let parentID = arguments.parentTaskID {
                query = "MATCH (t:Task)-[:SubTaskOf]->(parent:Task {id: $parentID})"
                bindings["parentID"] = parentID
            } else {
                query = "MATCH (t:Task)"
            }

            // Add status filter
            if let status = arguments.status {
                conditions.append("t.status = $status")
                bindings["status"] = status.rawValue
            }

            // Add assignee filter
            if let assignee = arguments.assignee {
                conditions.append("t.assignee = $assignee")
                bindings["assignee"] = assignee
            }

            // Add difficulty filter
            if let difficultyMax = arguments.difficultyMax {
                conditions.append("t.difficulty <= $difficultyMax")
                bindings["difficultyMax"] = difficultyMax
            }

            // Add ready filter (no incomplete blockers)
            if let readyOnly = arguments.readyOnly, readyOnly {
                query += """

                    WHERE NOT EXISTS {
                        MATCH (blocker:Task)-[:Blocks]->(t)
                        WHERE blocker.status IN ['pending', 'inProgress']
                    }
                    """
            }

            // Add other conditions
            if !conditions.isEmpty {
                if arguments.readyOnly == true {
                    query += " AND " + conditions.joined(separator: " AND ")
                } else {
                    query += " WHERE " + conditions.joined(separator: " AND ")
                }
            }

            // Return tasks
            if arguments.sessionID != nil {
                query += " RETURN t ORDER BY r.order ASC"
            } else {
                query += " RETURN t ORDER BY t.createdAt DESC"
            }

            let result = try context.raw(query, bindings: bindings)
            let tasks = try result.map(to: Task.self)
            return .taskList(tasks)
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
