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
    
    // Dependency Tools - New Unified (2)
    DependencySetTool(),  // Replaces add/remove
    DependencyGetTool(),  // Replaces chain/isBlocked
    
    // Deprecated - kept for backward compatibility
    // Uncomment if you need backward compatibility:
    // DependencyAddTool(),      // Use DependencySetTool instead
    // DependencyRemoveTool(),   // Use DependencySetTool instead
    // DependencyChainTool(),    // Use DependencyGetTool instead
    // TaskIsBlockedTool()       // Use DependencyGetTool instead
]