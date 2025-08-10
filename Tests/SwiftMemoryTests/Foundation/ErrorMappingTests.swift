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
        // Check that recovery suggestions exist, but don't depend on exact text
        let sessionError = MemoryError.sessionNotFound(UUID())
        #expect(sessionError.recoverySuggestion != nil)
        #expect(!sessionError.recoverySuggestion!.isEmpty)
        
        let taskError = MemoryError.taskNotFound(UUID())
        #expect(taskError.recoverySuggestion != nil)
        #expect(!taskError.recoverySuggestion!.isEmpty)
        
        let difficultyError = MemoryError.invalidDifficulty(10)
        #expect(difficultyError.recoverySuggestion != nil)
        #expect(!difficultyError.recoverySuggestion!.isEmpty)
        
        let circularError = MemoryError.circularDependency(blocker: UUID(), blocked: UUID())
        #expect(circularError.recoverySuggestion != nil)
        #expect(!circularError.recoverySuggestion!.isEmpty)
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
        
        // Check that error message exists without depending on exact text
        #expect(!mapped.isEmpty)
        #expect(mapped.count > 10) // Has meaningful content
        
        let taskError = MemoryError.taskNotFound(UUID())
        let mappedTask = ErrorMapping.map(taskError)
        
        // Check that error message exists without depending on exact text
        #expect(!mappedTask.isEmpty)
        #expect(mappedTask.count > 10) // Has meaningful content
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
        #expect(!structured.message.isEmpty) // Message exists but don't depend on exact text
        #expect(structured.suggestion != nil)
        #expect(!structured.suggestion!.isEmpty) // Suggestion exists
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