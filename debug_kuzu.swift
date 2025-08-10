import Foundation
import Testing
import KuzuSwiftExtension
@testable import SwiftMemory

@main
struct DebugKuzu {
    static func main() async {
        do {
            print("Creating test context...")
            let context = try await TestContext.create(testName: "debug_test")
            print("✅ TestContext created successfully")
            
            print("Creating session...")
            let session = try await context.createSession(title: "Debug Session")
            print("✅ Session created: \(session.id)")
            
            await context.cleanup()
            print("✅ Cleanup completed")
        } catch {
            print("❌ Error: \(error)")
            if let memoryError = error as? MemoryError {
                print("   Memory error: \(memoryError)")
            }
        }
    }
}