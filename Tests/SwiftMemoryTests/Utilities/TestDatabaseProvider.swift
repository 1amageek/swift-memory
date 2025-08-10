import Foundation
import Testing
import KuzuSwiftExtension
@testable import SwiftMemory

/// Test-specific database provider that creates isolated database instances
public actor TestDatabaseProvider: DatabaseContextProvider {
    private let testName: String
    private var graphContext: GraphContext?
    private var isInitialized = false
    private let dbPath: String
    
    public init(testName: String) {
        self.testName = testName
        // Create unique database path for this test
        self.dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-memory-test-\(testName)-\(UUID().uuidString)")
            .path
    }
    
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        // Create configuration with test-specific database path
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: false
            )
        )
        
        // Create context
        let context = try await GraphContext(configuration: configuration)
        
        // Apply schema using MigrationManager
        let migrationManager = MigrationManager(
            context: context,
            policy: .safeOnly
        )
        
        let models: [any _KuzuGraphModel.Type] = [
            Session.self,
            Task.self,
            HasTask.self,
            SubTaskOf.self,
            Blocks.self
        ]
        
        try await migrationManager.migrate(types: models)
        
        self.graphContext = context
        isInitialized = true
    }
    
    public func context() async throws -> GraphContext {
        if !isInitialized {
            try await initialize()
        }
        guard let context = graphContext else {
            throw MemoryError.databaseError("Test database not initialized")
        }
        return context
    }
    
    /// Clean up the test database
    public func cleanup() {
        graphContext = nil
        isInitialized = false
        
        // Clean up database files
        try? FileManager.default.removeItem(atPath: dbPath)
    }
}

/// Factory for creating test-specific managers
public struct TestManagerFactory {
    private let provider: TestDatabaseProvider
    
    public init(testName: String) {
        self.provider = TestDatabaseProvider(testName: testName)
    }
    
    public func sessionManager() -> SessionManager {
        SessionManager(contextProvider: provider)
    }
    
    public func taskManager() -> TaskManager {
        TaskManager(contextProvider: provider)
    }
    
    public func dependencyManager() -> DependencyManager {
        DependencyManager(contextProvider: provider)
    }
    
    public func cleanup() async {
        await provider.cleanup()
    }
}