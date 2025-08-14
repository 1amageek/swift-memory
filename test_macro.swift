import OpenFoundationModels
import OpenFoundationModelsMacros

@Generable
struct TestStruct {
    @Guide(description: "Test field")
    var field1: Bool?
    
    @Guide(description: "Another field")
    var field2: String?
}

// Test the generated initializer
let test1 = TestStruct(GeneratedContent(content: ["field1": true, "field2": "test"]))
print("Created test struct")