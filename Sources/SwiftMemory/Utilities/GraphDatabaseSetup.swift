import Foundation
import KuzuSwiftExtension

public actor GraphDatabaseSetup {
    public static let shared = GraphDatabaseSetup()
    
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