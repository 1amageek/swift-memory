import Foundation
import Testing
@testable import SwiftMemory

@Suite("GraphDatabase Setup Tests")
struct GraphDatabaseSetupTests {
    
    @Test("Database initialization should succeed")
    func testInitialization() async throws {
        let context = try await GraphDatabaseSetup.shared.context()
        #expect(context != nil)
    }
    
    @Test("Multiple initialization calls should be safe")
    func testMultipleInitialization() async throws {
        // Get context multiple times
        let context1 = try await GraphDatabaseSetup.shared.context()
        let context2 = try await GraphDatabaseSetup.shared.context()
        
        #expect(context1 != nil)
        #expect(context2 != nil)
        
        // Both contexts should work
        let session1 = Session(title: "Test 1")
        let saved1 = try await context1.save(session1)
        #expect(saved1.id != UUID())
        
        let session2 = Session(title: "Test 2")
        let saved2 = try await context2.save(session2)
        #expect(saved2.id != UUID())
    }
    
    @Test("Context should be reusable for multiple operations")
    func testContextReuse() async throws {
        let context = try await GraphDatabaseSetup.shared.context()
        
        // Create a session
        let session = Session(title: "Reusable Test")
        let saved = try await context.save(session)
        
        // Fetch the session
        let fetched = try await context.fetchOne(Session.self, id: saved.id)
        #expect(fetched?.title == "Reusable Test")
        
        // Create a task using the same context
        let task = Task(
            title: "Test Task",
            description: "Testing context reuse",
            difficulty: 3
        )
        let savedTask = try await context.save(task)
        #expect(savedTask.title == "Test Task")
        
        // Create relationship using raw query
        _ = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID}), (t:Task {id: $taskID})
            MERGE (s)-[r:HasTask]->(t)
            SET r.order = 1
            RETURN r
            """,
            bindings: ["sessionID": saved.id, "taskID": savedTask.id]
        )
        
        // Verify relationship was created
        let result = try await context.raw(
            """
            MATCH (s:Session {id: $sessionID})-[:HasTask]->(t:Task)
            RETURN COUNT(t) as count
            """,
            bindings: ["sessionID": saved.id]
        )
        
        if result.hasNext(),
           let tuple = try result.getNext(),
           let dict = try? tuple.getAsDictionary(),
           let count = dict["count"] as? Int64 {
            #expect(count == 1)
        } else {
            Issue.record("Failed to verify task relationship")
        }
    }
    
    @Test("Database should handle concurrent access")
    func testConcurrentAccess() async throws {
        // Create multiple sessions concurrently
        let results = await withTaskGroup(of: Session?.self) { group in
            for i in 1...5 {
                group.addTask {
                    do {
                        let context = try await GraphDatabaseSetup.shared.context()
                        let session = Session(title: "Concurrent \(i)")
                        return try await context.save(session)
                    } catch {
                        return nil
                    }
                }
            }
            
            var sessions: [Session] = []
            for await session in group {
                if let session = session {
                    sessions.append(session)
                }
            }
            return sessions
        }
        
        #expect(results.count == 5)
        
        // Verify all sessions have unique IDs
        let ids = results.map { $0.id }
        #expect(Set(ids).count == 5)
    }
}