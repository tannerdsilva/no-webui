import WebUI
import WebUIDesignSystem

// the probe: five components carrying real variant axes, each taken from a real
// multi-class site in `arc-agent/Sources/ArcWebUI/Views.swift`. every component
// is declared once; every pair is rendered and compared byte for byte.

// MARK: - the vocabulary (arc generates this from the shipped sheet)

public enum ArcClass: String, CaseIterable, Sendable, CSSClass {
    case setRow = "set-row"
    case plBadge = "pl-badge"
    case msg = "msg"
    case dot = "dot"
    case detailCard = "detail-card"
    case detailTitle = "detail-title"
    case detailSub = "detail-sub"
    case mcRow = "mc-row"
}

extension ClassName {
    public static var setRow: ClassName { .init(ArcClass.setRow) }
    public static var plBadge: ClassName { .init(ArcClass.plBadge) }
    public static var msg: ClassName { .init(ArcClass.msg) }
    public static var dot: ClassName { .init(ArcClass.dot) }
    public static var detailCard: ClassName { .init(ArcClass.detailCard) }
    public static var detailTitle: ClassName { .init(ArcClass.detailTitle) }
    public static var detailSub: ClassName { .init(ArcClass.detailSub) }
    public static var mcRow: ClassName { .init(ArcClass.mcRow) }
}

// MARK: - the components: base class once, axis enum scoped to the component

@StyledElement(.div, class: .setRow)
public struct SetRow<Content: View> {
    public enum Stack: String, ClassAxis {
        case regular = "set-row-stack"
        case large = "set-row-stack-lg"
        case tight = "set-row-stack-tight"
    }
    @Axis public var stack: Stack? = nil
}

@StyledElement(.span, class: .plBadge)
public struct PlBadge<Content: View> {
    public enum State: String, ClassAxis {
        case active = "badge-active"
        case inactive = "badge-inactive"
        case normal = "badge-default"
    }
    @Axis public var state: State? = nil
}

@StyledElement(.div, class: .msg)
public struct Msg<Content: View> {
    // the raw values are the class tokens verbatim, so the cases need no spelling
    public enum Role: String, ClassAxis {
        case assistant
        case user
        case streaming
    }
    @Axis public var role: Role? = nil
}

@StyledElement(.span, class: .dot)
public struct Dot<Content: View> {
    public enum Severity: String, ClassAxis {
        case info = "dot-info"
        case warn = "dot-warn"
        case err = "dot-err"
    }
    @Axis public var severity: Severity? = nil
}

@StyledElement(.div, class: .detailSub)
public struct DetailSub<Content: View> {
    public enum Placement: String, ClassAxis {
        case card = "card-sub"
    }
    @Axis public var placement: Placement? = nil
}

// MARK: - the comparison harness

func pair(
    _ arcSource: String,
    _ before: some View,
    _ after: some View,
    _ afterSource: String
) {
    let a = before.markup.html
    let b = after.markup.html
    print("")
    print("  arc today  \(arcSource)")
    print("             \(a)")
    print("  after      \(afterSource)")
    print("             \(b)")
    print("             \(a == b ? "IDENTICAL" : "DIFFERENT  <-- regression")")
}

// MARK: - 1. the spacing axis (Views.swift:4477 and :3369)

pair(
    "Div(class: ClassName(.setRow, .setRowStackLg))",
    Div(class: "set-row set-row-stack-lg") { Text("main model") },
    SetRow(stack: .large) { Text("main model") },
    "SetRow(stack: .large)"
)

pair(
    "Div(class: ClassName(.setRow, .setRowStack))",
    Div(class: "set-row set-row-stack") { Text("pinned") },
    SetRow(stack: .regular) { Text("pinned") },
    "SetRow(stack: .regular)"
)

// the axis is optional, so "no variant" is still expressible
pair(
    "Div(class: .setRow)",
    Div(class: "set-row") { Text("plain") },
    SetRow { Text("plain") },
    "SetRow"
)

// MARK: - 2. the state axis (Views.swift:3242)

pair(
    "Span(class: ClassName(.plBadge, .badgeActive))",
    Span(class: "pl-badge badge-active") { Text("ACTIVE") },
    PlBadge(state: .active) { Text("ACTIVE") },
    "PlBadge(state: .active)"
)

// MARK: - 3. the role axis (Views.swift:1629)

pair(
    "Div(class: ClassName(.msg, .assistant))",
    Div(class: "msg assistant") { Text("hello") },
    Msg(role: .assistant) { Text("hello") },
    "Msg(role: .assistant)"
)

// MARK: - 4. the severity axis, with no children (Views.swift:5234)

pair(
    "Span(class: ClassName(.dot, .dotInfo)) {}",
    Span(class: "dot dot-info") { EmptyView() },
    Dot(severity: .info),
    "Dot(severity: .info)"
)

// MARK: - 5. the placement axis (Views.swift:4444)

