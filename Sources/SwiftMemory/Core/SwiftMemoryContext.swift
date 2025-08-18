import Foundation
import KuzuSwiftExtension
import KuzuSwiftMacros

/// SwiftMemory's context manager for database operations
public actor SwiftMemoryContext {
    private let configuration: SwiftMemoryConfiguration
    private var graphContext: GraphContext?
    private var isInitialized = false
    
    /// Shared instance with default configuration
    public static let shared = SwiftMemoryContext()
    
    /// Initialize with default configuration
    public init() {
        self.configuration = .default
    }
    
    /// Initialize with custom configuration
    public init(configuration: SwiftMemoryConfiguration) {
        self.configuration = configuration
    }
    
    /// Get or create the graph context
    public func context() async throws -> GraphContext {
        if let context = graphContext {
            return context
        }
        
        if configuration.databasePath != nil {
            // Custom path - create direct GraphContext
            let graphConfig = configuration.toGraphConfiguration()
            let context = try await GraphContext(configuration: graphConfig)
            
            // Register and migrate models
            try await initializeSchema(context: context)
            
            self.graphContext = context
            self.isInitialized = true
            return context
        } else {
            // Use GraphDatabase singleton for default path
            if !isInitialized {
                try await initializeGraphDatabase()
            }
            return try await GraphDatabase.shared.context()
        }
    }
    
    /// Initialize GraphDatabase with models and migration policy
    @MainActor
    private func initializeGraphDatabase() async throws {
        // Register all models with GraphDatabase
        GraphDatabase.shared.register(models: [
            Session.self,
            Task.self,
            HasTask.self,
            SubTaskOf.self,
            Blocks.self
        ])
        
        // Configure migration policy
        GraphDatabase.shared.configure(migrationPolicy: configuration.migrationPolicy)
    }
    
    /// Initialize schema for a custom GraphContext
    private func initializeSchema(context: GraphContext) async throws {
        // Create schemas for all models
        let models: [any _KuzuGraphModel.Type] = [
            Session.self,
            Task.self,
            HasTask.self,
            SubTaskOf.self,
            Blocks.self
        ]
        
        // Use MigrationManager for schema creation
        let migrationManager = MigrationManager(
            context: context,
            policy: configuration.migrationPolicy
        )
        
        try await migrationManager.migrate(types: models)
    }
    
    /// Execute a function with the graph context
    public func with<T>(_ block: @Sendable (GraphContext) async throws -> T) async throws -> T {
        let context = try await self.context()
        return try await block(context)
    }
    
    /// Execute a function within a transaction
    public func withTransaction<T: Sendable>(_ block: @escaping @Sendable (TransactionalGraphContext) throws -> T) async throws -> T {
        let context = try await self.context()
        return try await context.withTransaction(block)
    }
}