import Foundation
import KuzuSwiftExtension

/// Configuration for SwiftMemory database
public struct SwiftMemoryConfiguration: Sendable {
    /// Path to the database file
    public let databasePath: String?
    
    /// Migration policy for schema changes
    public let migrationPolicy: MigrationPolicy
    
    /// Enable logging for debugging
    public let enableLogging: Bool
    
    /// Maximum number of connections in the pool
    public let maxConnections: Int
    
    /// Connection timeout in seconds
    public let connectionTimeout: TimeInterval
    
    public init(
        databasePath: String? = nil,
        migrationPolicy: MigrationPolicy = .safe,
        enableLogging: Bool = false,
        maxConnections: Int = 5,
        connectionTimeout: TimeInterval = 30.0
    ) {
        self.databasePath = databasePath
        self.migrationPolicy = migrationPolicy
        self.enableLogging = enableLogging
        self.maxConnections = maxConnections
        self.connectionTimeout = connectionTimeout
    }
    
    /// Default configuration for production use
    public static let `default` = SwiftMemoryConfiguration(
        databasePath: nil,  // Uses default GraphDatabase path
        migrationPolicy: .safe,
        enableLogging: false
    )
    
    /// Configuration for testing with in-memory database
    public static func test(name: String) -> SwiftMemoryConfiguration {
        let testPath = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("swift-memory-test-\(name)-\(UUID())")
            .path
        
        return SwiftMemoryConfiguration(
            databasePath: testPath,
            migrationPolicy: .automatic,
            enableLogging: true,
            maxConnections: 1,  // Single connection for tests
            connectionTimeout: 10.0
        )
    }
    
    /// Configuration for development with verbose logging
    public static let development = SwiftMemoryConfiguration(
        databasePath: nil,
        migrationPolicy: .automatic,
        enableLogging: true
    )
    
    /// Convert to GraphConfiguration for KuzuSwiftExtension
    internal func toGraphConfiguration() -> GraphConfiguration {
        if let path = databasePath {
            return GraphConfiguration(
                databasePath: path,
                options: GraphConfiguration.Options(
                    maxConnections: maxConnections,
                    connectionTimeout: connectionTimeout,
                    enableLogging: enableLogging
                )
            )
        } else {
            // Use default GraphDatabase path
            return GraphConfiguration(
                options: GraphConfiguration.Options(
                    maxConnections: maxConnections,
                    connectionTimeout: connectionTimeout,
                    enableLogging: enableLogging
                )
            )
        }
    }
}