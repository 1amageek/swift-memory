import Foundation
import Testing
import KuzuSwiftExtension
@testable import SwiftMemory

/// Provides isolated database setup for each test
public actor TestDatabaseSetup {
    private var isInitialized = false
    private let databasePath: String
    
    public init() {
        // Create unique database path for this test instance
        let tempDir = FileManager.default.temporaryDirectory
        let dbName = "test-\(UUID().uuidString)"
        self.databasePath = tempDir.appendingPathComponent(dbName).path
    }
    
    /// Initialize the test database
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
        await GraphDatabase.shared.configure(migrationPolicy: .safe)
        
        // Initialize context (this will create schema automatically)
        _ = try await GraphDatabase.shared.context()
        
        isInitialized = true
    }
    
    /// Get a context for database operations
    public func context() async throws -> GraphContext {
        if !isInitialized {
            try await initialize()
        }
        return try await GraphDatabase.shared.context()
    }
    
    /// Clean up the test database
    public func cleanup() async {
        // Note: We can't close the database as it's a singleton
        // But we can clean up test data if needed
        if FileManager.default.fileExists(atPath: databasePath) {
            try? FileManager.default.removeItem(atPath: databasePath)
        }
    }
    
    /// Create an isolated test environment
    public static func createIsolated() async throws -> TestDatabaseSetup {
        let setup = TestDatabaseSetup()
        try await setup.initialize()
        return setup
    }
}

/// Test-specific managers that use isolated database
public struct TestManagers {
    public let sessionManager = SessionManager.shared
    public let taskManager = TaskManager.shared
    public let dependencyManager = DependencyManager.shared
    
    public init() {}
}