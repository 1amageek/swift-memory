// GivenBuilder.swift
// Result builder for composing GivenContent

import Foundation

/// Result builder for composing GivenContent from GivenRepresentable components.
///
/// ```swift
/// let content = GivenContent {
///     "Alice works at Acme Corp"
///     GivenContent.Image(source: .url(imageURL))
/// }
/// ```
@resultBuilder
public struct GivenBuilder {

    public static func buildArray(_ givens: [some GivenRepresentable]) -> GivenContent {
        let components = givens.flatMap { $0.givenRepresentation.components }
        return GivenContent(components: components)
    }

    public static func buildBlock<each G>(_ components: repeat each G) -> GivenContent where repeat each G: GivenRepresentable {
        var allComponents: [GivenContent.Component] = []
        repeat allComponents.append(contentsOf: (each components).givenRepresentation.components)
        return GivenContent(components: allComponents)
    }

    public static func buildEither(first component: some GivenRepresentable) -> GivenContent {
        component.givenRepresentation
    }

    public static func buildEither(second component: some GivenRepresentable) -> GivenContent {
        component.givenRepresentation
    }

    public static func buildExpression<G: GivenRepresentable>(_ expression: G) -> G {
        expression
    }

    public static func buildExpression(_ expression: GivenContent) -> GivenContent {
        expression
    }

    public static func buildLimitedAvailability(_ given: some GivenRepresentable) -> GivenContent {
        given.givenRepresentation
    }

    public static func buildOptional(_ component: GivenContent?) -> GivenContent {
        component ?? GivenContent(components: [])
    }
}
