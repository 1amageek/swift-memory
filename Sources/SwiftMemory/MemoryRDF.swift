import Database

enum MemoryRDF {
    private static let encodedTermPrefix = "memory:term/"
    private static let hexadecimal = Array("0123456789abcdef".utf8)

    static func graphName(_ value: String) throws -> RDFGraphName {
        do {
            return try RDFGraphName(iri: value)
        } catch {
            throw MemoryError.invalidRDFTerm(position: "graph", value: value)
        }
    }

    static func graphTerm(_ graph: RDFGraphName) -> RDFTerm {
        graph.term
    }

    static func graphValue(_ graph: RDFGraphName) -> String {
        switch graph.subject {
        case .iri(let iri):
            iri.rawValue
        case .blankNode(let identifier):
            "_:\(identifier.rawValue)"
        }
    }

    static func resourceTerm(_ value: String) throws -> RDFTerm {
        guard !value.isEmpty else {
            throw MemoryError.invalidRDFTerm(position: "resource", value: value)
        }
        if let iri = validatedIRI(value) {
            return .iri(iri)
        }
        return .iri(try RDFIRI(encodedTermPrefix + hexadecimalUTF8(value)))
    }

    static func predicateTerm(_ value: String) throws -> RDFTerm {
        guard let iri = validatedIRI(value) else {
            throw MemoryError.invalidRDFTerm(position: "predicate", value: value)
        }
        return .iri(iri)
    }

    static func objectTerm(_ value: String) throws -> RDFTerm {
        if let iri = validatedIRI(value) {
            return .iri(iri)
        }
        return .string(value)
    }

    static func executionResource(_ value: String) throws -> ExecutionTerm {
        .value(.rdfTerm(try resourceTerm(value)))
    }

    static func executionPredicate(_ value: String) throws -> ExecutionTerm {
        .value(.rdfTerm(try predicateTerm(value)))
    }

    static func value(_ binding: VariableBinding, variable: String) -> String? {
        guard let fieldValue = binding[variable] else { return nil }
        return value(fieldValue)
    }

    static func resourceValue(
        _ binding: VariableBinding,
        variable: String
    ) -> String? {
        guard case .rdfTerm(let term)? = binding[variable] else { return nil }
        switch term {
        case .iri, .blankNode:
            return value(term)
        case .literal, .tripleTerm:
            return nil
        }
    }

    static func value(_ fieldValue: FieldValue) -> String? {
        guard case .rdfTerm(let term) = fieldValue else {
            return fieldValue.stringValue
        }
        return value(term)
    }

    static func value(_ term: RDFTerm) -> String? {
        switch term {
        case .iri(let iri):
            return decodedTerm(iri.rawValue) ?? iri.rawValue
        case .blankNode(let identifier):
            return "_:\(identifier.rawValue)"
        case .literal(let literal):
            return literal.lexicalForm
        case .tripleTerm:
            return term.description
        }
    }

    private static func validatedIRI(_ value: String) -> RDFIRI? {
        do {
            return try RDFIRI(value)
        } catch {
            return nil
        }
    }

    private static func hexadecimalUTF8(_ value: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count * 2)
        for byte in value.utf8 {
            bytes.append(hexadecimal[Int(byte >> 4)])
            bytes.append(hexadecimal[Int(byte & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decodedTerm(_ value: String) -> String? {
        guard value.hasPrefix(encodedTermPrefix) else { return nil }
        let encoded = value.dropFirst(encodedTermPrefix.count)
        guard encoded.count.isMultiple(of: 2) else { return nil }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(encoded.count / 2)
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let next = encoded.index(after: index)
            let end = encoded.index(after: next)
            guard let high = hexadecimalValue(encoded[index]),
                  let low = hexadecimalValue(encoded[next]) else {
                return nil
            }
            decoded.append((high << 4) | low)
            index = end
        }
        let result = String(decoding: decoded, as: UTF8.self)
        guard result.utf8.elementsEqual(decoded) else { return nil }
        return result
    }

    private static func hexadecimalValue(_ character: Character) -> UInt8? {
        guard let asciiValue = character.asciiValue else { return nil }
        switch asciiValue {
        case 48...57:
            return asciiValue - 48
        case 97...102:
            return asciiValue - 97 + 10
        default:
            return nil
        }
    }
}
