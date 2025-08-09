// The Swift Programming Language
// https://docs.swift.org/swift-book

import OpenFoundationModels

// MARK: - Tool Collection
public let memoryTools: [any Tool] = [
    // Session Tools
    SessionCreateTool(),
    SessionGetTool(),
    SessionListTool(),
    SessionUpdateTool(),
    SessionDeleteTool(),
    // Task Tools
    TaskCreateTool(),
    TaskGetTool(),
    TaskListTool(),
    TaskUpdateTool(),
    TaskReorderTool(),
    TaskDeleteTool(),
    // Dependency Tools
    DependencyAddTool(),
    DependencyRemoveTool(),
    DependencyChainTool(),
    TaskIsBlockedTool()
]