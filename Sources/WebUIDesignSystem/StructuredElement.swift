import WebUI

// MARK: - ClassTokens

/// the class attribute's tokens: emission order, no duplicates.
///
/// one non-generic value type, so every styled element shares a single merger in
/// the binary. an element never re-implements the dedupe.
public struct ClassTokens: Sendable {
    private var tokens: [String] = []

    public init() {}

    /// seed with an element's base classes. an empty `ClassName` contributes
    /// nothing, which is how a component with no base class is expressed.
    public init(_ base: ClassName) {
        add(base)
    }

    public mutating func add(_ name: ClassName?) {
        guard let name else {
            return
        }
        for token in name.value.split(separator: " ") {
            add(token: String(token))
        }
    }

    public mutating func add(token: String) {
        guard !token.isEmpty, !tokens.contains(token) else {
            return
        }
        tokens.append(token)
    }

    public var isEmpty: Bool { tokens.isEmpty }
    public var joined: String { tokens.joined(separator: " ") }
}

// MARK: - AttributeTokens

/// the element's non-class attributes, in contribution order.
///
/// the twin of ``ClassTokens``: one non-generic value type, so every styled
/// element shares a single formatter, and an element never concatenates
/// attribute text by hand. values are escaped here, at the only door, so a
/// contributed value cannot reach the wire unescaped.
public struct AttributeTokens: Sendable {
    private var rendered: [String] = []

    public init() {}

    /// `name="value"`.
    public mutating func add(_ name: String, _ value: String) {
        rendered.append("\(htmlEscape(name))=\"\(htmlEscape(value))\"")
    }

    /// `name="value"`, omitted entirely when nil.
    public mutating func add(_ name: String, _ value: String?) {
        guard let value else {
            return
        }
        add(name, value)
    }

    /// `name=""` when true, omitted when false — the boolean spelling.
    public mutating func add(flag name: String, _ on: Bool) {
        guard on else {
            return
        }
        rendered.append("\(htmlEscape(name))=\"\"")
    }

    /// `data-<name>="value"`.
    public mutating func add(data name: String, _ value: String?) {
        add("data-\(name)", value)
    }

    /// `aria-<name>="value"`.
    public mutating func add(aria name: String, _ value: String?) {
        add("aria-\(name)", value)
    }

    public var isEmpty: Bool { rendered.isEmpty }
    /// the attribute text, in contribution order.
    public var entries: [String] { rendered }
}

// MARK: - StyledElement

/// a component that renders one root element.
///
/// the renderer lives here, once. a conforming type states its tag, its base
/// classes, and how its axes contribute — and inherits the framing, the class
/// merge, and the attribute order. no element rendering is written per
/// component, so 97 components cost 97 declarations and one renderer.
///
/// the three data requirements have defaults: a component with no children, no
/// id, no extra classes and no axes writes only `tag`, `base` and `content`.
public protocol StyledElement: View {
    associatedtype Content: View

    /// the root element to emit.
    static var tag: Tag { get }

    /// the classes every instance carries. `ClassName("")` means none.
    static var base: ClassName { get }

    /// the element's children.
    var content: Content { get }

    /// the element's `id` attribute.
    var id: String? { get }

    /// classes a call site adds on top of the base.
    var extra: ClassName? { get }

    /// add this element's variant tokens, in declaration order.
    func contribute(to tokens: inout ClassTokens)

    /// add this element's non-class attributes, in emission order.
    func contributeAttributes(to attributes: inout AttributeTokens)
}

extension StyledElement {
    public var id: String? { nil }
    public var extra: ClassName? { nil }
    public func contribute(to tokens: inout ClassTokens) {}
    public func contributeAttributes(to attributes: inout AttributeTokens) {}

    public func render(into buffer: inout HTMLBuffer) {
        var tokens = ClassTokens(Self.base)
        contribute(to: &tokens)
        tokens.add(extra)

        var attributes = AttributeTokens()
        contributeAttributes(to: &attributes)

        // the buffer prepends every contribution, so the calls run in reverse
        // and the emitted order is: id, class, then the contributed attributes.
        buffer.beginElement(Self.tag.rawValue)
        for entry in attributes.entries.reversed() {
            buffer.addAttribute(entry)
        }
        if !tokens.isEmpty {
            buffer.addAttributeValue("class", tokens.joined)
        }
        if let id {
            buffer.addAttributeValue("id", id)
        }
        buffer.endOpenTag()
        content.render(into: &buffer)
        buffer.endElement()
    }
}

// MARK: - ClassAxis

/// a class that belongs to exactly one component.
///
/// the distinction that makes this worth a protocol: `CSSClass` says a token is
/// *real*. `ClassAxis` says a token is *valid here* — a component scopes the
/// conformance to a nested enum, so `SetRow(stack: .danger)` does not compile
/// while `SetRow(stack: .large)` does. a generic class argument can only ever
/// express the first of those; this expresses the second.
///
/// named `ClassAxis` rather than `Variant` or `Axis` because the design-system
/// core already owns both (`Variant` is the deprecated spelling of `Tone`).
///
/// an axis whose token is empty contributes no class at all, which is how a
/// `.normal` / `.default` case means "the base element, unchanged".
public protocol ClassAxis: CSSClass {}

// MARK: - @Axis

/// marks one stored property as a class axis.
///
/// ```swift
/// @StyledElement(.div, class: .setRow)
/// struct SetRow<Content: View> {
///     enum Stack: String, ClassAxis { case regular = "set-row-stack" }
///     @Axis var stack: Stack? = nil          // a class axis
///     let rows: [Row]                        // payload, required at init
/// }
/// ```
///
/// unmarked stored properties are payload: kept as stored data and required by
/// the generated initializer. marked ones additionally contribute their token
/// through `contribute(to:)`.
@attached(peer, names: arbitrary)
public macro Axis() = #externalMacro(module: "WebUIDesignSystemMacros", type: "AxisMacro")

// MARK: - @StyledElement

/// one line at the type: the element's tag and its base classes are stated
/// here, and every call site names only the component.
///
/// the attribute derives the stored content, both initializers, and
/// `render(into:)`. the base classes merge with a call site's `class:` extra
/// classes, in order, duplicates dropped.
///
/// ```swift
/// @StyledElement(.div, class: .detailSub)
/// public struct DetailSub<Content: View>: View { }
///
/// DetailSub { Text("Add or remove the model configurations…") }
/// DetailSub(id: "hint", class: .cardSub) { … }
/// ```
///
/// the host declares exactly one generic `: View` parameter — a member macro
/// cannot widen the host's generic parameter list.
///
/// - Parameters:
///   - tag: the element to emit, e.g. `.div`, `.span`, `.h1`.
///   - class: the base classes; written once, here, and never at a call site.
@attached(extension, conformances: StyledElement)
@attached(member, names: arbitrary)
public macro StyledElement(_ tag: Tag, class: ClassName? = nil) =
    #externalMacro(module: "WebUIDesignSystemMacros", type: "StyledElementMacro")