pair(
    "Div(class: ClassName(.detailSub, .cardSub))",
    Div(class: "detail-sub card-sub") { Text("sub-line") },
    DetailSub(placement: .card) { Text("sub-line") },
    "DetailSub(placement: .card)"
)

// MARK: - what the scoped enum buys

// none of these compile, which is the point. a generic class argument checks
// membership in the sheet; a scoped enum checks membership in this component:
//
//     SetRow(stack: .danger)        // type 'SetRow<Content>.Stack' has no member 'danger'
//     SetRow(stack: .dotErr)        // 'dotErr' is not a Stack
//     Dot(severity: .large)         // 'large' is not a Severity
//     PlBadge(state: .streaming)    // 'streaming' is not a State
//
// whereas `Div<CatDot, AkvV>` — two unrelated tokens — compiles.

print("")
print("  axes are scoped: SetRow.Stack is regular/large/tight, Dot.Severity is")
print("  info/warn/err. no other class in the sheet can reach either component.")

// MARK: - Layer 1, on a real component: arc's ArcButton

// today: 61 lines, 23 of them assembling attribute text by hand
public struct ArcButtonV1<Views: View>: View {
    public let label: String
    public var id: String? = nil
    public var component: String? = nil
    public var className: String = ""
    public var type: String = "button"
    public var tabIndex: Int? = nil
    public var disabled = false
    public var hidden = false
    public var views: Views

    public func render(into buffer: inout HTMLBuffer) {
        var attributes = ""
        if let id { attributes += " id=\"\(htmlEscape(id))\"" }
        if let component, !component.isEmpty {
            attributes += " data-component-id=\"\(htmlEscape(component))\""
        }
        if !className.isEmpty { attributes += " class=\"\(htmlEscape(className))\"" }
        attributes += " type=\"\(type)\""
        if let tabIndex { attributes += " tabindex=\"\(tabIndex)\"" }
        if disabled { attributes += " disabled=\"\"" }
        if hidden { attributes += " hidden=\"\"" }

        buffer.beginElement("div", attributes)
        buffer.endOpenTag()
        views.render(into: &buffer)
        buffer.endElement()
    }
}

// after: no render, no attribute string — the attribute set is data
// (root is div, not button: `Tag` deliberately excludes the tags that already
// have a dedicated type — see Slice H. arc's ArcButton itself needs `Button`
// to adopt StyledElement rather than Tag growing.)
public struct ArcButtonV2<Views: View>: StyledElement {
    public var id: String? = nil
    public var component: String? = nil
    public var type: String = "button"
    public var tabIndex: Int? = nil
    public var disabled = false
    public var hidden = false
    public var extra: ClassName? = nil
    public let content: Views

    public static var tag: Tag? { .div }
    public static var base: ClassName { ClassName("primary-btn") }

    public func contributeAttributes(to attributes: inout AttributeTokens) {
        attributes.add(data: "component-id", component)
        attributes.add("type", type)
        attributes.add("tabindex", tabIndex.map(String.init))
        attributes.add(flag: "disabled", disabled)
        attributes.add(flag: "hidden", hidden)
    }
}

let v1 = ArcButtonV1(
    label: "Remove", id: "mc-del-1", component: "mc-del-1",
    className: "primary-btn", tabIndex: nil, disabled: false, hidden: true,
    views: Text("Remove")
)

let v2 = ArcButtonV2(
    id: "mc-del-1", component: "mc-del-1", type: "button",
    tabIndex: nil, disabled: false, hidden: true,
    content: Text("Remove")
)

let a = v1.markup.html
let b = v2.markup.html
print("")
print("arc today  ArcButtonV1  (23 lines of attribute assembly)")
print("           \(a)")
print("after      ArcButtonV2  (6 lines of contribution, no renderer)")
print("           \(b)")
if a == b {
    print("           IDENTICAL")
} else {
    print("           attribute ORDER differs — same set, different position:")
    print("           v1: id, data-component-id, class, type, tabindex, disabled, hidden")
    print("           v2: id, class, data-component-id, type, tabindex, disabled, hidden")
}


// MARK: - payload AND axes on one type

// `@Axis` is the discriminator: name and model are data the initializer
// requires; stack is a class axis that contributes a token.
@StyledElement(.div, class: .mcRow)
public struct ModelConfigRow<Content: View> {
    public enum Stack: String, ClassAxis {
        case regular = "set-row-stack"
        case tight = "set-row-stack-tight"
    }
    public let name: String
    public let model: String
    @Axis public var stack: Stack? = nil
}

let plainRow = ModelConfigRow(name: "deepseek-v4-flash", model: "custom") { Text("row") }
let stackedRow = ModelConfigRow(name: "deepseek-v4-flash", model: "custom", stack: .tight) { Text("row") }

print("")
print("payload + axis, no class expression at the call site:")
print("  ModelConfigRow(name:model:)          \(plainRow.markup.html)")
print("  ModelConfigRow(name:model:stack:.tight) \(stackedRow.markup.html)")


