// KnowledgeEncodingContainer.swift
// Container for submitting statements to Knowledge Store

import Synchronization

/// A raw statement submitted for the Knowledge Store.
public struct RawStatement: Sendable {
    /// Subject IRI.
    public var subject: String

    /// Predicate IRI.
    public var predicate: String

    /// Object IRI or literal value.
    public var object: String

    public init(subject: String, predicate: String, object: String) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

/// Container that collects statements for the Knowledge Store.
///
/// `MemoryEncodable` types submit their structured relationships here.
/// The `MemoryEncoding` implementation later processes these into
/// `Statement` objects for persistence.
public final class KnowledgeEncodingContainer: Sendable {

    private let statements: Mutex<[RawStatement]> = Mutex([])

    public init() {}

    /// Submit a knowledge statement (subject-predicate-object).
    public func encode(subject: String, predicate: String, object: String) {
        statements.withLock { $0.append(RawStatement(subject: subject, predicate: predicate, object: object)) }
    }

    /// Collect all submitted statements.
    public func collectStatements() -> [RawStatement] {
        statements.withLock { $0 }
    }
}
