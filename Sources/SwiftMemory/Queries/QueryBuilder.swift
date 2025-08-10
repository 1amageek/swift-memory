import Foundation

/// Builder for creating Cypher queries in a type-safe manner
public struct CypherQueryBuilder {
    
    // MARK: - Session Queries
    
    public enum SessionQueries {
        public static func create(session: Session) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: "CREATE (s:Session $props) RETURN s",
                bindings: ["props": ["id": session.id as any Sendable, "title": session.title as any Sendable, "startedAt": session.startedAt as any Sendable] as [String: any Sendable]]
            )
        }
        
        public static func findById(id: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: "MATCH (s:Session {id: $id}) RETURN s",
                bindings: ["id": id]
            )
        }
        
        public static func list(startedAfter: Date? = nil, startedBefore: Date? = nil) -> (query: String, bindings: [String: any Sendable]) {
            var query = "MATCH (s:Session)"
            var whereConditions: [String] = []
            var bindings: [String: any Sendable] = [:]
            
            if let after = startedAfter {
                whereConditions.append("s.startedAt >= $startedAfter")
                bindings["startedAfter"] = after
            }
            
            if let before = startedBefore {
                whereConditions.append("s.startedAt <= $startedBefore")
                bindings["startedBefore"] = before
            }
            
            if !whereConditions.isEmpty {
                query += " WHERE " + whereConditions.joined(separator: " AND ")
            }
            
            query += " RETURN s ORDER BY s.startedAt DESC"
            
            return (query: query, bindings: bindings)
        }
        
        public static func update(id: UUID, title: String) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: "MATCH (s:Session {id: $id}) SET s.title = $title RETURN s",
                bindings: ["id": id, "title": title]
            )
        }
        
        public static func delete(id: UUID, cascade: Bool) -> (query: String, bindings: [String: any Sendable]) {
            if cascade {
                // Note: This is not currently used but kept for API compatibility
                // Actual implementation uses separate queries in SessionManager
                return (
                    query: """
                        MATCH (s:Session {id: $sessionID})
                        OPTIONAL MATCH (s)-[:HasTask]->(t:Task)
                        OPTIONAL MATCH (t)-[:SubTaskOf*]->(child:Task)
                        DETACH DELETE child, t, s
                        RETURN COUNT(*) as deleted
                        """,
                    bindings: ["sessionID": id]
                )
            } else {
                return (
                    query: "MATCH (s:Session {id: $sessionID}) DETACH DELETE s RETURN COUNT(*) as deleted",
                    bindings: ["sessionID": id]
                )
            }
        }
    }
    
    // MARK: - Task Queries
    
    public enum TaskQueries {
        public static func findTasksInSession(
            sessionID: UUID,
            status: TaskStatus? = nil,
            assignee: String? = nil,
            difficultyMax: Int? = nil,
            readyOnly: Bool = false
        ) -> (query: String, bindings: [String: any Sendable]) {
            var query = "MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)"
            var whereConditions: [String] = []
            var bindings: [String: any Sendable] = ["sessionID": sessionID]
            
            if let status = status {
                whereConditions.append("t.status = $status")
                bindings["status"] = status.rawValue
            }
            
            if let assignee = assignee {
                whereConditions.append("t.assignee = $assignee")
                bindings["assignee"] = assignee
            }
            
            if let difficultyMax = difficultyMax {
                whereConditions.append("t.difficulty <= $difficultyMax")
                bindings["difficultyMax"] = difficultyMax
            }
            
            if readyOnly {
                whereConditions.append("t.status IN ['pending', 'inProgress']")
                whereConditions.append("NOT EXISTS { MATCH (blocker:Task)-[:Blocks]->(t) WHERE blocker.status IN ['pending', 'inProgress'] }")
            }
            
            if !whereConditions.isEmpty {
                query += " WHERE " + whereConditions.joined(separator: " AND ")
            }
            
            query += " RETURN t ORDER BY r.`order` ASC"
            
            return (query: query, bindings: bindings)
        }
        
        public static func getNextOrder(sessionID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
                    RETURN max(r.`order`) as maxOrder
                    """,
                bindings: ["sessionID": sessionID]
            )
        }
        
        public static func createTaskRelationship(sessionID: UUID, taskID: UUID, order: Int) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (s:Session {id: $sessionID}), (t:Task {id: $taskID})
                    MERGE (s)-[r:HasTask]->(t)
                    SET r.`order` = $orderValue
                    RETURN r
                    """,
                bindings: ["sessionID": sessionID, "taskID": taskID, "orderValue": order]
            )
        }
        
        public static func createParentRelationship(childID: UUID, parentID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (child:Task {id: $childID}), (parent:Task {id: $parentID})
                    MERGE (child)-[r:SubTaskOf]->(parent)
                    RETURN r
                    """,
                bindings: ["childID": childID, "parentID": parentID]
            )
        }
        
        public static func reorderTasks(sessionID: UUID, taskOrders: [(UUID, Int)]) -> (query: String, bindings: [String: any Sendable]) {
            let updateClauses = taskOrders.enumerated().map { index, taskOrder in
                "WHEN t.id = $taskID\(index) THEN $orderValue\(index)"
            }.joined(separator: " ")
            
            var bindings: [String: any Sendable] = ["sessionID": sessionID]
            for (index, (taskID, order)) in taskOrders.enumerated() {
                bindings["taskID\(index)"] = taskID
                bindings["orderValue\(index)"] = order
            }
            
            return (
                query: """
                    MATCH (s:Session {id: $sessionID})-[r:HasTask]->(t:Task)
                    SET r.`order` = CASE \(updateClauses) ELSE r.`order` END
                    RETURN COUNT(*) as updated
                    """,
                bindings: bindings
            )
        }
    }
    
    // MARK: - Dependency Queries
    
    public enum DependencyQueries {
        public static func checkCircularDependency(blockerID: UUID, blockedID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH p = (blocked:Task {id: $blockedID})-[:Blocks*]->(blocker:Task {id: $blockerID})
                    RETURN COUNT(p) > 0 AS hasCycle
                    """,
                bindings: ["blockedID": blockedID, "blockerID": blockerID]
            )
        }
        
        public static func addDependency(blockerID: UUID, blockedID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (blocker:Task {id: $blockerID}), (blocked:Task {id: $blockedID})
                    MERGE (blocker)-[r:Blocks]->(blocked)
                    RETURN r
                    """,
                bindings: ["blockerID": blockerID, "blockedID": blockedID]
            )
        }
        
        public static func removeDependency(blockerID: UUID, blockedID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (blocker:Task {id: $blockerID})-[r:Blocks]->(blocked:Task {id: $blockedID})
                    WITH r
                    DELETE r
                    RETURN COUNT(*) as deleted
                    """,
                bindings: ["blockerID": blockerID, "blockedID": blockedID]
            )
        }
        
        public static func getBlockers(taskID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    RETURN blocker
                    ORDER BY blocker.createdAt ASC
                    """,
                bindings: ["taskID": taskID]
            )
        }
        
        public static func getBlocking(taskID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (blocker:Task {id: $taskID})-[:Blocks]->(blocked:Task)
                    RETURN blocked
                    ORDER BY blocked.createdAt ASC
                    """,
                bindings: ["taskID": taskID]
            )
        }
        
        public static func isTaskBlocked(taskID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (blocker:Task)-[:Blocks]->(blocked:Task {id: $taskID})
                    WHERE blocker.status IN ['pending', 'inProgress']
                    RETURN COUNT(blocker) > 0 AS isBlocked
                    """,
                bindings: ["taskID": taskID]
            )
        }
        
        public static func getDependencyChain(taskID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH path = (blocker:Task)-[:Blocks*]->(blocked:Task {id: $taskID})
                    WITH blocker, min(length(path)) as depth
                    RETURN blocker, depth
                    ORDER BY depth DESC
                    """,
                bindings: ["taskID": taskID]
            )
        }
    }
    
    // MARK: - Hierarchy Queries
    
    public enum HierarchyQueries {
        public static func checkParentCycle(parentID: UUID, childID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH p = (parent:Task {id: $parentID})-[:SubTaskOf*]->(child:Task {id: $childID})
                    RETURN COUNT(p) > 0 AS hasCycle
                    """,
                bindings: ["parentID": parentID, "childID": childID]
            )
        }
        
        public static func getSubtasks(parentID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (t:Task)-[:SubTaskOf]->(parent:Task {id: $parentID})
                    RETURN t
                    ORDER BY t.createdAt ASC
                    """,
                bindings: ["parentID": parentID]
            )
        }
        
        public static func removeParentRelationship(childID: UUID) -> (query: String, bindings: [String: any Sendable]) {
            return (
                query: """
                    MATCH (child:Task {id: $childID})-[r:SubTaskOf]->(:Task)
                    WITH r
                    DELETE r
                    RETURN COUNT(*) as deleted
                    """,
                bindings: ["childID": childID]
            )
        }
    }
}