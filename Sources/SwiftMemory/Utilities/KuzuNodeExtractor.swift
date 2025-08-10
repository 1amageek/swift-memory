import Foundation

/// Helper to extract properties from KuzuNode objects returned by queries
public enum KuzuNodeExtractor {
    
    /// Extract properties dictionary from a KuzuNode that may be wrapped in Optional
    /// - Parameter node: The node object (may be Optional(KuzuNode) or KuzuNode)
    /// - Returns: The properties dictionary if found, nil otherwise
    public static func extractProperties(from node: Any) -> [String: Any?]? {
        // First unwrap the Optional if needed
        let actualNode: Any
        let mirror = Mirror(reflecting: node)
        if mirror.displayStyle == .optional {
            if let (_, wrapped) = mirror.children.first {
                actualNode = wrapped
            } else {
                return nil // nil optional
            }
        } else {
            actualNode = node
        }
        
        // Now extract properties from the actual KuzuNode
        let nodeMirror = Mirror(reflecting: actualNode)
        for child in nodeMirror.children {
            if child.label == "properties",
               let properties = child.value as? [String: Any?] {
                return properties
            }
        }
        
        return nil
    }
    
    /// Check if the node might be a KuzuNode (rather than a direct dictionary)
    /// - Parameter node: The node to check
    /// - Returns: true if it appears to be a KuzuNode, false if it's a dictionary
    public static func isKuzuNode(_ node: Any) -> Bool {
        // If it's already a dictionary, it's not a KuzuNode
        if node is [String: Any?] {
            return false
        }
        
        // Check if it has a properties field (characteristic of KuzuNode)
        let mirror = Mirror(reflecting: node)
        
        // Handle Optional wrapping
        let actualMirror: Mirror
        if mirror.displayStyle == .optional {
            if let (_, wrapped) = mirror.children.first {
                actualMirror = Mirror(reflecting: wrapped)
            } else {
                return false
            }
        } else {
            actualMirror = mirror
        }
        
        // Check for properties field
        for child in actualMirror.children {
            if child.label == "properties" {
                return true
            }
        }
        
        return false
    }
    
    /// Extract node properties or return the value if it's already a dictionary
    /// - Parameter value: The value from query result dictionary
    /// - Returns: Properties dictionary suitable for decoding
    public static func extractNodeOrDictionary(from value: Any) -> [String: Any?]? {
        // Check if it's a KuzuNode
        if isKuzuNode(value) {
            return extractProperties(from: value)
        }
        
        // Otherwise try to use it as a dictionary directly
        return value as? [String: Any?]
    }
}