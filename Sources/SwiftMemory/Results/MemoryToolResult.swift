import Foundation
import OpenFoundationModels

public enum MemoryToolResult: Codable, Sendable {
    // Session results
    case sessionCreated(Session)
    case sessionRetrieved(Session)
    case sessionList([Session])
    case sessionUpdated(Session)
    case sessionDeleted(UUID)
    
    // Task results
    case taskCreated(Task)
    case taskRetrieved(Task)
    case taskList([Task])
    case taskUpdated(Task)
    case taskDeleted(UUID)
    case taskReordered(sessionID: UUID, orderedIds: [UUID])
    case taskInfo(TaskInfo)
    
    // Dependency results
    case dependencyAdded(blockerID: UUID, blockedID: UUID)
    case dependencyRemoved(blockerID: UUID, blockedID: UUID)
    case dependencyChain(DependencyChain)
    case taskBlockedStatus(taskID: UUID, isBlocked: Bool)
    
    // Error result
    case error(String)
}

extension MemoryToolResult: PromptRepresentable {
    public var promptRepresentation: Prompt {
        switch self {
        // Session results
        case .sessionCreated(let session):
            return Prompt("Created session '\(session.title)' with ID: \(session.id)")
            
        case .sessionRetrieved(let session):
            return Prompt("Session: '\(session.title)' (ID: \(session.id), started: \(formatDate(session.startedAt)))")
            
        case .sessionList(let sessions):
            if sessions.isEmpty {
                return Prompt("No sessions found")
            }
            let sessionDescriptions = sessions.map { session in
                "- \(session.title) (ID: \(session.id), started: \(formatDate(session.startedAt)))"
            }.joined(separator: "\n")
            return Prompt("Sessions:\n\(sessionDescriptions)")
            
        case .sessionUpdated(let session):
            return Prompt("Updated session '\(session.title)' (ID: \(session.id))")
            
        case .sessionDeleted(let id):
            return Prompt("Deleted session with ID: \(id)")
            
        // Task results
        case .taskCreated(let task):
            var message = "Created task '\(task.title)' with ID: \(task.id)"
            if let desc = task.description {
                message += "\nDescription: \(desc)"
            }
            message += "\nDifficulty: \(task.difficulty)/5"
            if let assignee = task.assignee {
                message += "\nAssigned to: \(assignee)"
            }
            return Prompt(message)
            
        case .taskRetrieved(let task):
            var message = "Task: '\(task.title)' (ID: \(task.id))"
            message += "\nStatus: \(task.status.displayName)"
            message += "\nDifficulty: \(task.difficulty)/5"
            if let desc = task.description {
                message += "\nDescription: \(desc)"
            }
            if let assignee = task.assignee {
                message += "\nAssigned to: \(assignee)"
            }
            if let cancelReason = task.cancelReason {
                message += "\nCancellation reason: \(cancelReason)"
            }
            return Prompt(message)
            
        case .taskList(let tasks):
            if tasks.isEmpty {
                return Prompt("No tasks found")
            }
            let taskDescriptions = tasks.map { task in
                var desc = "- [\(task.status.displayName)] \(task.title)"
                if let assignee = task.assignee {
                    desc += " (assigned: \(assignee))"
                }
                desc += " [difficulty: \(task.difficulty)/5]"
                return desc
            }.joined(separator: "\n")
            return Prompt("Tasks:\n\(taskDescriptions)")
            
        case .taskUpdated(let task):
            var message = "Updated task '\(task.title)' (ID: \(task.id))"
            message += "\nStatus: \(task.status.displayName)"
            if let cancelReason = task.cancelReason, task.status == .cancelled {
                message += "\nCancellation reason: \(cancelReason)"
            }
            return Prompt(message)
            
        case .taskDeleted(let id):
            return Prompt("Deleted task with ID: \(id)")
            
        case .taskReordered(let sessionID, let orderedIds):
            return Prompt("Reordered \(orderedIds.count) tasks in session \(sessionID)")
            
        case .taskInfo(let info):
            var message = "Task Info for '\(info.task.title)':"
            message += "\nStatus: \(info.task.status.displayName)"
            message += "\nDifficulty: \(info.task.difficulty)/5"
            
            if let parent = info.parent {
                message += "\n\nParent: \(parent.title)"
            }
            
            if !info.children.isEmpty {
                message += "\n\nChildren (\(info.children.count)):"
                message += info.children.map { "\n  - \($0.title)" }.joined()
            }
            
            if !info.blockers.isEmpty {
                message += "\n\nBlocked by (\(info.blockers.count)):"
                message += info.blockers.map { "\n  - \($0.title) [\($0.status.displayName)]" }.joined()
            }
            
            if !info.blocking.isEmpty {
                message += "\n\nBlocking (\(info.blocking.count)):"
                message += info.blocking.map { "\n  - \($0.title)" }.joined()
            }
            
            return Prompt(message)
            
        // Dependency results
        case .dependencyAdded(let blockerID, let blockedID):
            return Prompt("Added dependency: \(blockerID) blocks \(blockedID)")
            
        case .dependencyRemoved(let blockerID, let blockedID):
            return Prompt("Removed dependency: \(blockerID) no longer blocks \(blockedID)")
            
        case .dependencyChain(let chain):
            var message = "Dependency chain for task \(chain.taskID):"
            
            if !chain.upstream.isEmpty {
                message += "\n\nUpstream dependencies (\(chain.upstream.count)):"
                for item in chain.upstream {
                    message += "\n  " + String(repeating: "  ", count: item.depth - 1) + "- \(item.task.title) [\(item.task.status.displayName)]"
                }
            }
            
            if !chain.downstream.isEmpty {
                message += "\n\nDownstream dependencies (\(chain.downstream.count)):"
                for item in chain.downstream {
                    message += "\n  " + String(repeating: "  ", count: item.depth - 1) + "- \(item.task.title) [\(item.task.status.displayName)]"
                }
            }
            
            return Prompt(message)
            
        case .taskBlockedStatus(let taskID, let isBlocked):
            return Prompt("Task \(taskID) is \(isBlocked ? "blocked by active dependencies" : "not blocked")")
            
        // Error
        case .error(let message):
            return Prompt("Error: \(message)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        return date.displayString
    }
}