import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct DependencyGetTool: Tool {
    public let name = "memory.dependency.get"
    public let description = "Get dependency information for a task"

    public typealias Arguments = GetDependencyArguments
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
            switch arguments.queryType {
            case .blockers:
                let result = try context.raw("""
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    RETURN blocker
                    ORDER BY blocker.createdAt ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                let blockers = try result.map(to: Task.self)
                return .taskBlockers(taskID: arguments.taskID, blockers: blockers)

            case .blocking:
                let result = try context.raw("""
                    MATCH (blocker:Task {id: $taskID})-[:Blocks]->(blocked:Task)
                    RETURN blocked
                    ORDER BY blocked.createdAt ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                let blocking = try result.map(to: Task.self)
                return .taskBlocking(taskID: arguments.taskID, blocking: blocking)

            case .isBlocked:
                let result = try context.raw("""
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    WHERE blocker.status IN ['pending', 'inProgress']
                    RETURN COUNT(blocker) > 0 AS isBlocked
                    """,
                    bindings: ["taskID": arguments.taskID]
                )
                guard let row = try result.getNext(),
                      let isBlocked = try? row.getValue(0) as? Bool else {
                    return .taskBlockedStatus(taskID: arguments.taskID, isBlocked: false)
                }
                return .taskBlockedStatus(taskID: arguments.taskID, isBlocked: isBlocked)

            case .chain:
                // Get upstream dependencies
                let upstreamResult = try context.raw("""
                    MATCH path = (blocker:Task)-[:Blocks*]->(blocked:Task {id: $taskID})
                    WITH blocker, min(length(path)) as depth
                    RETURN blocker, depth
                    ORDER BY depth DESC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )

                let decoder = KuzuDecoder()
                let upstreamRows = try upstreamResult.mapRows()
                let upstream = try upstreamRows.map { row in
                    let task = try decoder.decode(Task.self, from: row["blocker"] as! [String: Any])
                    let depth = (row["depth"] as? Int64).map(Int.init) ?? 0
                    return DependencyChainItem(task: task, depth: depth)
                }

                // Get downstream dependencies
                let downstreamResult = try context.raw("""
                    MATCH path = (blocker:Task {id: $taskID})-[:Blocks*]->(blocked:Task)
                    WITH blocked, min(length(path)) as depth
                    RETURN blocked, depth
                    ORDER BY depth ASC
                    """,
                    bindings: ["taskID": arguments.taskID]
                )

                let downstreamRows = try downstreamResult.mapRows()
                let downstream = try downstreamRows.map { row in
                    let task = try decoder.decode(Task.self, from: row["blocked"] as! [String: Any])
                    let depth = (row["depth"] as? Int64).map(Int.init) ?? 0
                    return DependencyChainItem(task: task, depth: depth)
                }

                let chain = DependencyChain(
                    taskID: arguments.taskID,
                    upstream: upstream,
                    downstream: downstream
                )
                return .dependencyChain(chain)
            }
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