// MARK: - the class derived from the type name

// no `class:` argument: `DetailCard` IS `detail-card`. no static, no marker
// type, no name to collide with — and the class is written zero times.
@StyledElement(.div)
public struct DetailCard<Content: View> { }

// a digit in the token needs an override: `FormGrid2` would derive `form-grid2`
@StyledElement(.div, class: "form-grid-2")
public struct FormGrid2<Content: View> { }

let derived = DetailCard { Text("body") }
let overridden = FormGrid2 { Text("cells") }
print("")
print("class derived from the type name:")
print("  DetailCard            \(derived.markup.html)")
print("  FormGrid2 (override)  \(overridden.markup.html)")

// MARK: - 6. the declared child tree: DetailCard

// the component this gate replaces, written the way arc writes it today: one
// attribute string assembled by hand, two conditional part elements, the body
// appended after them, and an optional extra class welded onto the base. this
// is the reference the declaration below has to reproduce byte for byte.
enum Legacy {
    struct DetailCard<Body: View>: View {
        let title: String?
        let sub: String?
        let extraClass: String?
        let body: Body

        init(
            title: String? = nil,
            sub: String? = nil,
            extraClass: String? = nil,
            @ElementBuilder body: () -> Body
        ) {
            self.title = title
            self.sub = sub
            self.extraClass = extraClass
            self.body = body()
        }

        func render(into buffer: inout HTMLBuffer) {
            var className = "detail-card"
            if let extraClass, !extraClass.isEmpty {
                className += " " + extraClass
            }
            buffer.beginElement("div", " class=\"\(htmlEscape(className))\"")
            buffer.endOpenTag()
            // the title, when there is one
            if let title, !title.isEmpty {
                buffer.beginElement("h1", " class=\"detail-title\"")
                buffer.endOpenTag()
                buffer.appendEscaped(title)
                buffer.endElement()
            }
            // the sub-line, when there is one
            if let sub, !sub.isEmpty {
                buffer.beginElement("div", " class=\"detail-sub\"")
                buffer.endOpenTag()
                buffer.appendEscaped(sub)
                buffer.endElement()
            }
            body.render(into: &buffer)
            buffer.endElement()
        }
    }
}

// and the declaration: no renderer, no attribute string, no `if` — two parts
// and the body. `title` is a `String` with a default and `sub` is a `String?`,
// so both omission spellings (empty and nil) are exercised.
@StyledElement(.div, class: .detailCard)
public struct DetailCardDeclared<Content: View> {
    @Part(.h1, class: .detailTitle) public var title: String = ""
    @Part(.div, class: .detailSub) public var sub: String? = nil
}

pair(
    "Legacy.DetailCard(title:sub:)",
    Legacy.DetailCard(title: "Storage", sub: "where sessions live") { Text("body") },
    DetailCardDeclared(title: "Storage", sub: "where sessions live") { Text("body") },
    "DetailCardDeclared(title:sub:)"
)

pair(
    "Legacy.DetailCard(title:)",
    Legacy.DetailCard(title: "Storage") { Text("body") },
    DetailCardDeclared(title: "Storage") { Text("body") },
    "DetailCardDeclared(title:)"
)

pair(
    "Legacy.DetailCard(title: \"\", sub:)",
    Legacy.DetailCard(title: "", sub: "where sessions live") { Text("body") },
    DetailCardDeclared(sub: "where sessions live") { Text("body") },
    "DetailCardDeclared(sub:)"
)

// the omission rule: an empty part is no part — not an empty element with the
// sheet's own margins on it
pair(
    "Legacy.DetailCard(title: \"\", sub: \"\")",
    Legacy.DetailCard(title: "", sub: "") { Text("body") },
    DetailCardDeclared(title: "", sub: "") { Text("body") },
    "DetailCardDeclared(title: \"\", sub: \"\")"
)

pair(
    "Legacy.DetailCard(title:extraClass:)",
    Legacy.DetailCard(title: "Storage", extraClass: "card-lead") { Text("body") },
    DetailCardDeclared(title: "Storage", class: "card-lead") { Text("body") },
    "DetailCardDeclared(title:class:)"
)

// MARK: - 7. element-free: a component with no wrapper of its own

// `tag: nil` emits the parts and the content and frames nothing. this is what
// `Text`, `Group` and the CSS serializers need: a declaration, not a second
// protocol.
@StyledElement(nil)
public struct StyledStack<Content: View> {
    @Part(.span, class: .dot) public var marker: String? = nil
}

pair(
    "Group { Span…; content }",
    Group {
        Span(class: "dot") { Text("m") }
        Text("content")
    },
    StyledStack(marker: "m") { Text("content") },
    "StyledStack(marker:)"
)

pair(
    "Group { content }",
    Group { Text("content") },
    StyledStack { Text("content") },
    "StyledStack"
)
