// OntologyPolicy.swift
// Write/Read 共通のオントロジー設計方針

import Database
import Hoot

/// オントロジー設計方針
///
/// WriteStep（保存）と ReadStep（検索）の両方が参照する共通知識。
/// LLM が正しい述語名・クラス構造・イベントモデルで動作するための定義。
public enum OntologyPolicy {

    /// 上位オントロジーのトップレベルクラス（親なし）
    public static let primitiveClasses: [(iri: String, label: String)] = [
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

    /// 上位オントロジーの階層（シード時に subClassOf axiom も追加する）
    public static let seedSubClasses: [(iri: String, label: String, superClass: String)] = [
        // Person
        ("ex:Politician", "Politician", "ex:Person"),
        ("ex:Ruler", "Ruler", "ex:Person"),
        ("ex:MilitaryLeader", "MilitaryLeader", "ex:Person"),
        ("ex:Executive", "Executive", "ex:Person"),
        ("ex:Investor", "Investor", "ex:Person"),
        ("ex:Scientist", "Scientist", "ex:Person"),
        ("ex:Artist", "Artist", "ex:Person"),
        ("ex:Athlete", "Athlete", "ex:Person"),
        ("ex:ReligiousLeader", "ReligiousLeader", "ex:Person"),

        // Organization
        ("ex:Company", "Company", "ex:Organization"),
        ("ex:GovernmentAgency", "GovernmentAgency", "ex:Organization"),
        ("ex:NonProfitOrganization", "NonProfitOrganization", "ex:Organization"),
        ("ex:MediaOrganization", "MediaOrganization", "ex:Organization"),
        ("ex:InternationalOrganization", "InternationalOrganization", "ex:Organization"),
        ("ex:AcademicInstitution", "AcademicInstitution", "ex:Organization"),
        ("ex:MilitaryOrganization", "MilitaryOrganization", "ex:Organization"),
        ("ex:PoliticalOrganization", "PoliticalOrganization", "ex:Organization"),
        // AcademicInstitution
        ("ex:University", "University", "ex:AcademicInstitution"),
        ("ex:ResearchInstitute", "ResearchInstitute", "ex:AcademicInstitution"),
        // GovernmentAgency
        ("ex:Municipality", "Municipality", "ex:GovernmentAgency"),
        // NonProfitOrganization
        ("ex:Foundation", "Foundation", "ex:NonProfitOrganization"),
        // PoliticalOrganization
        ("ex:PoliticalParty", "PoliticalParty", "ex:PoliticalOrganization"),

        // Place
        ("ex:Country", "Country", "ex:Place"),
        ("ex:Region", "Region", "ex:Place"),
        ("ex:City", "City", "ex:Place"),
        ("ex:Continent", "Continent", "ex:Place"),
        ("ex:GeographicFeature", "GeographicFeature", "ex:Place"),
        // GeographicFeature
        ("ex:WaterBody", "WaterBody", "ex:GeographicFeature"),
        ("ex:Landform", "Landform", "ex:GeographicFeature"),
        // WaterBody
        ("ex:Ocean", "Ocean", "ex:WaterBody"),
        ("ex:Sea", "Sea", "ex:WaterBody"),
        ("ex:River", "River", "ex:WaterBody"),
        ("ex:Lake", "Lake", "ex:WaterBody"),
        // Landform
        ("ex:Mountain", "Mountain", "ex:Landform"),
        ("ex:Desert", "Desert", "ex:Landform"),
        ("ex:Island", "Island", "ex:Landform"),
        ("ex:Peninsula", "Peninsula", "ex:Landform"),

        // Facility
        ("ex:Factory", "Factory", "ex:Facility"),
        ("ex:Office", "Office", "ex:Facility"),
        ("ex:MedicalFacility", "MedicalFacility", "ex:Facility"),
        ("ex:EducationalFacility", "EducationalFacility", "ex:Facility"),
        ("ex:Infrastructure", "Infrastructure", "ex:Facility"),
        ("ex:ResearchFacility", "ResearchFacility", "ex:Facility"),
        ("ex:ReligiousFacility", "ReligiousFacility", "ex:Facility"),
        // MedicalFacility
        ("ex:Hospital", "Hospital", "ex:MedicalFacility"),
        ("ex:Clinic", "Clinic", "ex:MedicalFacility"),
        // EducationalFacility
        ("ex:School", "School", "ex:EducationalFacility"),
        // Infrastructure
        ("ex:Airport", "Airport", "ex:Infrastructure"),
        ("ex:Port", "Port", "ex:Infrastructure"),
        ("ex:Bridge", "Bridge", "ex:Infrastructure"),
        ("ex:Station", "Station", "ex:Infrastructure"),
        // ResearchFacility
        ("ex:Laboratory", "Laboratory", "ex:ResearchFacility"),
        // ReligiousFacility
        ("ex:Temple", "Temple", "ex:ReligiousFacility"),
        ("ex:Church", "Church", "ex:ReligiousFacility"),
        ("ex:Mosque", "Mosque", "ex:ReligiousFacility"),

        // Occurrent
        ("ex:Event", "Event", "ex:Occurrent"),
        ("ex:Era", "Era", "ex:Occurrent"),
        // Event
        ("ex:Agreement", "Agreement", "ex:Event"),
        ("ex:Announcement", "Announcement", "ex:Event"),
        ("ex:Transition", "Transition", "ex:Event"),
        ("ex:Gathering", "Gathering", "ex:Event"),
        ("ex:Incident", "Incident", "ex:Event"),
        ("ex:Election", "Election", "ex:Event"),
        ("ex:LegalAction", "LegalAction", "ex:Event"),
        ("ex:Birth", "Birth", "ex:Event"),
        ("ex:Death", "Death", "ex:Event"),
        ("ex:Discovery", "Discovery", "ex:Event"),
        // Agreement
        ("ex:Acquisition", "Acquisition", "ex:Agreement"),
        ("ex:Merger", "Merger", "ex:Agreement"),
        ("ex:Partnership", "Partnership", "ex:Agreement"),
        ("ex:Funding", "Funding", "ex:Agreement"),
        // Announcement
        ("ex:Launch", "Launch", "ex:Announcement"),
        ("ex:Disclosure", "Disclosure", "ex:Announcement"),
        ("ex:Release", "Release", "ex:Announcement"),
        // Transition
        ("ex:Founding", "Founding", "ex:Transition"),
        ("ex:Appointment", "Appointment", "ex:Transition"),
        ("ex:Restructuring", "Restructuring", "ex:Transition"),
        ("ex:Listing", "Listing", "ex:Transition"),
        // Gathering
        ("ex:Exhibition", "Exhibition", "ex:Gathering"),
        ("ex:Conference", "Conference", "ex:Gathering"),
        ("ex:Competition", "Competition", "ex:Gathering"),
        ("ex:Ceremony", "Ceremony", "ex:Gathering"),
        ("ex:Festival", "Festival", "ex:Gathering"),
        // Incident
        ("ex:Accident", "Accident", "ex:Incident"),
        ("ex:NaturalDisaster", "NaturalDisaster", "ex:Incident"),
        ("ex:Crisis", "Crisis", "ex:Incident"),
        ("ex:Crime", "Crime", "ex:Incident"),
        ("ex:Conflict", "Conflict", "ex:Incident"),
        // NaturalDisaster
        ("ex:Earthquake", "Earthquake", "ex:NaturalDisaster"),
        ("ex:Flood", "Flood", "ex:NaturalDisaster"),
        ("ex:Typhoon", "Typhoon", "ex:NaturalDisaster"),
        ("ex:Drought", "Drought", "ex:NaturalDisaster"),
        ("ex:Wildfire", "Wildfire", "ex:NaturalDisaster"),
        // Conflict
        ("ex:War", "War", "ex:Conflict"),
        ("ex:Battle", "Battle", "ex:Conflict"),
        ("ex:Revolution", "Revolution", "ex:Conflict"),
        ("ex:MilitaryCampaign", "MilitaryCampaign", "ex:Conflict"),
        // Battle
        ("ex:Siege", "Siege", "ex:Battle"),
        // LegalAction
        ("ex:Lawsuit", "Lawsuit", "ex:LegalAction"),
        ("ex:Sanction", "Sanction", "ex:LegalAction"),

        // Activity
        ("ex:Project", "Project", "ex:Activity"),
        ("ex:Program", "Program", "ex:Activity"),
        ("ex:Campaign", "Campaign", "ex:Activity"),
        ("ex:Research", "Research", "ex:Activity"),

        // Education
        ("ex:Curriculum", "Curriculum", "ex:Education"),
        ("ex:Training", "Training", "ex:Education"),

        // Product
        ("ex:Vehicle", "Vehicle", "ex:Product"),
        ("ex:Device", "Device", "ex:Product"),
        ("ex:SoftwareProduct", "SoftwareProduct", "ex:Product"),
        ("ex:Pharmaceutical", "Pharmaceutical", "ex:Product"),
        ("ex:FinancialProduct", "FinancialProduct", "ex:Product"),
        ("ex:Material", "Material", "ex:Product"),
        ("ex:Artifact", "Artifact", "ex:Product"),
        // Vehicle
        ("ex:Car", "Car", "ex:Vehicle"),
        ("ex:Ship", "Ship", "ex:Vehicle"),
        ("ex:Aircraft", "Aircraft", "ex:Vehicle"),
        ("ex:Train", "Train", "ex:Vehicle"),
        ("ex:Bus", "Bus", "ex:Vehicle"),
        // Device
        ("ex:Computer", "Computer", "ex:Device"),
        ("ex:Smartphone", "Smartphone", "ex:Device"),
        ("ex:Robot", "Robot", "ex:Device"),
        // Pharmaceutical
        ("ex:Vaccine", "Vaccine", "ex:Pharmaceutical"),

        // Service
        ("ex:ProfessionalService", "ProfessionalService", "ex:Service"),
        ("ex:DigitalService", "DigitalService", "ex:Service"),
        ("ex:FinancialService", "FinancialService", "ex:Service"),
        ("ex:PublicService", "PublicService", "ex:Service"),

        // Technology
        ("ex:Software", "Software", "ex:Technology"),
        ("ex:Hardware", "Hardware", "ex:Technology"),
        // Hardware
        ("ex:Semiconductor", "Semiconductor", "ex:Hardware"),

        // CreativeWork
        ("ex:Publication", "Publication", "ex:CreativeWork"),
        ("ex:Media", "Media", "ex:CreativeWork"),
        ("ex:Artwork", "Artwork", "ex:CreativeWork"),
        ("ex:Patent", "Patent", "ex:CreativeWork"),
        ("ex:Game", "Game", "ex:CreativeWork"),
        // Publication
        ("ex:Book", "Book", "ex:Publication"),
        ("ex:Journal", "Journal", "ex:Publication"),
        ("ex:Newspaper", "Newspaper", "ex:Publication"),
        ("ex:Report", "Report", "ex:Publication"),
        // Media
        ("ex:Film", "Film", "ex:Media"),
        ("ex:Music", "Music", "ex:Media"),

        // Award
        ("ex:Prize", "Prize", "ex:Award"),
        ("ex:Certification", "Certification", "ex:Award"),
        ("ex:Ranking", "Ranking", "ex:Award"),

        // Regulation
        ("ex:Legislation", "Legislation", "ex:Regulation"),
        ("ex:Policy", "Policy", "ex:Regulation"),
        ("ex:Treaty", "Treaty", "ex:Regulation"),
        ("ex:Standard", "Standard", "ex:Regulation"),

        // Industry
        ("ex:ManufacturingIndustry", "ManufacturingIndustry", "ex:Industry"),
        ("ex:ServiceIndustry", "ServiceIndustry", "ex:Industry"),
        ("ex:TechnologyIndustry", "TechnologyIndustry", "ex:Industry"),
        ("ex:FinancialIndustry", "FinancialIndustry", "ex:Industry"),
        ("ex:EnergyIndustry", "EnergyIndustry", "ex:Industry"),

        // Market
        ("ex:FinancialMarket", "FinancialMarket", "ex:Market"),
        ("ex:CommodityMarket", "CommodityMarket", "ex:Market"),

        // Metric
        ("ex:FinancialMetric", "FinancialMetric", "ex:Metric"),
        ("ex:PerformanceMetric", "PerformanceMetric", "ex:Metric"),
        ("ex:StatisticalMetric", "StatisticalMetric", "ex:Metric"),
        ("ex:Rating", "Rating", "ex:Metric"),

        // Method
        ("ex:BusinessStrategy", "BusinessStrategy", "ex:Method"),
        ("ex:Algorithm", "Algorithm", "ex:Method"),
        ("ex:Framework", "Framework", "ex:Method"),
        ("ex:Process", "Process", "ex:Method"),

        // TransportationMode
        ("ex:RailTransport", "RailTransport", "ex:TransportationMode"),
        ("ex:AirTransport", "AirTransport", "ex:TransportationMode"),
        ("ex:MaritimeTransport", "MaritimeTransport", "ex:TransportationMode"),
        ("ex:RoadTransport", "RoadTransport", "ex:TransportationMode"),
        ("ex:PublicTransit", "PublicTransit", "ex:TransportationMode"),

        // Organism
        ("ex:Animal", "Animal", "ex:Organism"),
        ("ex:Plant", "Plant", "ex:Organism"),
        ("ex:Microorganism", "Microorganism", "ex:Organism"),
        // Animal
        ("ex:Human", "Human", "ex:Animal"),
        // Microorganism
        ("ex:Virus", "Virus", "ex:Microorganism"),
        ("ex:Bacteria", "Bacteria", "ex:Microorganism"),

        // Facility (direct)
        ("ex:Museum", "Museum", "ex:Facility"),
        ("ex:Stadium", "Stadium", "ex:Facility"),
        ("ex:Hotel", "Hotel", "ex:Facility"),
        ("ex:ArchaeologicalSite", "ArchaeologicalSite", "ex:Facility"),

        // Disease
        ("ex:InfectiousDisease", "InfectiousDisease", "ex:Disease"),
        ("ex:ChronicDisease", "ChronicDisease", "ex:Disease"),
        ("ex:MentalDisorder", "MentalDisorder", "ex:Disease"),
        ("ex:Cancer", "Cancer", "ex:Disease"),

        // Ideology
        ("ex:PoliticalIdeology", "PoliticalIdeology", "ex:Ideology"),
        ("ex:EconomicTheory", "EconomicTheory", "ex:Ideology"),
        ("ex:Philosophy", "Philosophy", "ex:Ideology"),
        ("ex:Religion", "Religion", "ex:Ideology"),

        // Language
        ("ex:NaturalLanguage", "NaturalLanguage", "ex:Language"),
        ("ex:ProgrammingLanguage", "ProgrammingLanguage", "ex:Language"),

        // Food
        ("ex:Dish", "Dish", "ex:Food"),
        ("ex:Ingredient", "Ingredient", "ex:Food"),
        ("ex:Beverage", "Beverage", "ex:Food"),

        // Sport
        ("ex:TeamSport", "TeamSport", "ex:Sport"),
        ("ex:IndividualSport", "IndividualSport", "ex:Sport"),
        ("ex:CombatSport", "CombatSport", "ex:Sport"),

        // NaturalResource
        ("ex:Mineral", "Mineral", "ex:NaturalResource"),
        ("ex:FossilFuel", "FossilFuel", "ex:NaturalResource"),
        ("ex:RenewableResource", "RenewableResource", "ex:NaturalResource"),
    ]

    /// 上位オントロジーの全 IRI セット（トップレベル + サブクラス）
    public static var allPrimitiveIRIs: Set<String> {
        Set(primitiveClasses.map(\.iri) + seedSubClasses.map(\.iri))
    }

    /// シードプロパティの IRI セット（merge で消してはいけない）
    public static let seedPropertyIRIs: Set<String> = [
        // Universal ObjectProperties
        "ex:partOf", "ex:hasPart",
        "ex:locatedIn",
        "ex:hasFounder", "ex:founderOf",
        "ex:memberOf", "ex:hasMember",
        "ex:produces", "ex:producedBy",
        // Event ObjectProperties
        "ex:hasParticipant", "ex:participatesIn",
        "ex:causes", "ex:causedBy",
        // Event DataProperties
        "ex:occurredOnDate", "ex:occurredAtTime",
        "ex:startDate", "ex:endDate",
        // External Reference DataProperties
        "ex:wikipediaURL", "ex:officialURL", "ex:imageURL",
    ]

    /// オントロジーに上位オントロジーのクラスが存在しなければシードする
    public static func seedPrimitiveClasses(
        context: FDBContext,
        graphName: String
    ) async throws {
        let ontologyIRI = MemoryContext.ontologyIRI(for: graphName)
        var ontology = try await context.ontology.get(iri: ontologyIRI)
            ?? OWLOntology(iri: ontologyIRI)

        let existingIRIs = Set(ontology.classes.map(\.iri))
        var added = 0

        for (iri, label) in primitiveClasses {
            if !existingIRIs.contains(iri) {
                ontology.classes.append(OWLClass(iri: iri, label: label))
                added += 1
            }
            // プリミティブクラスは owl:Thing を親に持つ
            let axiom = OWLAxiom.subClassOf(sub: .named(iri), sup: .named("owl:Thing"))
            if !ontology.axioms.contains(axiom) {
                ontology.axioms.append(axiom)
                added += 1
            }
        }

        for (iri, label, superClass) in seedSubClasses {
            if !existingIRIs.contains(iri) {
                ontology.classes.append(OWLClass(iri: iri, label: label))
                added += 1
            }
            let axiom = OWLAxiom.subClassOf(sub: .named(iri), sup: .named(superClass))
            if !ontology.axioms.contains(axiom) {
                ontology.axioms.append(axiom)
                added += 1
            }
        }

        if added > 0 {
            try await context.ontology.load(ontology)
        }
    }

    // MARK: - Base Ontology

    /// Schema に渡すベースオントロジーを構築する
    ///
    /// TBox（クラス階層 + 排他宣言）+ RBox（標準プロパティ）を含む。
    /// ABox（個体）は含まない（実行時に動的に追加される）。
    public static func buildBaseOntology() -> OWLOntology {
        OWLOntology(iri: MemoryContext.ontologyIRI, prefixes: ["ex": "http://example.org/"]) {

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
                iri: "ex:occurredOnDate",
                label: "occurred on date",
                domains: [.named("ex:Occurrent")],
                ranges: [.datatype(XSDDatatype.date.iri)]
            )
            OWLDataProperty(
                iri: "ex:occurredAtTime",
                label: "occurred at time",
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

    /// 上位オントロジーの HOOT 表現（LLM instructions に注入する）
    ///
    /// `buildBaseOntology()` から自動生成される。
    /// クラス階層・排他宣言・プロパティ定義・domain/range をすべて含む。
    /// HOOT compact モードにより Turtle 比で大幅にトークン数を削減。
    public static let upperOntologyText: String = buildBaseOntology().toHoot(mode: .compact)

    /// 共通方針テキスト（instructions に注入する）
    ///
    /// - Parameter existingVocabulary: DB から取得した既存カスタム語彙テキスト（空文字可）
    public static func definition(existingVocabulary: String = "") -> String {
        """
    # オントロジー設計方針

    ## Predicate Archetypes
    mereology | location | association | participation |
    causation | dependency | reference | identity | provenance | temporal

    ## 述語命名テンプレート
    - hasX / isXOf（一般）
    - partOf / hasPart（mereology）
    - locatedIn（location）
    - affiliatedWith / associatedWith（association）
    - participatesIn / hasParticipant（participation）
    - causes / causedBy / affects（causation）
    - dependsOn / requires（dependency）
    - refersTo / mentions（reference）
    - sameAs / exactMatch / closeMatch（identity）
    - derivedFrom / hasSource（provenance）
    - occurredOnDate / occurredAtTime / startDate / endDate（temporal）

    ## クラスか属性かの判断基準

    サブクラスを作る唯一の理由は、そのグループに固有のプロパティ（domain）が存在することである。
    親クラスにないプロパティを持つか？ YES → サブクラス。NO → 属性値・関係・Defined Class で表現する。

    ## クラス階層
    - 意味のある抽象度でクラスを定義する
    - 親クラスは子クラスの共通性質を捉える
    - すべてのクラスは「利用可能なクラス一覧」のいずれかに接続する

    ## 利用可能なクラス一覧

    以下はすべて定義済み。define_ontology での再定義は不要。
    新規クラスは最も具体的な既存クラスを superClasses に指定する。
    既存クラスで rdf:type を付与できるなら新規クラスは作成しない。

    ### 上位オントロジー（シード）

    \(upperOntologyText)

    \(existingVocabulary)

    ## プロパティ設計
    - オブジェクトプロパティ: エンティティ間の関係
    - データプロパティ: 属性値
    - domain/range はシステムが管理する。define_ontology では設定不要・設定不可

    ### オブジェクトプロパティの命名規約
    - 正方向: hasX（ex:hasFounder, ex:hasMember）
    - 逆方向: isXOf / XOf / XBy（ex:founderOf, ex:memberOf, ex:createdBy）
    - 正方向と逆方向は別プロパティとして定義し、owl:inverseOf で関連づける
    - 同じ概念に対して isXOf と XOf の両方を定義しない（どちらか一方を選ぶ）
    - 汎用的で短い名前を優先する（ex:founded > ex:foundedCompany）

    ### 逆プロパティ（owl:inverseOf）
    - 「A hasX B」⇔「B XOf A」の関係を逆プロパティと呼ぶ
    - 逆プロパティは merge してはいけない（主語と目的語が逆転する）
    - 逆関係のパターン:
      - hasX ↔ isXOf / XOf（ex:hasFounder ↔ ex:founderOf）
      - X ↔ XBy（ex:acquired ↔ ex:acquiredBy）
      - hasPart ↔ partOf（mereology の標準ペア）

    ### name 系 DataProperty の禁止
    - エンティティの名前は rdfs:label を使用する
    - companyName, personName, productName 等のドメイン固有 name プロパティは定義しない
    - rdfs:label は define_ontology での定義不要（標準プロパティ）

    ### DataProperty の命名規約
    - 汎用的で短い名前を優先する（ex:revenue > ex:revenueAmount）
    - Amount, Value, Count 等のサフィックスは冗長であれば省略する

    ## データプロパティ値の規約
    - 値は原子的（数値、日付、短いラベル、URI）
    - 文章や説明文は値にならない

    ## Defined Class（構造分類）
    - 条件を満たすインスタンスを自動分類するクラス（equivalentClass）
    - Reasoner が条件に合うインスタンスに自動で rdf:type を付与する

    ## TBox と ABox
    - TBox（用語層）: クラス、プロパティ、階層の定義
    - ABox（事実層）: 具体的なインスタンスとその属性・関係

    ## イベントモデル（Event Reification）

    出来事・事象はエンティティとして保存される。
    イベントは固有名を持つ個体であり、中間ノードではない。

    ### 基底クラス
    - ex:Event — すべてのイベントの基底クラス。具体的なイベント型はサブクラスとして定義される
    - ex:Era — 名前付きの時代・時期（例: 飛鳥時代、ルネサンス）。出来事ではなく時間的枠組み。startDate / endDate で期間を表す

    ### rdf:type は最も具体的なクラスを使用
    - 上位オントロジーの階層を参照し、最も具体的なサブクラスを rdf:type に指定する
    - 戦闘 → ex:Battle（ex:Event ではない）
    - 買収 → ex:Acquisition（ex:Agreement ではない）
    - 人事 → ex:Appointment（ex:Transition ではない）
    - 展示 → ex:Exhibition（ex:Gathering ではない）
    - 地震 → ex:Earthquake（ex:NaturalDisaster ではない）
    - 誕生 → ex:Birth、死亡 → ex:Death
    - 時代 → ex:Era（ex:Event ではない）
    - 推論が superClass を自動付与するため、親クラスの rdf:type は不要
    - 1つのエンティティに付与する rdf:type は1つ（最も具体的なもの）

    ### イベントのサブタイプ
    上位オントロジーの Event 配下を参照。
    新規イベントクラスは最も近いサブタイプの子として定義する。

    ### イベントの時間述語（DataProperty）
    - ex:occurredOnDate — 日付（domain: ex:Event, range: ISO 8601 精度別 xsd:gYear YYYY / xsd:gYearMonth YYYY-MM / xsd:date YYYY-MM-DD）
    - ex:occurredAtTime — 時刻（domain: ex:Event, range: xsd:time HH:MM:SS）。明示されている場合のみ
    - ex:startDate — 期間の開始日（domain: ex:Event, range: 同上）
    - ex:endDate — 期間の終了日（domain: ex:Event, range: 同上）

    ### イベントの関係述語（ObjectProperty）
    - ex:hasParticipant — 参加エンティティ（domain: ex:Event, archetype: participation）
    - ex:causes — イベント間の因果（domain: ex:Event, range: ex:Event, archetype: causation）

    ### 汎用関係述語（ObjectProperty）
    以下はシード済み。define_ontology での再定義は不要。
    - ex:partOf / ex:hasPart — 部分-全体の階層（transitive, archetype: mereology）。組織階層、構成要素等に使用
    - ex:locatedIn — 所在地（transitive, range: ex:Place, archetype: location）。本社、拠点、開催地等に使用。headquarteredIn 等の特殊化は原則不要
    - ex:hasFounder / ex:founderOf — 創設者（archetype: association）。Organization, Project 等に使用
    - ex:hasMember / ex:memberOf — 所属・会員（archetype: association）。Person→Organization, Organization→Organization に使用
    - ex:produces / ex:producedBy — 生産・製造（archetype: association）。develops, manufactures, offers 等の特殊化は原則不要

    ### 直接関係の併記
    イベントに加えて、参加者間の直接関係も存在する。
    検索時はイベント経由でも直接関係経由でも到達できる。

    ## 外部参照（DataProperty）

    エンティティに関連する外部リソースの URL を DataProperty で記録する。

    ### 標準プロパティ
    - ex:wikipediaURL — Wikipedia ページの URL（domain: owl:Thing, range: xsd:anyURI）
    - ex:officialURL — 公式サイトの URL（domain: owl:Thing, range: xsd:anyURI）
    - ex:imageURL — 画像の URL（domain: owl:Thing, range: xsd:anyURI）

    ### 規約
    - URL はそのまま目的語に格納する（短縮・加工しない）
    - 1つのエンティティに同種の URL は複数付与可
    - テキストに URL が存在しない場合は作成しない（推測禁止）
    - これらは標準 DataProperty であり、define_ontology での再定義は不要

    ## IRI 命名
    - プレフィックス付き短縮形（ex:Company, ex:name）
    - クラス: UpperCamelCase（ex:Person）
    - プロパティ: lowerCamelCase（ex:hasAuthor）
    - エンティティ: ASCII 識別子を使用
    - 日本語名や非 ASCII 文字は IRI に使用しない

    ## rdfs:label（必須）

    すべてのエンティティに rdfs:label を付与する。
    rdfs:label にはテキスト中の**原語表記**をそのまま使用する。

    ### 規約
    - rdfs:label は標準プロパティであり、define_ontology での定義は不要
    - 人物名・組織名・製品名など、テキスト中の表記をそのまま保存する
    - 検索時に日本語名で引けるようにするための必須プロパティ

    ## カテゴリの排他性

    ある個体が同時に属し得ないクラスの組がある。
    排他宣言は Reasoner による誤分類の検出に使われる。

    ### 排他的なカテゴリ
    - Person と Organization（人は組織ではない）
    - Person と Place（人は場所ではない）
    - Occurrent と Person / Organization / Place（時間的存在は実体ではない）
    - Event と Era（出来事は時代ではない）
    - Product と Service（製品はサービスではない）
    - Organism と Organization（生物は組織ではない）

    ### 排他でないカテゴリ
    - Facility と Organization（「東京大学」は施設でもあり組織でもある）
    - Technology と Product（ソフトウェアは技術でもあり製品でもある）
    - Activity と Event（活動が出来事として記録される場合がある）

    ### 判断基準
    - 同一の個体が両方に属する現実的なシナリオがあるなら排他宣言しない
    - 迷う場合は宣言しない（誤った排他は推論を壊す）

    ## 関係の性質

    ObjectProperty を定義するとき、その関係が持つ性質を宣言する。
    性質は Reasoner が暗黙のトリプルを推論するために使う。

    ### 推移性（transitive）
    A→B かつ B→C ならば A→C。包含・階層の関係に適用する。
    - locatedIn: 渋谷にある建物は東京にもあり、日本にもある
    - partOf: ピストンがエンジンの一部で、エンジンが車の一部なら、ピストンは車の一部
    - subOrganizationOf: 部署→事業部→本社

    推移性を宣言してはいけないもの:
    - hasFounder, hasParent — 直接的な関係のみ意味がある

    ### 対称性（symmetric）
    A→B ならば B→A。対等な関係に適用する。
    - allianceWith, competitorOf, siblingOf, adjacentTo

    ### 一意性（functional）
    ある主語に対して目的語が最大1つ。
    - hasBirthPlace, hasHeadquarters, hasCapital

    一意性を宣言してはいけないもの:
    - hasMember, hasProduct — 複数値を取り得る

    ### 逆一意性（inverseFunctional）
    ある目的語に対して主語が最大1つ。識別子的な関係に適用する。
    - hasIBAN — 同じ IBAN を持つ口座は1つ
    - hasStockTicker — 同じ証券コードを持つ企業は1つ

    ### 非対称性（asymmetric）
    A→B のとき B→A は成り立たない。方向性が固定の関係に適用する。
    - parentOf, supervises, partOf

    ### 判断基準
    - 「例外なく常に成り立つか？」で判断する。1つでも例外があるなら宣言しない
    - 推移性は推論の連鎖を生むため最も慎重に判断する
    - 一意性を宣言すると、2つ以上の値がある場合に矛盾として検出される

    ## 時間精度の保存

    日付・時間の情報はソーステキストの精度をそのまま保存する。
    精度を推測して補完してはならない。
    - 「2024年」→ xsd:gYear（「2024-01-01」にしない）
    - 「2024年3月」→ xsd:gYearMonth
    - 「2024年3月15日」→ xsd:date
    """
    }
}
