#!/usr/bin/env python3
"""
Script to migrate DependencyManagerTests to isolated architecture
"""
import re

def migrate_dependency_tests(content):
    """Migrate DependencyManagerTests to use TestContext"""
    
    # Pattern for test methods
    test_pattern = r'(@Test\([^)]+\)\s+func\s+\w+\(\)\s+async\s+throws\s+\{)'
    
    def replace_test_start(match):
        return f"""{match.group(1)}
        let context = try await TestContext.create(testName: #function)
        defer {{ Task {{ await context.cleanup() }} }}
        """
    
    # Replace test method starts
    content = re.sub(test_pattern, replace_test_start, content)
    
    # Replace TestHelpers calls
    content = re.sub(r'TestHelpers\.createSampleSession\(\)', 'context.helpers.createSampleSession()', content)
    content = re.sub(r'TestHelpers\.createSampleTask\(', 'context.helpers.createSampleTask(', content)
    content = re.sub(r'TestHelpers\.createTaskHierarchy\(', 'context.helpers.createTaskHierarchy(', content)
    content = re.sub(r'TestHelpers\.createDependencyChain\(', 'context.helpers.createDependencyChain(', content)
    content = re.sub(r'TestHelpers\.expectMemoryError\(', 'context.helpers.expectMemoryError(', content)
    
    # Replace shared managers
    content = re.sub(r'DependencyManager\.shared', 'context.dependencyManager', content)
    content = re.sub(r'TaskManager\.shared', 'context.taskManager', content)
    content = re.sub(r'SessionManager\.shared', 'context.sessionManager', content)
    
    return content

def main():
    # Read the current file
    with open('/Users/1amageek/Desktop/swift-memory/Tests/SwiftMemoryTests/Managers/DependencyManagerTests.swift', 'r') as f:
        content = f.read()
    
    # Migrate the content
    migrated_content = migrate_dependency_tests(content)
    
    # Write the migrated content
    with open('/Users/1amageek/Desktop/swift-memory/Tests/SwiftMemoryTests/Managers/DependencyManagerTests.swift', 'w') as f:
        f.write(migrated_content)
    
    print("DependencyManagerTests migration completed!")

if __name__ == '__main__':
    main()