import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros

@GraphEdge(from: Task.self, to: Task.self)
public struct SubTaskOf: Codable, Sendable {
    public init() {}
}