import Foundation
import Testing
import Kuzu
import KuzuSwiftExtension
@testable import SwiftMemory

@Suite("Minimal KuzuDB Test")
struct MinimalKuzuTest {
    
    @Test("Test GraphContext creation only")
    func testGraphContextCreation() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-kuzu-\(UUID().uuidString)")
            .path
        
        print("📍 Database path: \(dbPath)")
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                enableLogging: true  // Enable logging to see more details
            )
        )
        
        print("📍 Creating GraphContext...")
        let context = try await GraphContext(configuration: configuration)
        print("✅ GraphContext created successfully")
        
        // Try a simple query
        print("📍 Testing simple query...")
        let result = try await context.raw("RETURN 1 AS test")
        print("✅ Query executed successfully")
        
        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test minimal schema creation")
    func testMinimalSchemaCreation() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-kuzu-schema-\(UUID().uuidString)")
            .path
        
        print("📍 Database path: \(dbPath)")
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                enableLogging: true
            )
        )
        
        print("📍 Creating GraphContext...")
        let context = try await GraphContext(configuration: configuration)
        print("✅ GraphContext created")
        
        // Try creating a simple node table manually
        print("📍 Creating simple node table...")
        let createNodeQuery = """
            CREATE NODE TABLE TestNode (
                id UUID PRIMARY KEY,
                title STRING
            )
        """
        _ = try await context.raw(createNodeQuery)
        print("✅ Node table created")
        
        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test MigrationManager with single model")
    func testMigrationManagerSingleModel() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-kuzu-migration-\(UUID().uuidString)")
            .path
        
        print("📍 Database path: \(dbPath)")
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                enableLogging: true
            )
        )
        
        print("📍 Creating GraphContext...")
        let context = try await GraphContext(configuration: configuration)
        print("✅ GraphContext created")
        
        print("📍 Creating MigrationManager...")
        let migrationManager = MigrationManager(
            context: context,
            policy: .safe
        )
        
        // Try migrating just Session model
        print("📍 Migrating Session model only...")
        do {
            try await migrationManager.migrate(types: [Session.self])
            print("✅ Session model migrated successfully")
        } catch {
            print("❌ Migration failed: \(error)")
            if let memoryError = error as? MemoryError {
                print("   MemoryError: \(memoryError)")
            }
            throw error
        }
        
        // Clean up
        try? FileManager.default.removeItem(atPath: dbPath)
    }
}