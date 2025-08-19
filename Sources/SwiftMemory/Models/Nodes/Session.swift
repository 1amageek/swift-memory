import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros
import OpenFoundationModels

@GraphNode
public struct Session: Codable, Sendable {
    @ID public var id: String = UUID().uuidString
    public var title: String
    @Timestamp public var startedAt: Date = Date()
    
    public init(title: String) {
        self.title = title
    }
}