import Foundation
import Testing
@testable import SwiftMemory

@Suite("Task Manager Tests")
struct TaskManagerTests {
    
    // MARK: - Create Tests
    
    @Test("Create task with required fields")
    func testCreateTaskMinimal() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        let task = try await TaskManager.shared.create(
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
        let session = try await TestHelpers.createSampleSession()
        
        let task = try await TaskManager.shared.create(
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
        let session = try await TestHelpers.createSampleSession()
        let parent = try await TestHelpers.createSampleTask(in: session, title: "Parent Task")
        
        let child = try await TaskManager.shared.create(
            sessionID: session.id,
            title: "Child Task",
            parentTaskID: parent.id
        )
        
        #expect(child.title == "Child Task")
        
        // Verify parent-child relationship exists by querying subtasks
        let subtasks = try await TaskManager.shared.list(parentTaskID: parent.id)
        #expect(subtasks.contains { $0.id == child.id })
    }
    
    @Test("Create task with invalid session throws error")
    func testCreateTaskInvalidSession() async throws {
        let fakeSessionID = UUID()
        
        await TestHelpers.expectMemoryError(.sessionNotFound(fakeSessionID)) {
            try await TaskManager.shared.create(
                sessionID: fakeSessionID,
                title: "Task"
            )
        }
    }
    
    @Test("Create task with invalid parent throws error")
    func testCreateTaskInvalidParent() async throws {
        let session = try await TestHelpers.createSampleSession()
        let fakeParentID = UUID()
        
        await TestHelpers.expectMemoryError(.taskNotFound(fakeParentID)) {
            try await TaskManager.shared.create(
                sessionID: session.id,
                title: "Task",
                parentTaskID: fakeParentID
            )
        }
    }
    
    @Test("Create task with invalid difficulty throws error")
    func testCreateTaskInvalidDifficulty() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        await TestHelpers.expectMemoryError(.invalidDifficulty(10)) {
            try await TaskManager.shared.create(
                sessionID: session.id,
                title: "Task",
                difficulty: 10
            )
        }
    }
    
    // MARK: - Get Tests
    
    @Test("Get existing task")
    func testGetTask() async throws {
        let session = try await TestHelpers.createSampleSession()
        let task = try await TestHelpers.createSampleTask(in: session)
        
        let fetched = try await TaskManager.shared.get(id: task.id)
        
        TestHelpers.assertTasksEqual(fetched, task)
    }
    
    @Test("Get task with parent")
    func testGetTaskWithParent() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (parent, child, _) = try await TestHelpers.createTaskHierarchy(in: session)
        
        // Verify child task is returned
        let childTask = try await TaskManager.shared.get(id: child.id)
        #expect(childTask.id == child.id)
        
