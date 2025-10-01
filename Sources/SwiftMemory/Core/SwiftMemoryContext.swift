import Foundation
import KuzuSwiftExtension

/// SwiftMemory's context manager for database operations
public actor SwiftMemoryContext {
    /// GraphContainer and GraphContext are thread-safe, so we can safely access them
    /// from nonisolated contexts. The lazy initialization pattern ensures they're
    /// only created once.
    private nonisolated(unsafe) var graphContainer: GraphContainer?
    private nonisolated(unsafe) var graphContext: GraphContext?

    /// Shared instance with default configuration
    public static let shared = SwiftMemoryContext()

    /// Initialize with default configuration
    private init() {}

    /// Get or create the graph context
    ///
    /// GraphContext is thread-safe, so this method can be called from any context.
    public nonisolated func context() throws -> GraphContext {
        // Check if already initialized
        if let existing = self.graphContext {
            return existing
        }

        // Create GraphContainer with all models
        let container = try GraphContainer(
            for: Session.self,
                SwiftMemory.Task.self,
                HasTask.self,
                SubTaskOf.self,
                Blocks.self
        )

        let context = GraphContext(container)

        // Store for future use
        self.graphContainer = container
        self.graphContext = context

        return context
    }
}
