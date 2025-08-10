import Foundation
import Testing
@testable import SwiftMemory

@Suite("Enums Tests")
struct EnumsTests {
    
    // MARK: - TaskDifficulty Tests
    
    @Test("TaskDifficulty should have correct int values")
    func testTaskDifficultyIntValues() {
        #expect(TaskDifficulty.trivial.intValue == 1)
        #expect(TaskDifficulty.easy.intValue == 2)
        #expect(TaskDifficulty.medium.intValue == 3)
        #expect(TaskDifficulty.hard.intValue == 4)
        #expect(TaskDifficulty.expert.intValue == 5)
    }
    
    @Test("TaskDifficulty should convert from int values")
    func testTaskDifficultyFromInt() {
        #expect(TaskDifficulty(intValue: 1) == .trivial)
        #expect(TaskDifficulty(intValue: 2) == .easy)
        #expect(TaskDifficulty(intValue: 3) == .medium)
        #expect(TaskDifficulty(intValue: 4) == .hard)
        #expect(TaskDifficulty(intValue: 5) == .expert)
        
        // Invalid values
        #expect(TaskDifficulty(intValue: 0) == nil)
        #expect(TaskDifficulty(intValue: 6) == nil)
        #expect(TaskDifficulty(intValue: -1) == nil)
    }
    
    @Test("TaskDifficulty should have display names")
    func testTaskDifficultyDisplayNames() {
        #expect(TaskDifficulty.trivial.displayName == "Trivial")
        #expect(TaskDifficulty.easy.displayName == "Easy")
        #expect(TaskDifficulty.medium.displayName == "Medium")
        #expect(TaskDifficulty.hard.displayName == "Hard")
        #expect(TaskDifficulty.expert.displayName == "Expert")
    }
    
    @Test("TaskDifficulty should have descriptions")
    func testTaskDifficultyDescriptions() {
        #expect(TaskDifficulty.trivial.description == "Trivial (1/5)")
        #expect(TaskDifficulty.easy.description == "Easy (2/5)")
        #expect(TaskDifficulty.medium.description == "Medium (3/5)")
        #expect(TaskDifficulty.hard.description == "Hard (4/5)")
        #expect(TaskDifficulty.expert.description == "Expert (5/5)")
    }
    
    @Test("TaskDifficulty should be codable")
    func testTaskDifficultyCodable() throws {
        let difficulties = TaskDifficulty.allCases
        
        for difficulty in difficulties {
            let encoder = JSONEncoder()
            let data = try encoder.encode(difficulty)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(TaskDifficulty.self, from: data)
            
            #expect(decoded == difficulty)
        }
    }
    
    // MARK: - TaskStatus Tests
    
    @Test("TaskStatus should have correct raw values")
    func testTaskStatusRawValues() {
        #expect(TaskStatus.pending.rawValue == "pending")
        #expect(TaskStatus.inProgress.rawValue == "inProgress")
        #expect(TaskStatus.done.rawValue == "done")
        #expect(TaskStatus.cancelled.rawValue == "cancelled")
    }
    
    @Test("TaskStatus isActive property")
    func testTaskStatusIsActive() {
        #expect(TaskStatus.pending.isActive == true)
        #expect(TaskStatus.inProgress.isActive == true)
        #expect(TaskStatus.done.isActive == false)
        #expect(TaskStatus.cancelled.isActive == false)
    }
    
    @Test("TaskStatus isCompleted property")
    func testTaskStatusIsCompleted() {
        #expect(TaskStatus.pending.isCompleted == false)
        #expect(TaskStatus.inProgress.isCompleted == false)
        #expect(TaskStatus.done.isCompleted == true)
        #expect(TaskStatus.cancelled.isCompleted == true)
    }
    
    @Test("TaskStatus should have display names")
    func testTaskStatusDisplayNames() {
        #expect(TaskStatus.pending.displayName == "Pending")
        #expect(TaskStatus.inProgress.displayName == "In Progress")
        #expect(TaskStatus.done.displayName == "Done")
        #expect(TaskStatus.cancelled.displayName == "Cancelled")
    }
    
    // MARK: - DependencyAction Tests
    
    @Test("DependencyAction should have correct raw values")
    func testDependencyActionRawValues() {
        #expect(DependencyAction.add.rawValue == "add")
        #expect(DependencyAction.remove.rawValue == "remove")
    }
    
    // MARK: - DependencyQueryType Tests
    
    @Test("DependencyQueryType should have correct raw values")
    func testDependencyQueryTypeRawValues() {
        #expect(DependencyQueryType.chain.rawValue == "chain")
        #expect(DependencyQueryType.blockers.rawValue == "blockers")
        #expect(DependencyQueryType.blocking.rawValue == "blocking")
        #expect(DependencyQueryType.isBlocked.rawValue == "isBlocked")
    }
    
    // MARK: - TaskIncludeOptions Tests
    
    @Test("TaskIncludeOptions should detect enabled options")
    func testTaskIncludeOptionsHasAnyEnabled() {
        let empty = TaskIncludeOptions()
        #expect(empty.hasAnyEnabled == false)
        
        let withParent = TaskIncludeOptions(parent: true)
        #expect(withParent.hasAnyEnabled == true)
        
        let withChildren = TaskIncludeOptions(children: true)
        #expect(withChildren.hasAnyEnabled == true)
        
        let withMultiple = TaskIncludeOptions(
            parent: true,
            children: true,
            dependencies: true
        )
        #expect(withMultiple.hasAnyEnabled == true)
        
        let allFalse = TaskIncludeOptions(
            parent: false,
            children: false,
            dependencies: false,
            fullChain: false,
            session: false
        )
        #expect(allFalse.hasAnyEnabled == false)
    }
    
    @Test("TaskIncludeOptions should be codable")
    func testTaskIncludeOptionsCodable() throws {
        let options = TaskIncludeOptions(
            parent: true,
            children: false,
            dependencies: true,
            fullChain: nil,
            session: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(options)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TaskIncludeOptions.self, from: data)
        
        #expect(decoded.parent == true)
        #expect(decoded.children == false)
        #expect(decoded.dependencies == true)
        #expect(decoded.fullChain == nil)
        #expect(decoded.session == true)
    }
    
    // MARK: - TaskBatchUpdate Tests
    
    @Test("TaskBatchUpdate should be codable")
    func testTaskBatchUpdateCodable() throws {
        let update = TaskBatchUpdate(
            title: "Updated Title",
            description: "Updated Description",
            status: .done,
            difficulty: .hard,
            assignee: "Bob",
            cancelReason: nil
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(update)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TaskBatchUpdate.self, from: data)
        
        #expect(decoded.title == "Updated Title")
        #expect(decoded.description == "Updated Description")
        #expect(decoded.status == .done)
        #expect(decoded.difficulty == .hard)
        #expect(decoded.assignee == "Bob")
        #expect(decoded.cancelReason == nil)
    }
}