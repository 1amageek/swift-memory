import Foundation
import Testing
@testable import SwiftMemory

@Suite("Task Manager Tests")
struct TaskManagerTests {
    
    // MARK: - Create Tests
    
    @Test("Create task with required fields")
    func testCreateTaskMinimal() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let task = try await context.taskManager.create(
            sessionID: session.id,
            title: "Basic Task"
        )
        
        #expect(task.title == "Basic Task")
        #expect(task.description == nil)
        #expect(task.status == .pending)
        #expect(task.difficulty == 3) // Default
        #expect(task.assignee == nil)
        #expect(task.id != UUID())
    }
    
    @Test("Create task with all fields")
    func testCreateTaskComplete() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let task = try await context.taskManager.create(
            sessionID: session.id,
            title: "Complete Task",
            description: "A task with all fields",
            difficulty: 4,
            assignee: "Alice"
        )
        
        #expect(task.title == "Complete Task")
        #expect(task.description == "A task with all fields")
        #expect(task.status == .pending)
        #expect(task.difficulty == 4)
        #expect(task.assignee == "Alice")
    }
    
    @Test("Create task with parent")
    func testCreateSubtask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let parent = try await context.helpers.createSampleTask(in: session, title: "Parent Task")
        
        let child = try await context.taskManager.create(
            sessionID: session.id,
            title: "Child Task",
            parentTaskID: parent.id
        )
        
        #expect(child.title == "Child Task")
        
        // Verify parent-child relationship exists by querying subtasks
        let subtasks = try await context.taskManager.list(parentTaskID: parent.id)
        #expect(subtasks.contains { $0.id == child.id })
    }
    
    @Test("Create task with invalid session throws error")
    func testCreateTaskInvalidSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeSessionID = UUID()
        
        await context.helpers.expectMemoryError(.sessionNotFound(fakeSessionID)) {
            try await context.taskManager.create(
                sessionID: fakeSessionID,
                title: "Task"
            )
        }
    }
    
    @Test("Create task with invalid parent throws error")
    func testCreateTaskInvalidParent() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let fakeParentID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeParentID)) {
            try await context.taskManager.create(
                sessionID: session.id,
                title: "Task",
                parentTaskID: fakeParentID
            )
        }
    }
    
    @Test("Create task with invalid difficulty throws error")
    func testCreateTaskInvalidDifficulty() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        await context.helpers.expectMemoryError(.invalidDifficulty(10)) {
            try await context.taskManager.create(
                sessionID: session.id,
                title: "Task",
                difficulty: 10
            )
        }
    }
    
    // MARK: - Get Tests
    
    @Test("Get existing task")
    func testGetTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        
        let fetched = try await context.taskManager.get(id: task.id)
        
        context.helpers.assertTasksEqual(fetched, task)
    }
    
    @Test("Get task with parent")
    func testGetTaskWithParent() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (parent, child, _) = try await context.helpers.createTaskHierarchy(in: session)
        
        // Verify child task is returned
        let childTask = try await context.taskManager.get(id: child.id)
        #expect(childTask.id == child.id)
        
        // Verify it's listed as a subtask of parent
        let subtasks = try await context.taskManager.list(parentTaskID: parent.id)
        #expect(subtasks.contains { $0.id == child.id })
    }
    
    @Test("Get task with children")
    func testGetTaskWithChildren() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (parent, child, grandchild) = try await context.helpers.createTaskHierarchy(in: session)
        
        // Get parent's children
        let parentChildren = try await context.taskManager.list(parentTaskID: parent.id)
        #expect(parentChildren.count == 1)
        #expect(parentChildren.first?.id == child.id)
        
        // Get child's children
        let childChildren = try await context.taskManager.list(parentTaskID: child.id)
        #expect(childChildren.count == 1)
        #expect(childChildren.first?.id == grandchild.id)
    }
    
    @Test("Get task with dependencies")
    func testGetTaskWithDependencies() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (first, second, third) = try await context.helpers.createDependencyChain(in: session)
        
        // Get second task's blockers
        let blockers = try await context.dependencyManager.getBlockers(taskID: second.id)
        #expect(blockers.count == 1)
        #expect(blockers.first?.id == first.id)
        
        // Get second task's blocking
        let blocking = try await context.dependencyManager.getBlocking(taskID: second.id)
        #expect(blocking.count == 1)
        #expect(blocking.first?.id == third.id)
    }
    
    @Test("Get task hierarchy")
    func testGetTaskHierarchy() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (parent, child, grandchild) = try await context.helpers.createTaskHierarchy(in: session)
        
        // Verify hierarchy by checking parent-child relationships
        let parentChildren = try await context.taskManager.list(parentTaskID: parent.id)
        #expect(parentChildren.contains { $0.id == child.id })
        
        let childChildren = try await context.taskManager.list(parentTaskID: child.id)
        #expect(childChildren.contains { $0.id == grandchild.id })
    }
    
    @Test("Get task in session")
    func testGetTaskInSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession(title: "Test Session")
        let task = try await context.helpers.createSampleTask(in: session)
        
        // Verify task is in session's task list
        let tasksInSession = try await context.taskManager.list(sessionID: session.id)
        #expect(tasksInSession.contains { $0.id == task.id })
    }
    
    @Test("Get non-existent task throws error")
    func testGetNonExistentTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await context.taskManager.get(id: fakeID)
        }
    }
    
    // MARK: - List Tests
    
    @Test("List all tasks in session")
    func testListTasksInSession() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await context.helpers.createSampleTask(in: session, title: "Task 3")
        
        let tasks = try await context.taskManager.list(sessionID: session.id)
        
        #expect(tasks.count >= 3)
        context.helpers.assertContainsTask(tasks, withID: task1.id)
        context.helpers.assertContainsTask(tasks, withID: task2.id)
        context.helpers.assertContainsTask(tasks, withID: task3.id)
    }
    
    @Test("List tasks by status")
    func testListTasksByStatus() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (pending, inProgress, done, cancelled) = try await context.helpers.createTasksWithStatuses(in: session)
        
        // List pending tasks
        let pendingTasks = try await context.taskManager.list(
            sessionID: session.id,
            status: .pending
        )
        context.helpers.assertContainsTask(pendingTasks, withID: pending.id)
        context.helpers.assertDoesNotContainTask(pendingTasks, withID: done.id)
        
        // List in progress tasks
        let inProgressTasks = try await context.taskManager.list(
            sessionID: session.id,
            status: .inProgress
        )
        context.helpers.assertContainsTask(inProgressTasks, withID: inProgress.id)
        context.helpers.assertDoesNotContainTask(inProgressTasks, withID: pending.id)
        
        // List done tasks
        let doneTasks = try await context.taskManager.list(
            sessionID: session.id,
            status: .done
        )
        context.helpers.assertContainsTask(doneTasks, withID: done.id)
        context.helpers.assertDoesNotContainTask(doneTasks, withID: pending.id)
        
        // List cancelled tasks
        let cancelledTasks = try await context.taskManager.list(
            sessionID: session.id,
            status: .cancelled
        )
        context.helpers.assertContainsTask(cancelledTasks, withID: cancelled.id)
        context.helpers.assertDoesNotContainTask(cancelledTasks, withID: done.id)
    }
    
    @Test("List tasks by assignee")
    func testListTasksByAssignee() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let aliceTask = try await context.helpers.createSampleTask(
            in: session,
            title: "Alice's Task",
            assignee: "Alice"
        )
        
        let bobTask = try await context.helpers.createSampleTask(
            in: session,
            title: "Bob's Task",
            assignee: "Bob"
        )
        
        let unassigned = try await context.helpers.createSampleTask(
            in: session,
            title: "Unassigned Task"
        )
        
        // List Alice's tasks
        let aliceTasks = try await context.taskManager.list(
            sessionID: session.id,
            assignee: "Alice"
        )
        context.helpers.assertContainsTask(aliceTasks, withID: aliceTask.id)
        context.helpers.assertDoesNotContainTask(aliceTasks, withID: bobTask.id)
        context.helpers.assertDoesNotContainTask(aliceTasks, withID: unassigned.id)
    }
    
    @Test("List tasks by difficulty range")
    func testListTasksByDifficulty() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let tasks = try await context.helpers.createTasksWithDifficulties(in: session)
        
        // List easy tasks (max difficulty 2)
        let easyTasks = try await context.taskManager.list(
            sessionID: session.id,
            difficultyMax: 2
        )
        #expect(easyTasks.allSatisfy { $0.difficulty <= 2 })
        
        // List medium or easy tasks (max difficulty 3)
        let mediumTasks = try await context.taskManager.list(
            sessionID: session.id,
            difficultyMax: 3
        )
        #expect(mediumTasks.allSatisfy { $0.difficulty <= 3 })
        
        // List all tasks - no difficulty filter
        let allTasks = try await context.taskManager.list(
            sessionID: session.id
        )
        #expect(allTasks.count >= tasks.count)
    }
    
    @Test("List ready tasks")
    func testListReadyTasks() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        // Create dependency chain
        let blocker = try await context.helpers.createSampleTask(in: session, title: "Blocker")
        let blocked = try await context.helpers.createSampleTask(in: session, title: "Blocked")
        let independent = try await context.helpers.createSampleTask(in: session, title: "Independent")
        
        try await context.dependencyManager.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // List ready tasks - should not include blocked
        let readyTasks = try await context.taskManager.list(
            sessionID: session.id,
            readyOnly: true
        )
        
        context.helpers.assertContainsTask(readyTasks, withID: blocker.id)
        context.helpers.assertContainsTask(readyTasks, withID: independent.id)
        context.helpers.assertDoesNotContainTask(readyTasks, withID: blocked.id)
        
        // Mark blocker as done
        _ = try await context.taskManager.update(
            id: blocker.id,
            status: .done
        )
        
        // Now blocked should be ready
        let readyAfterCompletion = try await context.taskManager.list(
            sessionID: session.id,
            readyOnly: true
        )
        
        context.helpers.assertContainsTask(readyAfterCompletion, withID: blocked.id)
        context.helpers.assertContainsTask(readyAfterCompletion, withID: independent.id)
        context.helpers.assertDoesNotContainTask(readyAfterCompletion, withID: blocker.id) // Done tasks not included
    }
    
    @Test("List tasks with subtasks")
    func testListTasksWithSubtasks() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (parent, child, _) = try await context.helpers.createTaskHierarchy(in: session)
        
        // List parent's subtasks
        let parentSubtasks = try await context.taskManager.list(parentTaskID: parent.id)
        #expect(parentSubtasks.count == 1)
        #expect(parentSubtasks.first?.id == child.id)
    }
    
    // MARK: - Update Tests
    
    @Test("Update task properties")
    func testUpdateTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        
        let updated = try await context.taskManager.update(
            id: task.id,
            title: "Updated Title",
            description: "Updated Description",
            status: .inProgress,
            assignee: "Bob",
            difficulty: 5
        )
        
        #expect(updated.title == "Updated Title")
        #expect(updated.description == "Updated Description")
        #expect(updated.status == TaskStatus.inProgress)
        #expect(updated.difficulty == 5)
        #expect(updated.assignee == "Bob")
        
        // Verify persistence
        let fetched = try await context.taskManager.get(id: task.id)
        #expect(fetched.title == "Updated Title")
    }
    
    @Test("Update task to cancelled with reason")
    func testCancelTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        
        let cancelled = try await context.taskManager.update(
            id: task.id,
            status: .cancelled,
            cancelReason: "No longer needed"
        )
        
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.cancelReason == "No longer needed")
    }
    
    @Test("Batch update tasks")
    func testBatchUpdate() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await context.helpers.createSampleTask(in: session, title: "Task 3")
        
        let updated = try await context.taskManager.updateBatch(
            taskIDs: [task1.id, task2.id, task3.id],
            status: .inProgress,
            assignee: "Team"
        )
        
        #expect(updated.count == 3)
        #expect(updated.allSatisfy { $0.status == TaskStatus.inProgress })
        #expect(updated.allSatisfy { $0.assignee == "Team" })
    }
    
    @Test("Update non-existent task throws error")
    func testUpdateNonExistentTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await context.taskManager.update(
                id: fakeID,
                title: "New Title"
            )
        }
    }
    
    // MARK: - Reorder Tests
    
    @Test("Reorder tasks in session")
    func testReorderTasks() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        
        let task1 = try await context.helpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await context.helpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await context.helpers.createSampleTask(in: session, title: "Task 3")
        
        // Reorder: 3, 1, 2
        try await context.taskManager.reorder(
            sessionID: session.id,
            orderedIds: [task3.id, task1.id, task2.id]
        )
        
        // Verify order
        let ordered = try await context.taskManager.list(sessionID: session.id)
        
        // Find indices
        let index1 = ordered.firstIndex { $0.id == task1.id }
        let index2 = ordered.firstIndex { $0.id == task2.id }
        let index3 = ordered.firstIndex { $0.id == task3.id }
        
        if let i1 = index1, let i2 = index2, let i3 = index3 {
            #expect(i3 < i1) // task3 comes before task1
            #expect(i1 < i2) // task1 comes before task2
        } else {
            Issue.record("Failed to find all tasks in ordered list")
        }
    }
    
    @Test("Reorder with invalid task throws error")
    func testReorderInvalidTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        let fakeID = UUID()
        
        do {
            try await context.taskManager.reorder(
                sessionID: session.id,
                orderedIds: [task.id, fakeID]
            )
            Issue.record("Expected error for invalid task ID")
        } catch {
            // Expected error
            #expect(error is MemoryError)
        }
    }
    
    // MARK: - Delete Tests
    
    @Test("Delete task without cascade")
    func testDeleteTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let task = try await context.helpers.createSampleTask(in: session)
        
        try await context.taskManager.delete(id: task.id, cascade: false)
        
        await context.helpers.expectMemoryError(.taskNotFound(task.id)) {
            try await context.taskManager.get(id: task.id)
        }
    }
    
    @Test("Delete task with cascade removes subtasks")
    func testDeleteTaskWithCascade() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (parent, child, grandchild) = try await context.helpers.createTaskHierarchy(in: session)
        
        // Delete parent with cascade
        try await context.taskManager.delete(id: parent.id, cascade: true)
        
        // Verify all are deleted
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
    
    @Test("Delete task removes dependencies")
    func testDeleteTaskRemovesDependencies() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let session = try await context.helpers.createSampleSession()
        let (first, second, third) = try await context.helpers.createDependencyChain(in: session)
        
        // Delete middle task
        try await context.taskManager.delete(id: second.id, cascade: false)
        
        // First should have no tasks it's blocking
        let firstBlocking = try await context.dependencyManager.getBlocking(taskID: first.id)
        #expect(firstBlocking.isEmpty == true)
        
        // Third should have no blockers
        let thirdBlockers = try await context.dependencyManager.getBlockers(taskID: third.id)
        #expect(thirdBlockers.isEmpty == true)
    }
    
    @Test("Delete non-existent task throws error")
    func testDeleteNonExistentTask() async throws {
        let context = try await TestContext.create(testName: #function)
        defer { _Concurrency.Task { await context.cleanup() } }
        
        let fakeID = UUID()
        
        await context.helpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await context.taskManager.delete(id: fakeID, cascade: false)
        }
    }
}