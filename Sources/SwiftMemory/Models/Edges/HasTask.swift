import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros

@GraphEdge(from: Session.self, to: Task.self)
public struct HasTask: Codable, Sendable {
    public var order: Int
    
    public init(order: Int) {
        self.order = order
    }
}