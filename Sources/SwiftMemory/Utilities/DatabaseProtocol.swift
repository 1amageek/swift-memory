import Foundation
import KuzuSwiftExtension

/// Protocol for providing database context
/// This allows for dependency injection and test isolation
public protocol DatabaseContextProvider: Sendable {
    /// Get a database context for operations
    func context() async throws -> GraphContext
    
    /// Initialize the database if needed
    func initialize() async throws
}

/// Default implementation using the shared GraphDatabase
public actor DefaultDatabaseProvider: DatabaseContextProvider {
    public static let shared = DefaultDatabaseProvider()
    
    private var isInitialized = false
    
    private init() {}
    
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        // Register all models with GraphDatabase
        await GraphDatabase.shared.register(models: [
            Session.self,
            Task.self,
            HasTask.self,
            SubTaskOf.self,
            Blocks.self
        ])
        
        // Configure migration policy
        await GraphDatabase.shared.configure(migrationPolicy: .safeOnly)
        
        // Initialize context (this will create schema automatically)
        _ = try await GraphDatabase.shared.context()
        
        isInitialized = true
    }
    
    public func context() async throws -> GraphContext {
        if !isInitialized {
            try await initialize()
        }
        return try await GraphDatabase.shared.context()
    }
}