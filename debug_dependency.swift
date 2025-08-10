import Foundation
import Testing
import KuzuSwiftExtension
@testable import SwiftMemory

@main
struct DebugDependency {
    static func main() async {
        do {
            print("🔍 Creating test context...")
            let context = try await TestContext.create(testName: "debug_dependency")
            defer { _Concurrency.Task { await context.cleanup() } }
            
            print("✅ TestContext created successfully")
            
            // Create session and tasks
            print("📝 Creating session...")
            let session = try await context.sessionManager.create(title: "Debug Session")
            print("✅ Session created: \(session.id)")
            
            print("📝 Creating tasks...")
            let blocker = try await context.taskManager.create(
                sessionID: session.id,
                title: "Blocker Task"
            )
            print("✅ Blocker task created: \(blocker.id)")
            
            let blocked = try await context.taskManager.create(
                sessionID: session.id,
                title: "Blocked Task"
            )
            print("✅ Blocked task created: \(blocked.id)")
            
            // Add dependency
            print("🔗 Adding dependency...")
            try await context.dependencyManager.add(
                blockerID: blocker.id,
                blockedID: blocked.id
            )
            print("✅ Dependency added")
            
            // Query to check if dependency exists
            print("🔍 Checking dependency with raw query...")
            let checkResult = try await context.graphContext.raw(
                """
                MATCH (blocker:Task {id: $blockerID})-[r:Blocks]->(blocked:Task {id: $blockedID})
                RETURN blocker, r, blocked
                """,
                bindings: ["blockerID": blocker.id, "blockedID": blocked.id]
            )
            
            if checkResult.hasNext() {
                print("✅ Dependency found in database!")
                if let tuple = try checkResult.getNext(),
                   let dict = try? tuple.getAsDictionary() {
                    print("   Result keys: \(dict.keys)")
                }
            } else {
                print("❌ Dependency NOT found in database!")
            }
            
            // Get blockers
            print("🔍 Getting blockers for blocked task...")
            let blockers = try await context.dependencyManager.getBlockers(taskID: blocked.id)
            print("   Blockers count: \(blockers.count)")
            if blockers.isEmpty {
                print("❌ No blockers found!")
                
                // Debug query
                print("🔍 Running debug query...")
                let debugResult = try await context.graphContext.raw(
                    """
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    RETURN blocker.id, blocker.title
                    """,
                    bindings: ["taskID": blocked.id]
                )
                
                print("   Has results: \(debugResult.hasNext())")
                while debugResult.hasNext() {
                    if let tuple = try debugResult.getNext(),
                       let dict = try? tuple.getAsDictionary() {
                        print("   Debug result: \(dict)")
                    }
                }
            } else {
                print("✅ Found \(blockers.count) blocker(s)")
                for blocker in blockers {
                    print("   - \(blocker.title) (\(blocker.id))")
                }
            }
            
            print("✅ Debug completed")
        } catch {
            print("❌ Error: \(error)")
            if let memoryError = error as? MemoryError {
                print("   Memory error: \(memoryError)")
            }
        }
    }
}