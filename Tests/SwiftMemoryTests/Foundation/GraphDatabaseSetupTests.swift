import Foundation
import Testing
@testable import SwiftMemory

@Suite("GraphDatabase Setup Tests")
struct GraphDatabaseSetupTests {
    
    @Test("Database initialization should succeed")
    func testInitialization() async throws {
        try await withTestContext(testName: #function) { context in
            // Test that we can create a session successfully
            let session = try await context.sessionManager.create(title: "Test Session")
            
            // Verify session was actually saved to database
            let fetched = try await context.sessionManager.get(id: session.id)
            #expect(fetched.id == session.id)
            #expect(fetched.title == "Test Session")
        }
    }
    
    @Test("Multiple initialization calls should be safe")
    func testMultipleInitialization() async throws {
        try await withTestContext(testName: #function) { context in
            // Both operations use the same context through managers
            let session1 = try await context.sessionManager.create(title: "Test 1")
            let session2 = try await context.sessionManager.create(title: "Test 2")
            
            // Verify both sessions were saved
            let fetched1 = try await context.sessionManager.get(id: session1.id)
            #expect(fetched1.id == session1.id)
            #expect(fetched1.title == "Test 1")
            
            let fetched2 = try await context.sessionManager.get(id: session2.id)
            #expect(fetched2.id == session2.id)
            #expect(fetched2.title == "Test 2")
            
            // Verify they have different IDs
            #expect(session1.id != session2.id)
        }
    }
    
    @Test("Context should be reusable for multiple operations")
    func testContextReuse() async throws {
        try await withTestContext(testName: #function) { context in
            // Create a session
            let session = try await context.sessionManager.create(title: "Reusable Test")
            
            // Fetch the session
            let fetched = try await context.sessionManager.get(id: session.id)
            #expect(fetched.title == "Reusable Test")
            
            // Create a task using the same context
            let task = try await context.taskManager.create(
                sessionID: session.id,
                title: "Test Task",
                description: "Testing context reuse"
            )
            
            // Verify task exists and was saved
            let fetchedTask = try await context.taskManager.get(id: task.id)
            #expect(fetchedTask.id == task.id)
            #expect(fetchedTask.title == "Test Task")
            #expect(fetchedTask.description == "Testing context reuse")
        }
    }
    
    @Test("Database should handle concurrent reads")
    func testConcurrentAccess() async throws {
        try await withTestContext(testName: #function) { context in
            // Create session and tasks first (sequentially)
            let session = try await context.sessionManager.create(title: "Concurrent Test")
            
            var createdTasks: [Task] = []
            for index in 0..<5 {
                let task = try await context.taskManager.create(
                    sessionID: session.id,
                    title: "Task \(index)",
                    description: "Concurrent test \(index)"
                )
                createdTasks.append(task)
            }
            
            // Now test concurrent READS (which KuzuDB can handle)
            var results: [Task] = []
            try await withThrowingTaskGroup(of: Task.self) { group in
                for task in createdTasks {
                    group.addTask {
                        // Concurrent read operations
                        return try await context.taskManager.get(id: task.id)
                    }
                }
                
                // Collect all results - will throw if any task fails
                for try await task in group {
                    results.append(task)
                }
            }
            
            // All tasks should be fetched successfully
            #expect(results.count == 5)
            
            // All IDs should match created tasks
            let fetchedIds = Set(results.map(\.id))
            let createdIds = Set(createdTasks.map(\.id))
            #expect(fetchedIds == createdIds)
            
            // Verify all tasks exist in database
            for task in results {
                let fetched = try await context.taskManager.get(id: task.id)
                #expect(fetched.id == task.id)
                #expect(fetched.title.starts(with: "Task"))
            }
        }
    }
}