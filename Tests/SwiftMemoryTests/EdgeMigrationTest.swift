import Foundation
import Testing
import Kuzu
import KuzuSwiftExtension
@testable import SwiftMemory

@Suite("Edge Migration Test")
struct EdgeMigrationTest {
    
    @Test("Test migrating nodes only")
    func testNodesOnlyMigration() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-nodes-\(UUID().uuidString)")
            .path
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: true
            )
        )
        
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safeOnly)
        
        print("📍 Migrating Session and Task nodes...")
        try await migrationManager.migrate(types: [Session.self, Task.self])
        print("✅ Nodes migrated successfully")
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test adding HasTask edge")
    func testHasTaskEdgeMigration() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-hastask-\(UUID().uuidString)")
            .path
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: true
            )
        )
        
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safeOnly)
        
        print("📍 Migrating nodes and HasTask edge...")
        do {
            try await migrationManager.migrate(types: [
                Session.self,
                Task.self,
                HasTask.self
            ])
            print("✅ HasTask edge migrated successfully")
        } catch {
            print("❌ HasTask migration failed: \(error)")
            throw error
        }
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test adding SubTaskOf edge")
    func testSubTaskOfEdgeMigration() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-subtaskof-\(UUID().uuidString)")
            .path
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: true
            )
        )
        
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safeOnly)
        
        print("📍 Migrating nodes and SubTaskOf edge...")
        do {
            try await migrationManager.migrate(types: [
                Session.self,
                Task.self,
                SubTaskOf.self
            ])
            print("✅ SubTaskOf edge migrated successfully")
        } catch {
            print("❌ SubTaskOf migration failed: \(error)")
            throw error
        }
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test adding Blocks edge")
    func testBlocksEdgeMigration() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-blocks-\(UUID().uuidString)")
            .path
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: true
            )
        )
        
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safeOnly)
        
        print("📍 Migrating nodes and Blocks edge...")
        do {
            try await migrationManager.migrate(types: [
                Session.self,
                Task.self,
                Blocks.self
            ])
            print("✅ Blocks edge migrated successfully")
        } catch {
            print("❌ Blocks migration failed: \(error)")
            throw error
        }
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    @Test("Test all models together")
    func testAllModelsMigration() async throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-all-\(UUID().uuidString)")
            .path
        
        let configuration = GraphConfiguration(
            databasePath: dbPath,
            options: GraphConfiguration.Options(
                migrationPolicy: .safeOnly,
                enableLogging: true
            )
        )
        
        let context = try await GraphContext(configuration: configuration)
        let migrationManager = MigrationManager(context: context, policy: .safeOnly)
        
        print("📍 Migrating all models...")
        do {
            try await migrationManager.migrate(types: [
                Session.self,
                Task.self,
                HasTask.self,
                SubTaskOf.self,
                Blocks.self
            ])
            print("✅ All models migrated successfully")
        } catch {
            print("❌ Full migration failed: \(error)")
            throw error
        }
        
        try? FileManager.default.removeItem(atPath: dbPath)
    }
}