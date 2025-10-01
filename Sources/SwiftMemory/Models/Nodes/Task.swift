import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros
import OpenFoundationModels

@GraphNode
public struct Task: Codable, Sendable {
    @ID public var id: String = UUID().uuidString
    public var title: String
    public var description: String?
    public var status: TaskStatus = .pending
    public var cancelReason: String?
    public var assignee: String?
    public var difficulty: Int = 3
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        status: TaskStatus = .pending,
        cancelReason: String? = nil,
        assignee: String? = nil,
        difficulty: Int = 3
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.cancelReason = cancelReason
        self.assignee = assignee
        self.difficulty = difficulty
    }
    
    public var isReady: Bool {
        !status.isCompleted
    }
}