        // Verify it's listed as a subtask of parent
        let subtasks = try await TaskManager.shared.list(parentTaskID: parent.id)
        #expect(subtasks.contains { $0.id == child.id })
    }
    
    @Test("Get task with children")
    func testGetTaskWithChildren() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (parent, child, grandchild) = try await TestHelpers.createTaskHierarchy(in: session)
        
        // Get parent's children
        let parentChildren = try await TaskManager.shared.list(parentTaskID: parent.id)
        #expect(parentChildren.count == 1)
        #expect(parentChildren.first?.id == child.id)
        
        // Get child's children
        let childChildren = try await TaskManager.shared.list(parentTaskID: child.id)
        #expect(childChildren.count == 1)
        #expect(childChildren.first?.id == grandchild.id)
    }
    
    @Test("Get task with dependencies")
    func testGetTaskWithDependencies() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (first, second, third) = try await TestHelpers.createDependencyChain(in: session)
        
        // Get second task's blockers
        let blockers = try await DependencyManager.shared.getBlockers(taskID: second.id)
        #expect(blockers.count == 1)
        #expect(blockers.first?.id == first.id)
        
        // Get second task's blocking
        let blocking = try await DependencyManager.shared.getBlocking(taskID: second.id)
        #expect(blocking.count == 1)
        #expect(blocking.first?.id == third.id)
    }
    
    @Test("Get task hierarchy")
    func testGetTaskHierarchy() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (parent, child, grandchild) = try await TestHelpers.createTaskHierarchy(in: session)
        
        // Verify hierarchy by checking parent-child relationships
        let parentChildren = try await TaskManager.shared.list(parentTaskID: parent.id)
        #expect(parentChildren.contains { $0.id == child.id })
        
        let childChildren = try await TaskManager.shared.list(parentTaskID: child.id)
        #expect(childChildren.contains { $0.id == grandchild.id })
    }
    
    @Test("Get task in session")
    func testGetTaskInSession() async throws {
        let session = try await TestHelpers.createSampleSession(title: "Test Session")
        let task = try await TestHelpers.createSampleTask(in: session)
        
        // Verify task is in session's task list
        let tasksInSession = try await TaskManager.shared.list(sessionID: session.id)
        #expect(tasksInSession.contains { $0.id == task.id })
    }
    
    @Test("Get non-existent task throws error")
    func testGetNonExistentTask() async throws {
        let fakeID = UUID()
        
        await TestHelpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await TaskManager.shared.get(id: fakeID)
        }
    }
    
    // MARK: - List Tests
    
    @Test("List all tasks in session")
    func testListTasksInSession() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        let task1 = try await TestHelpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await TestHelpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await TestHelpers.createSampleTask(in: session, title: "Task 3")
        
        let tasks = try await TaskManager.shared.list(sessionID: session.id)
        
        #expect(tasks.count >= 3)
        TestHelpers.assertContainsTask(tasks, withID: task1.id)
        TestHelpers.assertContainsTask(tasks, withID: task2.id)
        TestHelpers.assertContainsTask(tasks, withID: task3.id)
    }
    
    @Test("List tasks by status")
    func testListTasksByStatus() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (pending, inProgress, done, cancelled) = try await TestHelpers.createTasksWithStatuses(in: session)
        
        // List pending tasks
        let pendingTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            status: .pending
        )
        TestHelpers.assertContainsTask(pendingTasks, withID: pending.id)
        TestHelpers.assertDoesNotContainTask(pendingTasks, withID: done.id)
        
        // List in progress tasks
        let inProgressTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            status: .inProgress
        )
        TestHelpers.assertContainsTask(inProgressTasks, withID: inProgress.id)
        TestHelpers.assertDoesNotContainTask(inProgressTasks, withID: pending.id)
        
        // List done tasks
        let doneTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            status: .done
        )
        TestHelpers.assertContainsTask(doneTasks, withID: done.id)
        TestHelpers.assertDoesNotContainTask(doneTasks, withID: pending.id)
        
        // List cancelled tasks
        let cancelledTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            status: .cancelled
        )
        TestHelpers.assertContainsTask(cancelledTasks, withID: cancelled.id)
        TestHelpers.assertDoesNotContainTask(cancelledTasks, withID: done.id)
    }
    
    @Test("List tasks by assignee")
    func testListTasksByAssignee() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        let aliceTask = try await TestHelpers.createSampleTask(
            in: session,
            title: "Alice's Task",
            assignee: "Alice"
        )
        
        let bobTask = try await TestHelpers.createSampleTask(
            in: session,
            title: "Bob's Task",
            assignee: "Bob"
        )
        
        let unassigned = try await TestHelpers.createSampleTask(
            in: session,
            title: "Unassigned Task"
        )
        
        // List Alice's tasks
        let aliceTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            assignee: "Alice"
        )
        TestHelpers.assertContainsTask(aliceTasks, withID: aliceTask.id)
        TestHelpers.assertDoesNotContainTask(aliceTasks, withID: bobTask.id)
        TestHelpers.assertDoesNotContainTask(aliceTasks, withID: unassigned.id)
    }
    
    @Test("List tasks by difficulty range")
    func testListTasksByDifficulty() async throws {
        let session = try await TestHelpers.createSampleSession()
        let tasks = try await TestHelpers.createTasksWithDifficulties(in: session)
        
        // List easy tasks (max difficulty 2)
        let easyTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            difficultyMax: 2
        )
        #expect(easyTasks.allSatisfy { $0.difficulty <= 2 })
        
        // List medium or easy tasks (max difficulty 3)
        let mediumTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            difficultyMax: 3
        )
        #expect(mediumTasks.allSatisfy { $0.difficulty <= 3 })
        
        // List all tasks - no difficulty filter
        let allTasks = try await TaskManager.shared.list(
            sessionID: session.id
        )
        #expect(allTasks.count >= tasks.count)
    }
    
    @Test("List ready tasks")
    func testListReadyTasks() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        // Create dependency chain
        let blocker = try await TestHelpers.createSampleTask(in: session, title: "Blocker")
        let blocked = try await TestHelpers.createSampleTask(in: session, title: "Blocked")
        let independent = try await TestHelpers.createSampleTask(in: session, title: "Independent")
        
        try await DependencyManager.shared.add(
            blockerID: blocker.id,
            blockedID: blocked.id
        )
        
        // List ready tasks - should not include blocked
        let readyTasks = try await TaskManager.shared.list(
            sessionID: session.id,
            readyOnly: true
        )
        
        TestHelpers.assertContainsTask(readyTasks, withID: blocker.id)
        TestHelpers.assertContainsTask(readyTasks, withID: independent.id)
        TestHelpers.assertDoesNotContainTask(readyTasks, withID: blocked.id)
        
        // Mark blocker as done
        _ = try await TaskManager.shared.update(
            id: blocker.id,
            status: .done
        )
        
        // Now blocked should be ready
        let readyAfterCompletion = try await TaskManager.shared.list(
            sessionID: session.id,
            readyOnly: true
        )
        
        TestHelpers.assertContainsTask(readyAfterCompletion, withID: blocked.id)
        TestHelpers.assertContainsTask(readyAfterCompletion, withID: independent.id)
        TestHelpers.assertDoesNotContainTask(readyAfterCompletion, withID: blocker.id) // Done tasks not included
    }
    
    @Test("List tasks with subtasks")
    func testListTasksWithSubtasks() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (parent, child, _) = try await TestHelpers.createTaskHierarchy(in: session)
        
        // List parent's subtasks
        let parentSubtasks = try await TaskManager.shared.list(parentTaskID: parent.id)
        #expect(parentSubtasks.count == 1)
        #expect(parentSubtasks.first?.id == child.id)
    }
    
    // MARK: - Update Tests
    
    @Test("Update task properties")
    func testUpdateTask() async throws {
        let session = try await TestHelpers.createSampleSession()
        let task = try await TestHelpers.createSampleTask(in: session)
        
        let updated = try await TaskManager.shared.update(
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
        let fetched = try await TaskManager.shared.get(id: task.id)
        #expect(fetched.title == "Updated Title")
    }
    
    @Test("Update task to cancelled with reason")
    func testCancelTask() async throws {
        let session = try await TestHelpers.createSampleSession()
        let task = try await TestHelpers.createSampleTask(in: session)
        
        let cancelled = try await TaskManager.shared.update(
            id: task.id,
            status: .cancelled,
            cancelReason: "No longer needed"
        )
        
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.cancelReason == "No longer needed")
    }
    
    @Test("Batch update tasks")
    func testBatchUpdate() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        let task1 = try await TestHelpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await TestHelpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await TestHelpers.createSampleTask(in: session, title: "Task 3")
        
        let updated = try await TaskManager.shared.updateBatch(
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
        let fakeID = UUID()
        
        await TestHelpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await TaskManager.shared.update(
                id: fakeID,
                title: "New Title"
            )
        }
    }
    
    // MARK: - Reorder Tests
    
    @Test("Reorder tasks in session")
    func testReorderTasks() async throws {
        let session = try await TestHelpers.createSampleSession()
        
        let task1 = try await TestHelpers.createSampleTask(in: session, title: "Task 1")
        let task2 = try await TestHelpers.createSampleTask(in: session, title: "Task 2")
        let task3 = try await TestHelpers.createSampleTask(in: session, title: "Task 3")
        
        // Reorder: 3, 1, 2
        try await TaskManager.shared.reorder(
            sessionID: session.id,
            orderedIds: [task3.id, task1.id, task2.id]
        )
        
        // Verify order
        let ordered = try await TaskManager.shared.list(sessionID: session.id)
        
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
        let session = try await TestHelpers.createSampleSession()
        let task = try await TestHelpers.createSampleTask(in: session)
        let fakeID = UUID()
        
        do {
            try await TaskManager.shared.reorder(
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
        let session = try await TestHelpers.createSampleSession()
        let task = try await TestHelpers.createSampleTask(in: session)
        
        try await TaskManager.shared.delete(id: task.id, cascade: false)
        
        await TestHelpers.expectMemoryError(.taskNotFound(task.id)) {
            try await TaskManager.shared.get(id: task.id)
        }
    }
    
    @Test("Delete task with cascade removes subtasks")
    func testDeleteTaskWithCascade() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (parent, child, grandchild) = try await TestHelpers.createTaskHierarchy(in: session)
        
        // Delete parent with cascade
        try await TaskManager.shared.delete(id: parent.id, cascade: true)
        
        // Verify all are deleted
        await TestHelpers.expectMemoryError(.taskNotFound(parent.id)) {
            try await TaskManager.shared.get(id: parent.id)
        }
        
        await TestHelpers.expectMemoryError(.taskNotFound(child.id)) {
            try await TaskManager.shared.get(id: child.id)
        }
        
        await TestHelpers.expectMemoryError(.taskNotFound(grandchild.id)) {
            try await TaskManager.shared.get(id: grandchild.id)
        }
    }
    
    @Test("Delete task removes dependencies")
    func testDeleteTaskRemovesDependencies() async throws {
        let session = try await TestHelpers.createSampleSession()
        let (first, second, third) = try await TestHelpers.createDependencyChain(in: session)
        
        // Delete middle task
        try await TaskManager.shared.delete(id: second.id, cascade: false)
        
        // First should have no tasks it's blocking
        let firstBlocking = try await DependencyManager.shared.getBlocking(taskID: first.id)
        #expect(firstBlocking.isEmpty == true)
        
        // Third should have no blockers
        let thirdBlockers = try await DependencyManager.shared.getBlockers(taskID: third.id)
        #expect(thirdBlockers.isEmpty == true)
    }
    
    @Test("Delete non-existent task throws error")
    func testDeleteNonExistentTask() async throws {
        let fakeID = UUID()
        
        await TestHelpers.expectMemoryError(.taskNotFound(fakeID)) {
            try await TaskManager.shared.delete(id: fakeID, cascade: false)
        }
    }
}