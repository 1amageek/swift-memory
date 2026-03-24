// DefaultOntologyPolicy.swift
// Default ontology policy with 26 primitive classes and ~120 subclasses

import Database

/// Default ontology policy.
///
/// Provides the standard upper ontology (26 primitive classes, ~120 subclasses,
/// standard properties). Used as the default when no custom policy is provided.
public struct DefaultOntologyPolicy: OntologyPolicy, Sendable {

    public init() {}

    public let primitiveClasses: [(iri: String, label: String)] = [
        ("ex:Person", "Person"),
        ("ex:Organization", "Organization"),
        ("ex:Place", "Place"),
        ("ex:Facility", "Facility"),
        ("ex:Occurrent", "Occurrent"),
        ("ex:Activity", "Activity"),
        ("ex:Education", "Education"),
        ("ex:Product", "Product"),
        ("ex:Service", "Service"),
        ("ex:Technology", "Technology"),
        ("ex:CreativeWork", "CreativeWork"),
        ("ex:Award", "Award"),
        ("ex:Regulation", "Regulation"),
        ("ex:Industry", "Industry"),
        ("ex:Market", "Market"),
        ("ex:Metric", "Metric"),
        ("ex:Method", "Method"),
        ("ex:TransportationMode", "TransportationMode"),
        ("ex:Organism", "Organism"),
        ("ex:Disease", "Disease"),
        ("ex:Ideology", "Ideology"),
        ("ex:Language", "Language"),
        ("ex:Food", "Food"),
        ("ex:Sport", "Sport"),
        ("ex:NaturalResource", "NaturalResource"),
        ("ex:Brand", "Brand"),
    ]

    // Only subclasses with unique domain-constrained properties are kept.
    // hasParticipant domain: Event, causes domain/range: Event → Event needed.
    // Era is disjoint with Event under Occurrent → Era needed.
    // All other subclasses share parent properties — use rdfs:label for specificity.
    public let seedSubClasses: [(iri: String, label: String, superClass: String)] = [
        ("ex:Event", "Event", "ex:Occurrent"),
        ("ex:Era", "Era", "ex:Occurrent"),
    ]

    /// 上位オントロジーの全 IRI セット（トップレベル + サブクラス）
    public let objectPropertyIRIs: Set<String> = [
        "ex:partOf", "ex:hasPart",
        "ex:locatedIn",
        "ex:hasFounder", "ex:founderOf",
        "ex:memberOf", "ex:hasMember",
        "ex:produces", "ex:producedBy",
        "ex:hasParticipant", "ex:participatesIn",
        "ex:causes", "ex:causedBy",
    ]

    public let dataPropertyIRIs: Set<String> = [
        "ex:date", "ex:time",
        "ex:startDate", "ex:endDate",
        "ex:wikipediaURL", "ex:officialURL", "ex:imageURL",
    ]

    // MARK: - Build Ontology

