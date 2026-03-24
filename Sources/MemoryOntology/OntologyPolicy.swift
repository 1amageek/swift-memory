// OntologyPolicy.swift
// Protocol for ontology design policies

import Database

/// Ontology design policy that defines the allowed class hierarchy and properties.
///
/// The policy acts as a gatekeeper: only classes and properties declared here
/// can be used by `@OWLClass` entities registered with `Memory`.
///
/// Provide a custom implementation to extend or replace the default ontology.
/// When omitted, `DefaultOntologyPolicy` is used.
public protocol OntologyPolicy: Sendable {

    /// Top-level classes (no parent, direct subclass of owl:Thing).
    var primitiveClasses: [(iri: String, label: String)] { get }

    /// Subclasses with their parent class.
    var seedSubClasses: [(iri: String, label: String, superClass: String)] { get }

    /// Allowed object property IRIs (e.g. "ex:worksAt", "ex:partOf").
    var objectPropertyIRIs: Set<String> { get }

    /// Allowed data property IRIs (e.g. "ex:email", "ex:status").
    var dataPropertyIRIs: Set<String> { get }

    /// Build the complete OWL ontology (TBox + RBox).
    func buildOntology() -> OWLOntology

    /// LLM-facing definition text (ontology vocabulary + design rules).
    var definition: String { get }
}

extension OntologyPolicy {

    /// All valid class IRIs (primitives + subclasses).
    public var allClassIRIs: Set<String> {
        var iris = Set(primitiveClasses.map(\.iri))
        for sub in seedSubClasses {
            iris.insert(sub.iri)
        }
        return iris
    }

    /// Validate that a type IRI exists in this policy.
    public func validate(typeIRI: String) -> Bool {
        allClassIRIs.contains(typeIRI)
    }
}
