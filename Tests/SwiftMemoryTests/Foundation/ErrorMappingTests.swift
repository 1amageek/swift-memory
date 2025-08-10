import Foundation
import Testing
@testable import SwiftMemory

@Suite("Error Mapping Tests")
struct ErrorMappingTests {
    
    @Test("MemoryError should provide error codes")
    func testErrorCodes() {
        let errors: [(MemoryError, MemoryErrorCode)] = [
            (.sessionNotFound(UUID()), .sessionNotFound),
            (.taskNotFound(UUID()), .taskNotFound),
            (.invalidOrder, .invalidOrder),
            (.circularDependency(blocker: UUID(), blocked: UUID()), .circularDependency),
            (.duplicateParent(taskID: UUID()), .duplicateParent),
            (.invalidDifficulty(10), .invalidDifficulty),
            (.invalidInput(field: "test", reason: "invalid"), .invalidInput),
            (.databaseError("test error"), .databaseError)
        ]
        
        for (error, expectedCode) in errors {
            #expect(error.code == expectedCode)
        }
    }
    
    @Test("MemoryError should provide recovery suggestions")
    func testRecoverySuggestions() {
        let sessionError = MemoryError.sessionNotFound(UUID())
        #expect(sessionError.recoverySuggestion != nil)
        #expect(sessionError.recoverySuggestion?.contains("memory.session.create") == true)
        
        let taskError = MemoryError.taskNotFound(UUID())
        #expect(taskError.recoverySuggestion != nil)
        #expect(taskError.recoverySuggestion?.contains("memory.task.list") == true)
        
        let difficultyError = MemoryError.invalidDifficulty(10)
        #expect(difficultyError.recoverySuggestion != nil)
        #expect(difficultyError.recoverySuggestion?.contains("1-5") == true)
        
        let circularError = MemoryError.circularDependency(blocker: UUID(), blocked: UUID())
        #expect(circularError.recoverySuggestion != nil)
        #expect(circularError.recoverySuggestion?.contains("Remove intermediate dependencies") == true)
    }
    
    @Test("MemoryError should provide context information")
    func testContextInfo() {
        let sessionID = UUID()
        let sessionError = MemoryError.sessionNotFound(sessionID)
        #expect(sessionError.contextInfo["sessionID"] == sessionID.uuidString)
        
        let taskID = UUID()
        let taskError = MemoryError.taskNotFound(taskID)
        #expect(taskError.contextInfo["taskID"] == taskID.uuidString)
        
        let blockerID = UUID()
        let blockedID = UUID()
        let circularError = MemoryError.circularDependency(blocker: blockerID, blocked: blockedID)
        #expect(circularError.contextInfo["blockerID"] == blockerID.uuidString)
        #expect(circularError.contextInfo["blockedID"] == blockedID.uuidString)
        
        let difficultyError = MemoryError.invalidDifficulty(10)
        #expect(difficultyError.contextInfo["providedValue"] == "10")
        #expect(difficultyError.contextInfo["validRange"] == "1-5")
    }
    
    @Test("ErrorMapping should format errors with suggestions")
    func testErrorMappingWithSuggestions() {
        let sessionError = MemoryError.sessionNotFound(UUID())
        let mapped = ErrorMapping.map(sessionError)
        
        #expect(mapped.contains("Session not found"))
        #expect(mapped.contains("Verify the session ID"))
        
        let taskError = MemoryError.taskNotFound(UUID())
        let mappedTask = ErrorMapping.map(taskError)
        
        #expect(mappedTask.contains("Task not found"))
        #expect(mappedTask.contains("memory.task.list"))
    }
    
    @Test("ErrorMapping should handle non-MemoryError")
    func testErrorMappingWithOtherErrors() {
        struct CustomError: Error {
            let message: String
        }
        
        let customError = CustomError(message: "Custom error")
        let mapped = ErrorMapping.map(customError)
        
        #expect(mapped == "Unexpected error occurred")
    }
    
    @Test("StructuredMemoryError should contain all fields")
    func testStructuredError() {
        let taskID = UUID()
        let error = MemoryError.taskNotFound(taskID)
        let structured = error.structuredError
        
        #expect(structured.code == "TASK_NOT_FOUND")
        #expect(structured.message.contains("Task not found"))
        #expect(structured.suggestion != nil)
        #expect(structured.context["taskID"] == taskID.uuidString)
    }
    
    @Test("Error descriptions should be informative")
    func testErrorDescriptions() {
        let errors: [MemoryError] = [
            .sessionNotFound(UUID()),
            .taskNotFound(UUID()),
            .invalidOrder,
            .circularDependency(blocker: UUID(), blocked: UUID()),
            .duplicateParent(taskID: UUID()),
            .invalidDifficulty(10),
            .invalidInput(field: "title", reason: "empty"),
            .databaseError("connection failed")
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(description.count > 10) // Should be meaningful
        }
    }
}