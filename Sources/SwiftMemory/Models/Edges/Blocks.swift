import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros

@GraphEdge(from: Task.self, to: Task.self)
public struct Blocks: Codable, Sendable {
    public init() {}
}