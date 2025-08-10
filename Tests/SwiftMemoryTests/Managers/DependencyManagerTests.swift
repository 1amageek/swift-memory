import Foundation
import Testing
@testable import SwiftMemory

@Suite("Dependency Manager Tests")
struct DependencyManagerTests {
    
    // MARK: - Add Dependency Tests
    
    @Test("Add simple dependency")
    func testAddDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session, title: "Blocker")
        let blocked = try await context.helpers.createSampleTask(in: session, title: "Blocked")
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Verify dependency exists
        let blockers = try await context.dependencyManager.getBlockers(taskID: blocked.id)
        
        #expect(blockers.count == 1)
        #expect(blockers.first?.id == blocker.id)
    }
    
    @Test("Task cannot block itself")
    func testSelfLoopPrevention() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session, title: "Task")
        
        // Try to make task block itself
        await context.helpers.expectMemoryError(code: .invalidInput) {
            try await context.dependencyManager.add(
                blockerID: task.id,
                blockedID: task.id
            )
        }
        
        // Verify no self-dependency was created
        let blockers = try await context.dependencyManager.getBlockers(taskID: task.id)
        #expect(blockers.isEmpty)
        
        let blocking = try await context.dependencyManager.getBlocking(taskID: task.id)
        #expect(blocking.isEmpty)
    }
    
    @Test("Add dependency chain")
    func testAddDependencyChain() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (first, second, third) = try await context.helpers.createDependencyChain(in: session)
        
        // Verify first blocks second
        let secondBlockers = try await context.dependencyManager.getBlockers(taskID: second.id)
        #expect(secondBlockers.contains { $0.id == first.id } == true)
        
        // Verify second blocks third
        let thirdBlockers = try await context.dependencyManager.getBlockers(taskID: third.id)
        #expect(thirdBlockers.contains { $0.id == second.id } == true)
        
        // Verify first indirectly blocks third (chain)
        let chain = try await context.dependencyManager.getDependencyChain(taskID: third.id)
        #expect(chain.upstream.count == 2)
        #expect(chain.upstream.contains { $0.task.id == first.id } == true)
        #expect(chain.upstream.contains { $0.task.id == second.id } == true)
    }
    
    @Test("Add circular dependency throws error")
    func testAddCircularDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        
        // Create initial dependency
        try await context.dependencyManager.add(
            blockerID: task1.id,
            blockedID: task2.id
        )
        
        // Try to create circular dependency
        await context.helpers.expectMemoryError(
            .circularDependency(blocker: task2.id, blocked: task1.id)
        ) {
            try await context.dependencyManager.add(
                blockerID: task2.id,
                blockedID: task1.id
            )
        }
    }
    
    @Test("Add indirect circular dependency throws error")
    func testAddIndirectCircularDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (first, second, third) = try await context.helpers.createDependencyChain(in: session)
        
        // Try to make third block first (creating a cycle)
        await context.helpers.expectMemoryError(
            .circularDependency(blocker: third.id, blocked: first.id)
        ) {
            try await context.dependencyManager.add(
                blockerID: third.id,
                blockedID: first.id
            )
        }
    }
    
    @Test("Add duplicate dependency is idempotent")
    func testAddDuplicateDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session)
        let blocked = try await context.helpers.createSampleTask(in: session)
        
        // Add dependency twice
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Should still have only one dependency
        let blockers = try await context.dependencyManager.getBlockers(taskID: blocked.id)
        
        #expect(blockers.count == 1)
    }
    
    @Test("Add dependency with non-existent blocker throws error")
    func testAddDependencyInvalidBlocker() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await context.dependencyManager.add(
                blockerID: fakeID,
                blockedID: task.id
            )
        }
    }
    
    @Test("Add dependency with non-existent blocked throws error")
    func testAddDependencyInvalidBlocked() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await context.dependencyManager.add(
                blockerID: task.id,
                blockedID: fakeID
            )
        }
    }
    
    // MARK: - Remove Dependency Tests
    
    @Test("Remove existing dependency")
    func testRemoveDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session)
        let blocked = try await context.helpers.createSampleTask(in: session)
        
        // Add dependency
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Remove dependency
        try await context.dependencyManager.remove(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Verify dependency is removed
        let blockers = try await context.dependencyManager.getBlockers(taskID: blocked.id)
        
        #expect(blockers.isEmpty == true)
    }
    
    @Test("Remove non-existent dependency is safe")
    func testRemoveNonExistentDependency() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task1 = try await context.helpers.createSampleTask(in: session)
        let task2 = try await context.helpers.createSampleTask(in: session)
        
        // Remove non-existent dependency (should not throw)
        try await context.dependencyManager.remove(
            blockerID: task1.id,
            blockedID: task2.id
        )
        
        // Verify no dependencies exist
        let blockers = try await context.dependencyManager.getBlockers(taskID: task2.id)
        
        #expect(blockers.isEmpty == true)
    }
    
    @Test("Remove dependency from chain")
    func testRemoveDependencyFromChain() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (first, second, third) = try await context.helpers.createDependencyChain(in: session)
        
        // Remove middle link
        try await context.dependencyManager.remove(
            blockerID: second.id,
            blockedID: third.id
        )
        
        // Third should no longer be blocked by second
        let thirdBlockers = try await context.dependencyManager.getBlockers(taskID: third.id)
        #expect(thirdBlockers.isEmpty == true)
        
        // But first -> second should still exist
        let secondBlockers = try await context.dependencyManager.getBlockers(taskID: second.id)
        #expect(secondBlockers.count == 1)
        #expect(secondBlockers.first?.id == first.id)
    }
    
    // MARK: - Query Tests
    
    @Test("Get task blockers")
    func testGetBlockers() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker1 = try await context.helpers.createSampleTask(in: session, title: "Blocker 1")
        let blocker2 = try await context.helpers.createSampleTask(in: session, title: "Blocker 2")
        let blocked = try await context.helpers.createSampleTask(in: session, title: "Blocked")
        
        try await context.dependencyManager.add(
            blockerID: blocker1.id,
            blockedID: blocked.id
        )
        
        try await context.dependencyManager.add(
            blockerID: blocker2.id,
            blockedID: blocked.id
        )
        
        let blockers = try await context.dependencyManager.getBlockers(taskID: blocked.id)
        
        #expect(blockers.count == 2)
        #expect(blockers.contains { $0.id == blocker1.id } == true)
        #expect(blockers.contains { $0.id == blocker2.id } == true)
    }
    
    @Test("Get tasks blocked by task")
    func testGetBlocking() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session, title: "Blocker")
        let blocked1 = try await context.helpers.createSampleTask(in: session, title: "Blocked 1")
        let blocked2 = try await context.helpers.createSampleTask(in: session, title: "Blocked 2")
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked1.id
        )
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked2.id
        )
        
        let blocking = try await context.dependencyManager.getBlocking(taskID: blocker.id)
        
        #expect(blocking.count == 2)
        #expect(blocking.contains { $0.id == blocked1.id } == true)
        #expect(blocking.contains { $0.id == blocked2.id } == true)
    }
    
    @Test("Get dependency chain")
    func testGetDependencyChain() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        // Create a complex dependency graph
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await context.helpers.createSampleTask(in: session, title: "Task 3")
        let task4 = try await context.helpers.createSampleTask(in: session, title: "Task 4")
        let task5 = try await context.helpers.createSampleTask(in: session, title: "Task 5")
        
        // Create dependencies: 1->3, 2->3, 3->4, 4->5
        try await context.dependencyManager.add(blockerID: task1.id, blockedID: task3.id)
        try await context.dependencyManager.add(blockerID: task2.id, blockedID: task3.id)
        try await context.dependencyManager.add(blockerID: task3.id, blockedID: task4.id)
        try await context.dependencyManager.add(blockerID: task4.id, blockedID: task5.id)
        
        // Get chain for task5
        let chain = try await context.dependencyManager.getDependencyChain(taskID: task5.id)
        
        // Should include all upstream dependencies
        #expect(chain.upstream.count == 4)
        #expect(chain.upstream.contains { $0.task.id == task1.id } == true)
        #expect(chain.upstream.contains { $0.task.id == task2.id } == true)
        #expect(chain.upstream.contains { $0.task.id == task3.id } == true)
        #expect(chain.upstream.contains { $0.task.id == task4.id } == true)
    }
    
    @Test("Check if task is blocked")
    func testIsBlocked() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session, title: "Blocker")
        let blocked = try await context.helpers.createSampleTask(in: session, title: "Blocked")
        let independent = try await context.helpers.createSampleTask(in: session, title: "Independent")
        
        // Set blocker as pending
        _ = try await context.taskManager.update(id: blocker.id, status: .pending)
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Check blocked status
        let isBlocked = try await context.dependencyManager.isTaskBlocked(taskID: blocked.id)
        #expect(isBlocked == true)
        
        // Check independent status
        let isIndependentBlocked = try await context.dependencyManager.isTaskBlocked(taskID: independent.id)
        #expect(isIndependentBlocked == false)
        
        // Mark blocker as done
        _ = try await context.taskManager.update(id: blocker.id, status: .done)
        
        // Now blocked should not be blocked
        let isStillBlocked = try await context.dependencyManager.isTaskBlocked(taskID: blocked.id)
        #expect(isStillBlocked == false)
    }
    
    @Test("Get dependencies for non-existent task")
    func testGetDependenciesNonExistentTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        // getBlockers should return empty array for non-existent task
        let blockers = try await context.dependencyManager.getBlockers(taskID: fakeID)
        #expect(blockers.isEmpty)
    }
    
    // MARK: - Complex Scenarios
    
    @Test("Dependencies with task status changes")
    func testDependenciesWithStatusChanges() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await context.helpers.createSampleTask(in: session, title: "Task 3")
        
        // Create dependencies
        try await context.dependencyManager.add(blockerID: task1.id, blockedID: task2.id)
        try await context.dependencyManager.add(blockerID: task2.id, blockedID: task3.id)
        
        // Initially, task2 and task3 should be blocked
        let task2Blocked = try await context.dependencyManager.isTaskBlocked(taskID: task2.id)
        #expect(task2Blocked == true)
        
        let task3Blocked = try await context.dependencyManager.isTaskBlocked(taskID: task3.id)
        #expect(task3Blocked == true)
        
        // Complete task1
        _ = try await context.taskManager.update(id: task1.id, status: .done)
        
        // Now task2 should be unblocked, but task3 still blocked
        let task2Unblocked = try await context.dependencyManager.isTaskBlocked(taskID: task2.id)
        #expect(task2Unblocked == false)
        
        let task3StillBlocked = try await context.dependencyManager.isTaskBlocked(taskID: task3.id)
        #expect(task3StillBlocked == true)
        
        // Complete task2
        _ = try await context.taskManager.update(id: task2.id, status: .done)
        
        // Now task3 should be unblocked
        let task3Unblocked = try await context.dependencyManager.isTaskBlocked(taskID: task3.id)
        #expect(task3Unblocked == false)
    }
    
    @Test("Dependencies with cancelled tasks")
    func testDependenciesWithCancelledTasks() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let blocker = try await context.helpers.createSampleTask(in: session, title: "Blocker")
        let blocked = try await context.helpers.createSampleTask(in: session, title: "Blocked")
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // Cancel the blocker
        _ = try await context.taskManager.update(
            id: blocker.id,
            status: .cancelled,
            cancelReason: "Not needed"
        )
        
        // Blocked task should now be unblocked (cancelled counts as completed)
        let isBlocked = try await context.dependencyManager.isTaskBlocked(taskID: blocked.id)
        #expect(isBlocked == false)
    }
}