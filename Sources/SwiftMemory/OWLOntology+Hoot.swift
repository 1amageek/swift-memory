// OWLOntology+Hoot.swift
// OWLOntology → HOOT format conversion

import Database
import Hoot

extension OWLOntology {
    /// Encode OWLOntology to HOOT format.
    ///
    /// Pipeline: OWLOntology → .toTurtle() → TurtleParser → HootCompiler → HootEncoder
    public func toHoot(mode: HootEncodingMode = .compact) -> String {
        let turtle = self.toTurtle()
        let parser = TurtleParser()
        do {
            let turtleDoc = try parser.parse(turtle)
            let compiler = HootCompiler()
            let hootDoc = compiler.compile(turtleDoc)
            let encoder = HootEncoder(mode: mode)
            return encoder.encode(hootDoc)
        } catch {
            return turtle
        }
    }
}
