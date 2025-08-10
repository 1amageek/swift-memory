import Foundation
import Testing
@testable import SwiftMemory

@Suite("Session Manager Tests")
struct SessionManagerTests {
    
    // MARK: - Create Tests
    
    @Test("Create session with valid title")
    func testCreateSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.sessionManager.create(title: "Sprint Planning")
        
        #expect(session.title == "Sprint Planning")
        #expect(session.id != UUID())
        #expect(session.startedAt.timeIntervalSinceNow < 1) // Recently created
    }
    
    @Test("Create multiple sessions")
    func testCreateMultipleSessions() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session1 = try await context.sessionManager.create(title: "Session 1")
        let session2 = try await context.sessionManager.create(title: "Session 2")
        let session3 = try await context.sessionManager.create(title: "Session 3")
        
        #expect(session1.id != session2.id)
        #expect(session2.id != session3.id)
        #expect(session1.id != session3.id)
        
        #expect(session1.title == "Session 1")
        #expect(session2.title == "Session 2")
        #expect(session3.title == "Session 3")
    }
    
    @Test("Create session with empty title should succeed")
    func testCreateSessionWithEmptyTitle() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.sessionManager.create(title: "")
        #expect(session.title == "")
        #expect(session.id != UUID())
    }
    
    // MARK: - Get Tests
    
    @Test("Get existing session")
    func testGetExistingSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let created = try await context.sessionManager.create(title: "Test Session")
        let fetched = try await context.sessionManager.get(id: created.id)
        
        #expect(fetched.id == created.id)
        #expect(fetched.title == created.title)
        #expect(fetched.startedAt == created.startedAt)
    }
    
    @Test("Get non-existent session throws error")
    func testGetNonExistentSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        do {
            _ = try await context.sessionManager.get(id: fakeID)
            Issue.record("Expected MemoryError.sessionNotFound but no error was thrown")
        } catch let error as MemoryError {
            switch error {
            case .sessionNotFound(let id):
                #expect(id == fakeID)
            default:
                Issue.record("Expected sessionNotFound but got \(error)")
            }
            
            // Verify error has recovery suggestion
            #expect(error.recoverySuggestion != nil)
            #expect(error.recoverySuggestion?.contains("memory.session.create") == true)
        } catch {
            Issue.record("Expected MemoryError but got \(error)")
        }
    }
    
    // MARK: - List Tests
    
    @Test("List all sessions")
    func testListAllSessions() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        // Create test sessions
        let session1 = try await context.sessionManager.create(title: "Session 1")
        let session2 = try await context.sessionManager.create(title: "Session 2")
        let session3 = try await context.sessionManager.create(title: "Session 3")
        
        let sessions = try await context.sessionManager.list()
        
        #expect(sessions.contains { $0.id == session1.id })
        #expect(sessions.contains { $0.id == session2.id })
        #expect(sessions.contains { $0.id == session3.id })
    }
    
    @Test("List sessions with date filter - after")
    func testListSessionsWithStartedAfter() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let before = Date()
        
        // Small delay to ensure time difference  
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        let session1 = try await context.sessionManager.create(title: "Session 1")
        let session2 = try await context.sessionManager.create(title: "Session 2")
        
        let filtered = try await context.sessionManager.list(startedAfter: before)
        
        #expect(filtered.contains { $0.id == session1.id })
        #expect(filtered.contains { $0.id == session2.id })
        
        // Test with future date
        let future = Date().addingTimeInterval(3600) // 1 hour in future
        let empty = try await context.sessionManager.list(startedAfter: future)
        
        #expect(!empty.contains { $0.id == session1.id })
        #expect(!empty.contains { $0.id == session2.id })
    }
    
    @Test("List sessions with date filter - before")
    func testListSessionsWithStartedBefore() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session1 = try await context.sessionManager.create(title: "Session 1")
        
        // Small delay
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        let middle = Date()
        
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        let session2 = try await context.sessionManager.create(title: "Session 2")
        
        let beforeMiddle = try await context.sessionManager.list(startedBefore: middle)
        #expect(beforeMiddle.contains { $0.id == session1.id })
        #expect(!beforeMiddle.contains { $0.id == session2.id })
    }
    
    @Test("List sessions with date range filter")
    func testListSessionsWithDateRange() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let start = Date()
        
        let session1 = try await context.sessionManager.create(title: "In Range 1")
        let session2 = try await context.sessionManager.create(title: "In Range 2")
        
        let end = Date().addingTimeInterval(1)
        
        let inRange = try await context.sessionManager.list(
            startedAfter: start.addingTimeInterval(-1),
            startedBefore: end
        )
        
        #expect(inRange.contains { $0.id == session1.id })
        #expect(inRange.contains { $0.id == session2.id })
    }
    
    @Test("List empty sessions")
    func testListEmptySessions() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        // Create a session first to ensure database is initialized
        let session = try await context.sessionManager.create(title: "Test")
        
        // Filter with impossible date range
        let past = Date.distantPast
        let farPast = past.addingTimeInterval(-3600)
        
        let empty = try await context.sessionManager.list(
            startedAfter: past,
            startedBefore: farPast
        )
        
        #expect(empty.isEmpty || !empty.contains { $0.id == session.id })
    }
    
    // MARK: - Update Tests
    
    @Test("Update session title")
    func testUpdateSessionTitle() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.sessionManager.create(title: "Original Title")
        let updated = try await context.sessionManager.update(
            id: session.id,
            title: "Updated Title"
        )
        
        #expect(updated.id == session.id)
        #expect(updated.title == "Updated Title")
        #expect(updated.startedAt == session.startedAt) // Should not change
        
        // Verify update persisted
        let fetched = try await context.sessionManager.get(id: session.id)
        #expect(fetched.title == "Updated Title")
    }
    
    @Test("Update non-existent session throws error")
    func testUpdateNonExistentSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(
            .sessionNotFound(fakeID)
        ) {
            try await context.sessionManager.update(id: fakeID, title: "New Title")
        }
    }
    
    // MARK: - Delete Tests
    
    @Test("Delete session without cascade")
    func testDeleteSessionWithoutCascade() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.sessionManager.create(title: "To Delete")
        
        try await context.sessionManager.delete(id: session.id, cascade: false)
        
        // Verify session is deleted
        await context.helpers.expectMemoryError(.sessionNotFound(session.id)) {
            try await context.sessionManager.get(id: session.id)
        }
    }
    
    @Test("Delete session with cascade removes tasks")
    func testDeleteSessionWithCascade() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.createSession(title: "Session with Tasks")
        
        // Create multiple tasks in the session
        let task1 = try await context.createTask(in: session, title: "Task 1")
        let task2 = try await context.createTask(in: session, title: "Task 2")
        let task3 = try await context.createTask(in: session, title: "Task 3")
        
        // Delete session with cascade
        try await context.sessionManager.delete(id: session.id, cascade: true)
        
        // Verify session is deleted
        await context.helpers.expectMemoryError(.sessionNotFound(session.id)) {
            try await context.sessionManager.get(id: session.id)
        }
        
        // Verify all tasks are deleted
        await context.helpers.expectMemoryError(.taskNotFound(task1.id)) {
            try await context.taskManager.get(id: task1.id)
        }
        
        await context.helpers.expectMemoryError(.taskNotFound(task2.id)) {
            try await context.taskManager.get(id: task2.id)
        }
        
        await context.helpers.expectMemoryError(.taskNotFound(task3.id)) {
            try await context.taskManager.get(id: task3.id)
        }
    }
    
    @Test("Delete non-existent session throws error")
    func testDeleteNonExistentSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.sessionNotFound(fakeID)) {
            try await context.sessionManager.delete(id: fakeID, cascade: false)
        }
    }
    
    @Test("Delete session with task hierarchy and cascade")
    func testDeleteSessionWithTaskHierarchy() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.createSession()
        
        // Create task hierarchy
        let (parent, child, grandchild) = try await context.createTaskHierarchy(in: session)
        
        // Delete session with cascade
        try await context.sessionManager.delete(id: session.id, cascade: true)
        
        // Verify all tasks in hierarchy are deleted
        await context.helpers.expectMemoryError(.taskNotFound(parent.id)) {
            try await context.taskManager.get(id: parent.id)
        }
        
        await context.helpers.expectMemoryError(.taskNotFound(child.id)) {
            try await context.taskManager.get(id: child.id)
        }
        
        await context.helpers.expectMemoryError(.taskNotFound(grandchild.id)) {
            try await context.taskManager.get(id: grandchild.id)
        }
    }
}