    public func buildOntology() -> OWLOntology {
        OWLOntology(iri: "memory:", prefixes: ["ex": "http://example.org/"]) {

            // ── TBox: Primitive Classes (→ owl:Thing) ──

            for (iri, label) in primitiveClasses {
                OWLClass(iri: iri, label: label)
                OWLAxiom.subClassOf(sub: .named(iri), sup: .thing)
            }

            // ── TBox: Sub Classes ──

            for (iri, label, superClass) in seedSubClasses {
                OWLClass(iri: iri, label: label)
                OWLAxiom.subClassOf(sub: .named(iri), sup: .named(superClass))
            }

            // ── TBox: Disjoint Classes ──

            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Organization")])
            OWLAxiom.disjointClasses([.named("ex:Person"), .named("ex:Place")])
            OWLAxiom.disjointClasses([.named("ex:Occurrent"), .named("ex:Person")])
            OWLAxiom.disjointClasses([.named("ex:Occurrent"), .named("ex:Organization")])
            OWLAxiom.disjointClasses([.named("ex:Occurrent"), .named("ex:Place")])
            OWLAxiom.disjointClasses([.named("ex:Product"), .named("ex:Service")])
            OWLAxiom.disjointClasses([.named("ex:Organism"), .named("ex:Organization")])
            OWLAxiom.disjointClasses([.named("ex:Event"), .named("ex:Era")])

            // ── RBox: Universal Object Properties ──

            OWLObjectProperty(
                iri: "ex:partOf",
                label: "part of",
                characteristics: [.transitive],
                inverseOf: "ex:hasPart"
            )
            OWLObjectProperty(
                iri: "ex:hasPart",
                label: "has part",
                characteristics: [.transitive],
                inverseOf: "ex:partOf"
            )

            OWLObjectProperty(
                iri: "ex:locatedIn",
                label: "located in",
                characteristics: [.transitive],
                ranges: [.named("ex:Place")]
            )

            OWLObjectProperty(
                iri: "ex:hasFounder",
                label: "has founder",
                inverseOf: "ex:founderOf"
            )
            OWLObjectProperty(
                iri: "ex:founderOf",
                label: "founder of",
                inverseOf: "ex:hasFounder"
            )

            OWLObjectProperty(
                iri: "ex:memberOf",
                label: "member of",
                inverseOf: "ex:hasMember"
            )
            OWLObjectProperty(
                iri: "ex:hasMember",
                label: "has member",
                inverseOf: "ex:memberOf"
            )

            OWLObjectProperty(
                iri: "ex:produces",
                label: "produces",
                inverseOf: "ex:producedBy"
            )
            OWLObjectProperty(
                iri: "ex:producedBy",
                label: "produced by",
                inverseOf: "ex:produces"
            )

            // ── RBox: Event Object Properties ──

            OWLObjectProperty(
                iri: "ex:hasParticipant",
                label: "has participant",
                inverseOf: "ex:participatesIn",
                domains: [.named("ex:Event")]
            )
            OWLObjectProperty(
                iri: "ex:participatesIn",
                label: "participates in",
                inverseOf: "ex:hasParticipant",
                ranges: [.named("ex:Event")]
            )

            OWLObjectProperty(
                iri: "ex:causes",
                label: "causes",
                inverseOf: "ex:causedBy",
                domains: [.named("ex:Event")],
                ranges: [.named("ex:Event")]
            )
            OWLObjectProperty(
                iri: "ex:causedBy",
                label: "caused by",
                inverseOf: "ex:causes",
                domains: [.named("ex:Event")],
                ranges: [.named("ex:Event")]
            )

            // ── RBox: Occurrent Data Properties (shared by Event and Era) ──

            OWLDataProperty(
                iri: "ex:date",
                label: "date",
                domains: [.named("ex:Occurrent")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )
            OWLDataProperty(
                iri: "ex:time",
                label: "time",
                domains: [.named("ex:Occurrent")],
                ranges: [.datatype(XSDDatatype.time.iri)]
            )
            OWLDataProperty(
                iri: "ex:startDate",
                label: "start date",
                domains: [.named("ex:Occurrent")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )
            OWLDataProperty(
                iri: "ex:endDate",
                label: "end date",
                domains: [.named("ex:Occurrent")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )

            // ── RBox: External Reference Data Properties ──

            OWLDataProperty(
                iri: "ex:wikipediaURL",
                label: "Wikipedia URL",
                domains: [.thing],
                ranges: [.datatype(XSDDatatype.anyURI.iri)]
            )
            OWLDataProperty(
                iri: "ex:officialURL",
                label: "official URL",
                domains: [.thing],
                ranges: [.datatype(XSDDatatype.anyURI.iri)]
            )
            OWLDataProperty(
                iri: "ex:imageURL",
                label: "image URL",
                domains: [.thing],
                ranges: [.datatype(XSDDatatype.anyURI.iri)]
            )
        }
    }

    /// Upper ontology as Turtle text for LLM context.
    public var upperOntologyText: String {
        buildOntology().toTurtle()
    }

    public var definition: String {
        """
    # Ontology Design Policy

    ## Predicate Archetypes
    mereology | location | association | participation |
    causation | dependency | reference | identity | provenance | temporal

    ## Predicate Naming Templates
    - hasX / isXOf (general)
    - partOf / hasPart (mereology)
    - locatedIn (location)
    - affiliatedWith / associatedWith (association)
    - participatesIn / hasParticipant (participation)
    - causes / causedBy / affects (causation)
    - dependsOn / requires (dependency)
    - refersTo / mentions (reference)
    - sameAs / exactMatch / closeMatch (identity)
    - derivedFrom / hasSource (provenance)
    - date / time / startDate / endDate (temporal)

    ## When to Create a Subclass

    The only reason to create a subclass is when the group has domain-specific properties.
    Does it have properties the parent doesn't? YES → subclass. NO → use attribute values, relationships, or Defined Class.

    ## Class Hierarchy
    - Define classes at meaningful levels of abstraction
    - Parent classes capture shared properties of children
    - All classes must connect to one of the available classes below

    ## Available Classes

    All listed below are pre-defined. Do not redefine them.
    New classes must specify the most specific existing class as superClass.
    If an existing class can serve as rdf:type, do not create a new one.

    ### Upper Ontology (Seed)

    \(upperOntologyText)

    ## Property Design
    - Object properties: relationships between entities
    - Data properties: attribute values
    - domain/range are managed by the system. Do not set them manually.

    ### Object Property Naming
    - Forward: hasX (ex:hasFounder, ex:hasMember)
    - Inverse: isXOf / XOf / XBy (ex:founderOf, ex:memberOf, ex:createdBy)
    - Forward and inverse are separate properties linked by owl:inverseOf
    - Do not define both isXOf and XOf for the same concept (pick one)
    - Prefer short, generic names (ex:founded > ex:foundedCompany)

    ### Inverse Properties (owl:inverseOf)
    - "A hasX B" ⇔ "B XOf A" is an inverse property pair
    - Never merge inverse properties (subject and object swap)
    - Patterns:
      - hasX ↔ isXOf / XOf (ex:hasFounder ↔ ex:founderOf)
      - X ↔ XBy (ex:acquired ↔ ex:acquiredBy)
      - hasPart ↔ partOf (standard mereology pair)

    ### No name-specific DataProperties
    - Use rdfs:label for entity names
    - Do not define companyName, personName, productName, etc.
    - rdfs:label is a standard property — no need to define it

    ### DataProperty Naming
    - Prefer short, generic names (ex:revenue > ex:revenueAmount)
    - Omit redundant suffixes like Amount, Value, Count

    ## DataProperty Value Rules
    - Values must be atomic (numbers, dates, short labels, URIs)
    - Sentences or descriptions are not valid values

    ## Defined Class (Structural Classification)
    - A class that auto-classifies instances meeting certain conditions (equivalentClass)
    - The Reasoner automatically assigns rdf:type to matching instances

    ## TBox and ABox
    - TBox (terminological): class, property, and hierarchy definitions
    - ABox (assertional): concrete instances with their attributes and relationships

    ## Event Model (Event Reification)

    Occurrences are stored as entities.
    Events are named individuals, not intermediate nodes.

    ### Base Classes
    - ex:Event — base class for all events. Specific event types are subclasses.
    - ex:Era — named time period (e.g. Renaissance, Edo period). Not an event, but a temporal frame. Uses startDate / endDate.

    ### Use the Most Specific rdf:type
    - Refer to the upper ontology hierarchy and assign the most specific subclass as rdf:type
    - Battle → ex:Battle (not ex:Event)
    - Acquisition → ex:Acquisition (not ex:Agreement)
    - Appointment → ex:Appointment (not ex:Transition)
    - Exhibition → ex:Exhibition (not ex:Gathering)
    - Earthquake → ex:Earthquake (not ex:NaturalDisaster)
    - Birth → ex:Birth, Death → ex:Death
    - Era → ex:Era (not ex:Event)
    - The reasoner infers superClass types automatically — no need for parent rdf:type
    - Assign exactly one rdf:type per entity (the most specific)

    ### Event Subtypes
    Refer to the Event subtree in the upper ontology.
    New event classes should be defined as children of the closest subtype.

    ### Event Temporal Properties (DataProperty)
    - ex:date — date (domain: ex:Occurrent, range: ISO 8601 xsd:gYear / xsd:gYearMonth / xsd:date). Past or future.
    - ex:time — time of day (domain: ex:Occurrent, range: xsd:time HH:MM:SS). Only when explicitly stated.
    - ex:startDate — period start (domain: ex:Occurrent, same range)
    - ex:endDate — period end (domain: ex:Occurrent, same range)

    ### Event Relationship Properties (ObjectProperty)
    - ex:hasParticipant — participating entity (domain: ex:Event, archetype: participation)
    - ex:causes — event-to-event causation (domain: ex:Event, range: ex:Event, archetype: causation)

    ### Universal Relationship Properties (ObjectProperty)
    Pre-seeded. Do not redefine.
    - ex:partOf / ex:hasPart — part-whole hierarchy (transitive, mereology)
    - ex:locatedIn — location (transitive, range: ex:Place)
    - ex:hasFounder / ex:founderOf — founder (association)
    - ex:hasMember / ex:memberOf — membership (association)
    - ex:produces / ex:producedBy — production (association)

    ### Direct Relationships Alongside Events
    In addition to events, direct relationships between participants exist.
    Both event-mediated and direct paths should be searchable.

    ## External References (DataProperty)

    Record URLs of external resources related to entities.

    ### Standard Properties
    - ex:wikipediaURL — Wikipedia page URL (domain: owl:Thing, range: xsd:anyURI)
    - ex:officialURL — official website URL (domain: owl:Thing, range: xsd:anyURI)
    - ex:imageURL — image URL (domain: owl:Thing, range: xsd:anyURI)

    ### Rules
    - Store URLs as-is in the object position (no shortening)
    - Multiple URLs of the same type per entity are allowed
    - Do not fabricate URLs — only record when present in source text
    - These are standard DataProperties — no need to redefine

    ## IRI Naming
    - Use prefixed short forms (ex:Company, ex:name)
    - Classes: UpperCamelCase (ex:Person)
    - Properties: lowerCamelCase (ex:hasAuthor)
    - Entities: use ASCII identifiers
    - Do not use non-ASCII characters in IRIs

    ## rdfs:label (Required)

    Every entity must have an rdfs:label.
    Use the **original language form** from the source text.

    ### Rules
    - rdfs:label is a standard property — no need to define it
    - Store names as they appear in the text (person names, org names, product names, etc.)
    - This is required for label-based recall in any language

    ## Category Exclusivity

    Some classes are mutually exclusive — an individual cannot belong to both.
    Disjoint declarations are used by the Reasoner to detect misclassification.

    ### Disjoint Categories
    - Person and Organization
    - Person and Place
    - Occurrent and Person / Organization / Place
    - Event and Era
    - Product and Service
    - Organism and Organization

    ### Non-Disjoint Categories
    - Facility and Organization (a university is both)
    - Technology and Product (software is both)
    - Activity and Event (an activity may be recorded as an event)

    ### Decision Rule
    - If a realistic scenario exists where one individual belongs to both, do not declare disjoint
    - When in doubt, do not declare (false disjoint breaks reasoning)

    ## Property Characteristics

    When defining an ObjectProperty, declare its characteristics.
    The Reasoner uses these to infer implicit triples.

    ### Transitivity
    A→B and B→C implies A→C. For containment and hierarchy.
    - locatedIn: a building in Shibuya is also in Tokyo, also in Japan
    - partOf: a piston in an engine, engine in a car → piston in a car
    - subOrganizationOf: department → division → headquarters

    Do NOT declare transitive:
    - hasFounder, hasParent — only direct relationships are meaningful

    ### Symmetry
    A→B implies B→A. For peer relationships.
    - allianceWith, competitorOf, siblingOf, adjacentTo

    ### Functional
    At most one object per subject.
    - hasBirthPlace, hasHeadquarters, hasCapital

    Do NOT declare functional:
    - hasMember, hasProduct — can have multiple values

    ### Inverse Functional
    At most one subject per object. For identifier-like relationships.
    - hasIBAN, hasStockTicker

    ### Asymmetric
    A→B does not imply B→A. For fixed-direction relationships.
    - parentOf, supervises, partOf

    ### Decision Rule
    - Only declare if it holds universally without exception
    - Transitivity is the most impactful — be most cautious
    - Functional declarations cause contradictions when multiple values exist

    ## Temporal Precision

    Preserve the precision of date/time information from source text.
    Do not round or fill in missing precision.
    - "2024" → xsd:gYear (not "2024-01-01")
    - "March 2024" → xsd:gYearMonth
    - "March 15, 2024" → xsd:date
    """
    }
}
