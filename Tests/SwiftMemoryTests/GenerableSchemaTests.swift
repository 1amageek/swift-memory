import Foundation
import Testing
@testable import SwiftMemory
import OpenFoundationModels
import OpenFoundationModelsCore

@Suite("Generable Schema Tests")
struct GenerableSchemaTests {
    
    @Test("CreateTaskArguments conforms to Generable")
    func createTaskArgumentsGenerable() {
        // Check if CreateTaskArguments conforms to Generable
        let isGenerable = CreateTaskArguments.self is any Generable.Type
        #expect(isGenerable, "CreateTaskArguments should conform to Generable")
        
        if let generableType = CreateTaskArguments.self as? any Generable.Type {
            let schema = generableType.generationSchema
            #expect(schema.debugDescription.contains("GenerationSchema"))
            print("CreateTaskArguments schema: \(schema.debugDescription)")
        }
    }
    
    @Test("All argument types conform to Generable")
    func allArgumentTypesGenerable() {
        // Session arguments
        #expect(CreateSessionArguments.self is any Generable.Type)
        #expect(UpdateSessionArguments.self is any Generable.Type)
        #expect(GetSessionArguments.self is any Generable.Type)
        #expect(DeleteSessionArguments.self is any Generable.Type)
        #expect(ListSessionsArguments.self is any Generable.Type)
        
        // Task arguments
        #expect(CreateTaskArguments.self is any Generable.Type)
        #expect(UpdateTaskArguments.self is any Generable.Type)
        #expect(GetTaskArguments.self is any Generable.Type)
        #expect(DeleteTaskArguments.self is any Generable.Type)
        #expect(ListTasksArguments.self is any Generable.Type)
        #expect(ReorderTasksArguments.self is any Generable.Type)
        
        // Dependency arguments
        #expect(SetDependencyArguments.self is any Generable.Type)
        #expect(GetDependencyArguments.self is any Generable.Type)
        
        // Nested types
        #expect(TaskUpdate.self is any Generable.Type)
        #expect(TaskIncludeOptions.self is any Generable.Type)
    }
    
    @Test("Tool parameters use Generable schema")
    func toolParametersUseGenerableSchema() {
        // Test a sample tool
        let tool = TaskCreateTool()
        
        // Tool should have parameters
        let parameters = tool.parameters
        #expect(parameters.debugDescription.contains("GenerationSchema"))
        
        // The parameters should be derived from Arguments.generationSchema
        if let generableType = CreateTaskArguments.self as? any Generable.Type {
            let argumentSchema = generableType.generationSchema
            // Both should be GenerationSchema instances
            #expect(type(of: parameters) == type(of: argumentSchema))
        }
    }
    
    @Test("Tool protocol conformance")
    func toolProtocolConformance() {
        let tool = SessionCreateTool()
        
        // Check required properties exist
        #expect(!tool.name.isEmpty)
        #expect(!tool.description.isEmpty)
        
        // Check that the tool has proper types
        #expect(tool is any Tool)
        
        // Verify Arguments and Output types
        typealias Args = SessionCreateTool.Arguments
        typealias Out = SessionCreateTool.Output
        
        #expect(Args.self == CreateSessionArguments.self)
        #expect(Out.self == MemoryToolResult.self)
    }
    
    @Test("MemoryToolResult conforms to PromptRepresentable")
    func memoryToolResultPromptRepresentable() {
        #expect(MemoryToolResult.self is any PromptRepresentable.Type)
        
        // Test a specific case
        let result = MemoryToolResult.sessionCreated(
            Session(title: "Test Session")
        )
        
        let prompt = result.promptRepresentation
        // Prompt doesn't have a direct text property, but we can verify it exists
        #expect(prompt.description.contains("Created session"))
    }
}