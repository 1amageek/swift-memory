import Foundation
import KuzuSwiftExtension

/// Legacy GraphDatabaseSetup for backward compatibility
/// Now delegates to DefaultDatabaseProvider
public actor GraphDatabaseSetup: DatabaseContextProvider {
    public static let shared = GraphDatabaseSetup()
    
    private let provider = DefaultDatabaseProvider.shared
    
    private init() {}
    
    public func initialize() async throws {
        try await provider.initialize()
    }
    
    public func context() async throws -> GraphContext {
        try await provider.context()
    }
}