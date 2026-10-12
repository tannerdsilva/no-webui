// MARK: - CascadeLayer

/// the cascade layers a document can carry, in document order.
///
/// the framework sheet ships in `webui` (component rules) and `webui.utilities`
/// (the layout primitives the asset tool prepends); a host's own
/// ``StyleSheet`` rides ``host`` by default. the cascade fixes a layer's
/// position from the *first* statement that names it — a layer introduced
/// later outranks earlier ones — so ``orderStatement`` places `host` last no
/// matter where its bytes land relative to the framework sheet.
public enum CascadeLayer: String, Sendable, CaseIterable, Equatable {
    /// the framework's own component layer.
    case webui
    /// the layout-primitive layer, a named sub-layer of ``webui``.
    case utilities = "webui.utilities"
    /// the layer a host's custom components ride. declared last, so it wins
    /// the cascade by origin — equal or lower specificity, zero `!important`.
    case host

    /// the canonical document-wide layer order, as an `@layer` statement:
    /// framework first, utilities second, host last. re-stating a name is a
    /// no-op (first mention fixes the position), so a host sheet can carry
    /// this statement safely beside the framework's own `@layer webui,
    /// webui.utilities;` — and a browser that sees only this statement still
    /// orders the layers correctly.
    public static var orderStatement: String {
        "@layer \(allCases.map(\.rawValue).joined(separator: ", "));"
    }
}

// MARK: - CSSRuleBuilder

/// the result builder behind ``StyleSheet/init(name:layer:_:)``.
///
/// accepts single ``CSSRule``s, arrays of them (`LayoutStyles.complete`), and
/// `if`/`switch`/`for` forms, flattening into the flat rule list the sheet
/// owns.
@resultBuilder
public enum CSSRuleBuilder {
    public static func buildExpression(_ expression: CSSRule) -> [CSSRule] { [expression] }
    public static func buildExpression(_ expression: [CSSRule]) -> [CSSRule] { expression }
    public static func buildBlock(_ components: [CSSRule]...) -> [CSSRule] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [CSSRule]?) -> [CSSRule] { component ?? [] }
    public static func buildEither(first component: [CSSRule]) -> [CSSRule] { component }
    public static func buildEither(second component: [CSSRule]) -> [CSSRule] { component }
    public static func buildArray(_ components: [[CSSRule]]) -> [CSSRule] { components.flatMap { $0 } }
}

// MARK: - StyleSheet

/// a host-defined chunk of css with the same guarantees as the framework's own
/// sheet: a rule the host ships in ``CascadeLayer/host`` beats the framework's
/// rules by cascade origin, without specificity games and without `!important`.
///
/// ``css`` is a complete, placement-independent artifact — the canonical layer
/// order statement followed by the rules inside `@layer <layer> { … }` — so a
/// host can inline it anywhere (the document's style slot, a file, a route)
/// and the cascade still lands the same way.
public struct StyleSheet: Sendable, Equatable {
    /// a stable label for diagnostics and debugging; not emitted into the css.
    public let name: String
    /// the cascade layer these rules ride. `.host` by default; ``webui`` /
    /// ``utilities`` for a host that deliberately augments a framework layer
    /// and accepts that layer's position in the cascade.
    public let layer: CascadeLayer
    /// the rules, in author order.
    public let rules: [CSSRule]

    public init(name: String, layer: CascadeLayer = .host, @CSSRuleBuilder _ rules: () -> [CSSRule]) {
        self.name = name
        self.layer = layer
        self.rules = rules()
    }

    /// the full layered artifact, ready to ship: the canonical order
    /// statement, then the rules inside `@layer <layer> { … }`.
    public var css: String {
        let indented = CSSStylesheet(rules).markup.html
            .split(separator: "\n")
            .map { "  " + String($0) }
            .joined(separator: "\n")
        return "\(CascadeLayer.orderStatement)\n@layer \(layer.rawValue) {\n\(indented)\n}"
    }
}
