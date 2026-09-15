import Foundation

// MARK: - CSSDeclaration
public struct CSSDeclaration: Sendable, Equatable {
    public let property: String
    public let value: String
    public init(_ property: String, _ value: String) {
        self.property = property
        self.value = value
    }
}

// MARK: - CSSRule
public struct CSSRule: Sendable, Equatable {
    public let selector: String
    public let declarations: [CSSDeclaration]
    public init(_ selector: String, _ declarations: [CSSDeclaration]) {
        self.selector = selector
        self.declarations = declarations
    }
}

// MARK: - CSSStylesheet
public struct CSSStylesheet: Sendable {
    public let rules: [CSSRule]
    public init(_ rules: [CSSRule]) {
        self.rules = rules
    }
    public func render() -> String {
        rules.map { rule in
            let declarations = rule.declarations.map { "  \($0.property): \($0.value);" }.joined(separator: "\n")
            return "\(rule.selector) {\n\(declarations)\n}"
        }.joined(separator: "\n\n")
    }
}

// MARK: - CSSMediaQuery
public struct CSSMediaQuery: Sendable {
    public let condition: String
    public let rules: [CSSRule]
    public init(_ condition: String, rules: [CSSRule]) {
        self.condition = condition
        self.rules = rules
    }
    public func render() -> String {
        let inner = CSSStylesheet(rules).render()
        return """
        @media (\(condition)) {
        \(inner.split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
        }
        """
    }
}

// MARK: - CSSKeyframes
public struct CSSKeyframes: Sendable {
    public let name: String
    public let keyframes: [(String, [CSSDeclaration])]
    public init(_ name: String, _ keyframes: [(String, [CSSDeclaration])]) {
        self.name = name
        self.keyframes = keyframes
    }
    public func render() -> String {
        let stops = keyframes.map { (selector, declarations) in
            let decls = declarations.map { "    \($0.property): \($0.value);" }.joined(separator: "\n")
            return "  \(selector) {\n\(decls)\n  }"
        }.joined(separator: "\n")
        return """
        @keyframes \(name) {
        \(stops)
        }
        """
    }
}

// MARK: - CSSFontFace
public struct CSSFontFace: Sendable {
    public let declarations: [CSSDeclaration]

    public init(_ declarations: [CSSDeclaration]) {
        self.declarations = declarations
    }
    public func render() -> String {
        let decls = declarations.map { "  \($0.property): \($0.value);" }.joined(separator: "\n")
        return """
        @font-face {
        \(decls)
        }
        """
    }
}

// MARK: - Layout Styles
public enum LayoutStyles {
    public static let all: [CSSRule] = [
        vstack, hstack, zstack, zstackOverlap, spacer, scrollview, grid,
    ]
    public static let vstack = CSSRule(".vstack", [
        CSSDeclaration("display", "flex"),
        CSSDeclaration("flex-direction", "column"),
    ])
    public static let hstack = CSSRule(".hstack", [
        CSSDeclaration("display", "flex"),
        CSSDeclaration("flex-direction", "row"),
    ])
    public static let zstack = CSSRule(".zstack", [
        CSSDeclaration("display", "grid"),
        CSSDeclaration("place-items", "center center"),
    ])
    // zstack children must share the single grid cell or they stack in
    // separate rows instead of overlapping. the same rule exists in
    // design-system.css for the designer preview; here it makes the core
    // self-sufficient when only LayoutStyles is shipped.
    public static let zstackOverlap = CSSRule(".zstack > *", [
        CSSDeclaration("grid-area", "1 / 1"),
    ])
    public static let spacer = CSSRule(".spacer", [
        CSSDeclaration("flex", "1"),
    ])
    public static let scrollview = CSSRule(".scrollview", [
        CSSDeclaration("overflow", "auto"),
    ])
    public static let grid = CSSRule(".grid", [
        CSSDeclaration("display", "grid"),
    ])
}

// MARK: - Spacing Classes Generator
public func generateSpacingClasses(_ values: [Int]) -> [CSSRule] {
    values.map { px in
        CSSRule(".spacing-\(px)", [
            CSSDeclaration("gap", "\(px)px"),
        ])
    }
}
public func generateAlignmentClasses(_ values: [String]) -> [CSSRule] {
    values.map { value in
        CSSRule(".align-\(value)", [
            CSSDeclaration("align-items", value),
        ])
    }
}

// MARK: - Default Layout Stylesheet

extension LayoutStyles {
    public static let complete: [CSSRule] = {
        let spacings = generateSpacingClasses([0, 2, 4, 8, 12, 16, 20, 24, 32])
        let aligns = generateAlignmentClasses(["flex-start", "center", "flex-end"])
        return all + spacings + aligns
    }()
}
