// The Swift Programming Language
// https://docs.swift.org/swift-book

import OpenFoundationModels

// MARK: - Tool Collection
public let memoryTools: [any Tool] = [
    // Session Tools (5)
    SessionCreateTool(),
    SessionGetTool(),
    SessionListTool(),
    SessionUpdateTool(),
    SessionDeleteTool(),
    
    // Task Tools (6)
    TaskCreateTool(),
    TaskGetTool(),      // Enhanced with include options
    TaskListTool(),     
    TaskUpdateTool(),   // Enhanced with batch support
    TaskReorderTool(),
    TaskDeleteTool(),
    
    // Dependency Tools (2)
    DependencySetTool(),  // Handles both add and remove
    DependencyGetTool()   // Handles chain, blockers, blocking, and isBlocked queries
]