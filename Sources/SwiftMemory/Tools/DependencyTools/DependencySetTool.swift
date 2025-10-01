import Foundation
import OpenFoundationModels
import KuzuSwiftExtension

public struct DependencySetTool: Tool {
    public let name = "memory.dependency.set"
    public let description = "Add or remove task dependencies"

    public typealias Arguments = SetDependencyArguments
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
            if arguments.action == .add {
                // Add dependency
                try context.withRawTransaction { conn in
                    // Check self-loop
                    if arguments.blockerID == arguments.blockedID {
                        throw MemoryError.invalidInput(
                            field: "dependency",
                            reason: "Task cannot block itself (self-loop detected)"
                        )
                    }

                    // Verify both tasks exist
                    let blockerCheck = try conn.query("MATCH (t:Task {id: '\(arguments.blockerID)'}) RETURN t")
                    guard blockerCheck.hasNext() else {
                        throw MemoryError.taskNotFound(arguments.blockerID)
                    }

                    let blockedCheck = try conn.query("MATCH (t:Task {id: '\(arguments.blockedID)'}) RETURN t")
                    guard blockedCheck.hasNext() else {
                        throw MemoryError.taskNotFound(arguments.blockedID)
                    }

                    // Check for cycles (would create a path from blocked back to blocker)
                    let cycleCheck = try conn.query("""
                        MATCH p = (blocked:Task {id: '\(arguments.blockedID)'})-[:Blocks*]->(blocker:Task {id: '\(arguments.blockerID)'})
                        RETURN COUNT(p) > 0 AS hasCycle
                        """)
                    if cycleCheck.hasNext(),
                       let row = try cycleCheck.getNext(),
                       let hasCycle = try? row.getValue(0) as? Bool,
                       hasCycle {
                        throw MemoryError.circularDependency(
                            blocker: arguments.blockerID,
                            blocked: arguments.blockedID
                        )
                    }

                    // Create Blocks relationship
                    _ = try conn.query("""
                        MATCH (blocker:Task {id: '\(arguments.blockerID)'}), (blocked:Task {id: '\(arguments.blockedID)'})
                        MERGE (blocker)-[r:Blocks]->(blocked)
                        RETURN r
                        """)
                }

                return .dependencyAdded(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
            } else {
                // Remove dependency
                _ = try context.raw("""
                    MATCH (blocker:Task {id: $blockerID})-[r:Blocks]->(blocked:Task {id: $blockedID})
                    DELETE r
                    RETURN COUNT(*) as deleted
                    """,
                    bindings: ["blockerID": arguments.blockerID, "blockedID": arguments.blockedID]
                )

                return .dependencyRemoved(blockerID: arguments.blockerID, blockedID: arguments.blockedID)
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
