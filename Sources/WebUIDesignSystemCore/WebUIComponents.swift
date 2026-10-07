import Logging
import WebUICore

// MARK: - Foundation-free formatting helpers
//
// printf-equivalent number formatting that never touches Foundation, so this
// module renders identically in plain-stdlib contexts (shared with the
// server build). `String(format:)` previously backed these call sites; these
// mirror its output: fixed-point `%.Nf` (round half-to-even at the last
// printed digit, matching the FPU's default mode) and zero-padded `%0Nd`
// integers (the sign occupies one width slot, like printf).

/// `%.Nf`-style fixed-point rendering of `Double`: exactly `places` digits
/// after the decimal separator. rounds half-to-even at that position, like
/// `printf`'s `%.Nf` under the default FPU rounding mode.
func webuiFixedPoint(_ value: Double, places: Int) -> String {
    precondition(places >= 0 && places <= 6, "webuiFixedPoint: unsupported places")
    guard value.isFinite else { return String(value) }
    if value == 0 {
        let f = String(repeating: "0", count: places)
        let dot = f.isEmpty ? "" : "."
        return (value.sign == .minus ? "-" : "") + "0" + dot + f
    }
    // exact integer = round-half-even(value * 10^places).
    // value = m * 2^(e-52) exactly (m = 53-bit significand, e = exponent), so
    // value * 10^p = m * 5^p * 2^(e-52+p) = A / 2^s with A = m*5^p integer.
    // rounding A/2^s to the nearest integer (ties to even) is pure integer
    // arithmetic -- no intermediate double rounding, matching printf %.Nf.
    let fraction = value.significandBitPattern & ((1 << 52) - 1)
    let m = (1 << 52) | fraction
    var pow5: Int64 = 1
    for _ in 0..<places { pow5 *= 5 }
    let A = Int64(bitPattern: m) * pow5
    let s = 52 - value.exponent - places
    let scaled: Int64
    if s <= 0 {
        let shift = -s
        if shift >= 63 { scaled = 0 } else if shift == 0 {
            scaled = Int64(clamping: A)
        } else {
            scaled = Int64(clamping: A) &<< shift
        }
    } else if s >= 63 {
        scaled = 0
    } else {
        let half = Int64(1) << (s - 1)
        let q = Int64(A >> s)
        let r = Int64(clamping: A) & ((Int64(1) << s) - 1)
        scaled = r > half ? q + 1 : (r < half ? q : (q % 2 == 0 ? q : q + 1))
    }
    let absScaled: Int64 = scaled < 0 ? -scaled : scaled
    var f = 1
    for _ in 0..<places { f *= 10 }
    let whole = absScaled / Int64(f)
    let frac = absScaled % Int64(f)
    var fracStr = String(frac)
    if fracStr.count < places {
        fracStr = String(repeating: "0", count: places - fracStr.count) + fracStr
    }
    let neg = value.sign == .minus
    let dot = places > 0 ? "." : ""
    return (neg ? "-" : "") + String(whole) + dot + fracStr
}

/// `%0Nd`-style rendering of `Int`: zero-padded to at least `width`
/// characters.
func webuiZeroPad(_ value: Int, width: Int) -> String {
    if value < 0 {
        return "-" + webuiZeroPad(-value, width: max(width - 1, 0))
    }
    let digits = "\(value)"
    if digits.count >= width { return digits }
    return String(repeating: "0", count: width - digits.count) + digits
}

// MARK: - WebUI Button
public struct WebUIButton: View {
    public enum Variant: String, Sendable {
        case primary   = "button--primary"
        case secondary = "button--secondary"
        case outline   = "button--outline"
        case ghost     = "button--ghost"
        case danger    = "button--danger"
        case success   = "button--success"
        case warning   = "button--warning"
    }

    public enum Size: String, Sendable {
        case sm = "button--sm"
        case md = "button--md"
        case lg = "button--lg"
    }

    public let label: String
    public let variant: Variant
    public let size: Size
    public let disabled: Bool
    public let id: String?
    public let fullWidth: Bool
    public let loading: Bool
    /// self-wiring tap handler. when set, the button routes its click under
    /// the stable `id` (a render-context id is minted when `id` is nil) via
    /// `controlAttributes`, so a re-rendered region keeps routing without the
    /// `.onClick` modifier dance. nil (default) renders the static button.
    public let onTap: EventHandler?

    public init(
        _ label: String,
        variant: Variant = .primary,
        size: Size = .md,
        disabled: Bool = false,
        id: String? = nil,
        fullWidth: Bool = false,
        loading: Bool = false,
        onTap: EventHandler? = nil
    ) {
        self.label = label
        self.variant = variant
        self.size = size
        self.disabled = disabled
        self.id = id
        self.fullWidth = fullWidth
        self.loading = loading
        self.onTap = onTap
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var classes = ["button", variant.rawValue, size.rawValue]
        if fullWidth { classes.append("button--full") }
        if loading { classes.append("button--loading") }

        // self-wiring: an onTap handler routes the tap under the stable id
        // (minting one from the render context when the caller left id nil),
        // so a re-rendered region keeps routing without the .onClick dance.
        var wireAttrs = ""
        if onTap != nil {
            let wireID: String
            if let id {
                wireID = id
            } else if var ctx = RenderContext.current {
                wireID = ctx.nextComponentID().value
            } else {
                wireID = ""
            }
            if !wireID.isEmpty {
                wireAttrs = controlAttributes(id: wireID, event: .click, handler: onTap)
            }
        }

        let attributeText = [
            id.map { Tag.escAttr("id", $0) } ?? "",
            wireAttrs,
            Tag.classes(classes),
            disabled ? Tag.flag("disabled") : "",
            loading ? Tag.attr("aria-busy", "true") : "",
        ].joined()
        buffer.beginElement("button", attributeText)
        buffer.endOpenTag()
        if loading {
            buffer.append(Tag.element("span", [Tag.classes(["button__spinner"])], ""))
        }
        buffer.append(Tag.element("span", [Tag.classes(["button__label"])], htmlEscape(label)))
        buffer.endElement()
    }
}

// MARK: - WebUI Text Input
public struct WebUIInput: View {
    public enum State: String, Sendable {
        case normal = ""
        case error  = "input--error"
        case success = "input--success"
        case warning = "input--warning"
    }

    public let placeholder: String
    public let state: State
    public let disabled: Bool
    public let id: String?
    public let type: InputType
    public let label: String?
    public let helpText: String?

    public init(
        placeholder: String = "",
        state: State = .normal,
        disabled: Bool = false,
        id: String? = nil,
        type: InputType = .text,
        label: String? = nil,
        helpText: String? = nil
    ) {
        self.placeholder = placeholder
        self.state = state
        self.disabled = disabled
        self.id = id
        self.type = type
        self.label = label
        self.helpText = helpText
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {

        if let label {
            // the `for` value is emitted raw, matching the legacy spelling
            buffer.append(Tag.begin("label", Tag.classes(["input__label"]), id.map { Tag.attr("for", $0) } ?? ""))
            buffer.append(htmlEscape(label))
            buffer.append(Tag.end("label"))
        }

        buffer.append(Tag.begin("div", Tag.classes(["input-wrapper"])))
        buffer.append(Tag.void(
            "input",
            id.map { Tag.escAttr("id", $0) } ?? "",
            Tag.attr("type", type.rawValue),
            // the normal state's empty rawValue keeps its trailing space —
            // byte-pinned by the base capture
            Tag.classes(["input", state.rawValue.isEmpty ? " " : state.rawValue]),
            Tag.escAttr("placeholder", placeholder),
            disabled ? Tag.flag("disabled") : ""))
        buffer.append(Tag.end("div"))

        if let helpText {
            let helpClass = state == .error ? "input__help input__help--error" : "input__help"
            buffer.append(Tag.element("span", [Tag.classes([helpClass])], htmlEscape(helpText)))
        }

    }
}

// MARK: - WebUI Card
/// the card surface plus the anatomy the sheet styles above the body:
/// an optional media block (with a badge), a header (eyebrow / title / trailing
/// glyph), the body itself, a footer meta line, and a full-bleed action bar.
/// every anatomy slot defaults to absent, so a bare `WebUICard { … }` renders
/// exactly the markup it always has.
public struct WebUICard: View {
    public enum Variant: String, Sendable {
        case elevated = "card--elevated"
        case outlined = "card--outlined"
        case flat     = "card--flat"
        case interactive = "card--interactive"
        /// media beside the body (`.card--horizontal`). the sheet's horizontal
        /// model is media + body only, so a header here becomes its own middle
        /// column — prefer media plus body content for this variant.
        case horizontal  = "card--horizontal"
        /// hover-lift without the pointer affordance (`.card--hover`).
        case hover       = "card--hover"
        /// tighter body padding (`.card--compact`).
        case compact     = "card--compact"
        /// inert treatment (`.card--disabled`).
        case disabled    = "card--disabled"
    }

    public let variant: Variant
    public let id: String?
    public let children: [any View]
    /// small caps label above the title.
    public let eyebrow: String?
    public let title: String?
    /// muted line under the title.
    public let description: String?
    /// glyph in the header's trailing slot.
    public let headerIcon: IconName?
    /// leading media block. a glyph placeholder, so the component never has to
    /// sanitize caller-supplied geometry.
    public let media: IconName?
    /// badge text over the media block.
    public let mediaBadge: String?
    /// muted copy above the body's own content.
    public let text: String?
    /// footer's meta line.
    public let footerMeta: String?
    /// full-bleed action bar under the body.
    public let actions: [any View]

    public init(
        variant: Variant = .elevated,
        id: String? = nil,
        eyebrow: String? = nil,
        title: String? = nil,
        description: String? = nil,
        headerIcon: IconName? = nil,
        media: IconName? = nil,
        mediaBadge: String? = nil,
        text: String? = nil,
        footerMeta: String? = nil,
        @ViewBuilder actions: () -> [any View] = { [] },
        @ViewBuilder content: () -> [any View]
    ) {
        self.variant = variant
        self.id = id
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.headerIcon = headerIcon
        self.media = media
        self.mediaBadge = mediaBadge
        self.text = text
        self.footerMeta = footerMeta
        self.actions = actions()
        self.children = content()
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attributeText = Tag.classes(["card", variant.rawValue]) + (id.map { Tag.escAttr("id", $0) } ?? "")
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        if let media {
            buffer.append(Tag.begin("div", Tag.classes(["card__media"])))
            if let mediaBadge { buffer.append(Tag.element("span", [Tag.classes(["card__media-badge"])], htmlEscape(mediaBadge))) }
            buffer.append(WebUIIcon(media, size: .extraLarge).render())
            buffer.append(Tag.end("div"))
        }
        if eyebrow != nil || title != nil || headerIcon != nil {
            buffer.append(Tag.begin("div", Tag.classes(["card__header"])))
            buffer.append(Tag.begin("div"))
            if let eyebrow { buffer.append(Tag.element("span", [Tag.classes(["card__eyebrow"])], htmlEscape(eyebrow))) }
            if let title { buffer.append(Tag.element("div", [Tag.classes(["card__title"])], htmlEscape(title))) }
            buffer.append(Tag.end("div"))
            if let headerIcon {
                buffer.append(Tag.element("span", [Tag.classes(["card__icon"])], WebUIIcon(headerIcon, size: .medium).render()))
            }
            buffer.append(Tag.end("div"))
        }
        // the padded interior: the design-system `.card__body` rule carries
        // the `--space-4` default, so a consumer can override the padding
        // through the normal cascade (modifier or page-scoped style)
        // without touching this component.
        buffer.append(Tag.begin("div", Tag.classes(["card__body"])))
        if let description { buffer.append(Tag.element("div", [Tag.classes(["card__desc"])], htmlEscape(description))) }
        if let text { buffer.append(Tag.element("div", [Tag.classes(["card__text"])], htmlEscape(text))) }
        for child in children {
            child.render(into: &buffer)
        }
        if let footerMeta {
            buffer.append(Tag.begin("div", Tag.classes(["card__footer"])))
            buffer.append(Tag.element("span", [Tag.classes(["card__meta"])], htmlEscape(footerMeta)))
            buffer.append(Tag.end("div"))
        }
        buffer.append(Tag.end("div"))
        if !actions.isEmpty {
            buffer.append(Tag.begin("div", Tag.classes(["card__actions"])))
            for action in actions { action.render(into: &buffer) }
            buffer.append(Tag.end("div"))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Badge
public struct WebUIBadge: View {
    public enum Variant: String, Sendable {
        case primary   = "badge--primary"
        case secondary = "badge--secondary"
        case success   = "badge--success"
        case warning   = "badge--warning"
        case danger    = "badge--danger"
        case info      = "badge--info"
        case neutral   = "badge--neutral"
    }

    public enum Size: String, Sendable {
        case sm = "badge--sm"
        case md = "badge--md"
        case lg = "badge--lg"
    }

    public let text: String
    public let variant: Variant
    public let size: Size
    public let dot: Bool

    public init(
        _ text: String,
        variant: Variant = .neutral,
        size: Size = .md,
        dot: Bool = false
    ) {
        self.text = text
        self.variant = variant
        self.size = size
        self.dot = dot
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var classes = ["badge", variant.rawValue, size.rawValue]
        if dot { classes.append("badge--dot") }

        let attributeText = Tag.classes(classes)
        buffer.beginElement("span", attributeText)
        buffer.endOpenTag()
        if dot {
            buffer.append(Tag.element("span", [Tag.classes(["badge__dot"])], ""))
            buffer.append(" ")
        }
        buffer.append(htmlEscape(text))
        buffer.endElement()
    }
}

// MARK: - WebUI Alert
public struct WebUIAlert: View, Dismissible {
    public enum Variant: String, Sendable {
        case info    = "alert--info"
        case success = "alert--success"
        case warning = "alert--warning"
        case danger  = "alert--danger"
    }

    /// Semantic default glyph for a variant (used when `icon` is not set).
    private static func defaultIcon(for variant: Variant) -> IconName {
        switch variant {
        case .info:    return .info
        case .success: return .checkCircle
        case .warning: return .alertTriangle
        case .danger:  return .xCircle
        }
    }

    public let variant: Variant
    public let title: String?
    public let message: String
    public let dismissible: Bool
    /// Stable element id for the alert root. When set, the `ElementRef`
    /// handed to `.onDismiss` references it, so re-rendered fragments keep
    /// routing to the same handler.
    public let id: String?
    /// Icon to render. `nil` (the default) renders the variant's semantic
    /// glyph (info → `.info`, success → `.checkCircle`, warning →
    /// `.alertTriangle`, danger → `.xCircle`); pass a specific `IconName` to
    /// override.
    public let icon: IconName
    /// handler wired onto the close button; `nil` renders the static
    /// `data-dismiss` marker only.
    public var onDismiss: DismissHandler?

    public init(
        variant: Variant = .info,
        title: String? = nil,
        message: String,
        dismissible: Bool = false,
        icon: IconName? = nil,
        id: String? = nil
    ) {
        self.variant = variant
        self.title = title
        self.message = message
        self.dismissible = dismissible
        self.icon = icon ?? Self.defaultIcon(for: variant)
        self.id = id
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "alert__close" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: "Dismiss")
        var attributeText = Tag.classes(["alert", variant.rawValue]) + Tag.attr("role", "alert")
        if let elementID = dismissal.elementID ?? id {
            attributeText += Tag.escAttr("id", elementID)
        }
        if dismissible || onDismiss != nil { attributeText += Tag.flag("data-dismissible") }
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.element("div", [Tag.classes(["alert__icon fill-slot"])], WebUIIcon(icon, size: .slot).render()))
        buffer.append(Tag.begin("div", Tag.classes(["alert__body"])))
        if let title {
            buffer.append(Tag.element("div", [Tag.classes(["alert__title"])], htmlEscape(title)))
        }
        buffer.append(Tag.element("div", [Tag.classes(["alert__message"])], htmlEscape(message)))
        buffer.append(Tag.end("div"))
        if dismissible || onDismiss != nil {
            buffer.append(dismissal.buttonHTML)
        }
        buffer.endElement()
    }
}

// MARK: - Tab Item
public struct TabItem: Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

// MARK: - WebUI Tabs
public struct WebUITabs: View {
    public let tabs: [TabItem]
    public let activeTab: String
    public let id: String?
    /// tab-switch handler. receives `(me, tabID)` — `me` is the tablist root
    /// ref (the stable `id`), `tabID` the clicked tab's id. `nil` (default)
    /// renders the tabs statically with no routing attributes.
    public var onSelect: (@Sendable (ElementRef, String) async -> [FragmentUpdate])?

    public init(
        tabs: [TabItem],
        activeTab: String,
        id: String? = nil,
        onSelect: (@Sendable (ElementRef, String) async -> [FragmentUpdate])? = nil
    ) {
        self.tabs = tabs
        self.activeTab = activeTab
        self.id = id
        self.onSelect = onSelect
    }

    public func render() -> String {
        let base = id
        let wired = onSelect != nil && base != nil
        let me = base.map { ElementRef.stable($0) } ?? ElementRef.stable("webui-tabs")
        var html = Tag.begin("nav", Tag.classes(["tabs"]), id.map { Tag.escAttr("id", $0) } ?? "", Tag.attr("role", "tablist"))
        for tab in tabs {
            let active = tab.id == activeTab ? " tabs__tab--active" : ""
            var route = ""
            if wired, let onSelect, let base {
                let handler = onSelect
                let tabID = tab.id
                route = controlAttributes(id: "\(base)-\(tabID)", handler: { _ in await handler(me, tabID) })
            }
            let idAttr = base.map { Tag.attr("id", "\(htmlEscape($0))-\(htmlEscape(tab.id))") } ?? ""
            html += Tag.element("button",
                [Tag.classes(["tabs__tab", active]),
                 Tag.attr("role", "tab"),
                 Tag.attr("aria-selected", tab.id == activeTab ? "true" : "false"),
                 Tag.escAttr("data-tab", tab.id),
                 idAttr, route],
                htmlEscape(tab.label))
        }
        html += Tag.end("nav")
        return html
    }
}

public extension WebUITabs {
    /// attach a tab-switch handler (fluent form; same drill as the table's
    /// typed handlers).
    func onSelect(_ handler: @escaping @Sendable (ElementRef, String) async -> [FragmentUpdate]) -> Self {
        var copy = self
        copy.onSelect = handler
        return copy
    }
}

// MARK: - WebUI Avatar
public struct WebUIAvatar: View {
    public enum Size: String, Sendable {
        case sm = "avatar--sm"
        case md = "avatar--md"
        case lg = "avatar--lg"
        case xl = "avatar--xl"
    }

    public let initials: String
    public let size: Size
    public let src: String?
    public let status: String?

    public init(
        initials: String,
        size: Size = .md,
        src: String? = nil,
        status: String? = nil
    ) {
        self.initials = initials
        self.size = size
        self.src = src
        self.status = status
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attributeText = Tag.classes(["avatar", size.rawValue]) + (status.map { Tag.escAttr("data-status", $0) } ?? "")
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        if let src {
            buffer.append(Tag.void("img", Tag.classes(["avatar__img"]), Tag.escAttr("src", src), Tag.escAttr("alt", initials)))
        } else {
            buffer.append(Tag.element("span", [Tag.classes(["avatar__initials"])], htmlEscape(initials)))
        }
        if status != nil {
            buffer.append(Tag.element("span", [Tag.classes(["avatar__status"])], ""))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Progress
public struct WebUIProgress: View {
    public enum Variant: String, Sendable {
        case primary   = "progress--primary"
        case success   = "progress--success"
        case warning   = "progress--warning"
        case danger    = "progress--danger"
    }

    public enum Size: String, Sendable {
        case sm = "progress--sm"
        case md = "progress--md"
        case lg = "progress--lg"
    }

    public let value: Double  // 0.0 to 1.0
    public let variant: Variant
    public let showLabel: Bool
    public let size: Size

    public init(
        value: Double,
        variant: Variant = .primary,
        showLabel: Bool = false,
        size: Size = .md
    ) {
        self.value = min(max(value, 0), 1)
        self.variant = variant
        self.showLabel = showLabel
        self.size = size
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attributeText = Tag.classes(["progress", variant.rawValue, size.rawValue])
            + Tag.attr("role", "progressbar")
            + Tag.attr("aria-valuenow", "\(Int(value * 100))")
            + Tag.attr("aria-valuemin", "0")
            + Tag.attr("aria-valuemax", "100")
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.begin("div", Tag.classes(["progress__bar"]), Tag.attr("style", "width: \(Int(value * 100))%")))
        if showLabel {
            buffer.append(Tag.element("span", [Tag.classes(["progress__label"])], "\(Int(value * 100))%"))
        }
        buffer.append(Tag.end("div"))
        buffer.endElement()
    }
}

// MARK: - WebUI Skeleton
public struct WebUISkeleton: View {
    public enum Variant: String, Sendable {
        case text    = "skeleton--text"
        case title   = "skeleton--title"
        case avatar  = "skeleton--avatar"
        case card    = "skeleton--card"
        case custom  = ""
    }

    public let variant: Variant
    public let width: String?
    public let height: String?
    public let count: Int

    public init(
        variant: Variant = .text,
        width: String? = nil,
        height: String? = nil,
        count: Int = 1
    ) {
        self.variant = variant
        self.width = width
        self.height = height
        self.count = max(count, 1)
    }

    public func render() -> String {
        var result = ""
        for _ in 0..<count {
            // the custom variant's empty rawValue keeps its trailing space —
            // byte-pinned by the base capture
            var attrs = Tag.classes(["skeleton", variant.rawValue.isEmpty ? " " : variant.rawValue])
            if let width { attrs += Tag.attr("style", "width:\(width)") }
            if let height { attrs += Tag.attr("style", "height:\(height)") }
            attrs += Tag.attr("aria-hidden", "true")
            result += Tag.element("div", [attrs], "")
        }
        return result
    }
}

// MARK: - WebUI Toast
public struct WebUIToast: View, Dismissible {
    public enum Variant: String, Sendable {
        case info    = "toast--info"
        case success = "toast--success"
        case warning = "toast--warning"
        case danger  = "toast--danger"
    }

    public let variant: Variant
    public let message: String
    public let id: String?
    public let dismissible: Bool
    /// handler wired onto the close button; `nil` renders the static
    /// `data-dismiss` marker only.
    public var onDismiss: DismissHandler?

    public init(
        variant: Variant = .info,
        message: String,
        id: String? = nil,
        dismissible: Bool = true
    ) {
        self.variant = variant
        self.message = message
        self.id = id
        self.dismissible = dismissible
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "toast__close" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: "Dismiss")
        var attributeText = Tag.classes(["toast", variant.rawValue]) + Tag.attr("role", "alert")
        if let elementID = dismissal.elementID ?? id {
            attributeText += Tag.escAttr("id", elementID)
        }
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.element("span", [Tag.classes(["toast__icon"])], ""))
        buffer.append(Tag.element("span", [Tag.classes(["toast__message"])], htmlEscape(message)))
        if dismissible || onDismiss != nil {
            buffer.append(dismissal.buttonHTML)
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Modal
public struct WebUIModal: View, Dismissible {
    public let title: String
    public let id: String?
    public let children: [any View]
    public let footer: [any View]?
    /// handler wired onto the close button; `nil` renders the static
    /// `data-dismiss` marker only.
    public var onDismiss: DismissHandler?

    public init(
        title: String,
        id: String? = nil,
        @ViewBuilder content: () -> [any View],
        @ViewBuilder footer: () -> [any View] = { [] }
    ) {
        self.title = title
        self.id = id
        self.children = content()
        self.footer = footer()
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "modal__close" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: "Close")
        var attributeText = Tag.classes(["modal-overlay"])
        if let elementID = dismissal.elementID ?? id {
            attributeText += Tag.escAttr("id", elementID)
        }
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.begin("div",
            Tag.classes(["modal"]),
            Tag.attr("role", "dialog"),
            Tag.attr("aria-modal", "true"),
            Tag.escAttr("aria-labelledby", "\(id ?? "")-title")))
        buffer.append(Tag.begin("div", Tag.classes(["modal__header"])))
        buffer.append(Tag.element("h2", [Tag.classes(["modal__title"]), Tag.escAttr("id", "\(id ?? "")-title")], htmlEscape(title)))
        buffer.append(dismissal.buttonHTML)
        buffer.append(Tag.end("div"))
        buffer.append(Tag.begin("div", Tag.classes(["modal__body"])))
        for child in children {
            child.render(into: &buffer)
        }
        buffer.append(Tag.end("div"))
        if let footer, !footer.isEmpty {
            buffer.append(Tag.begin("div", Tag.classes(["modal__footer"])))
            for item in footer {
                item.render(into: &buffer)
            }
            buffer.append(Tag.end("div"))
        }
        buffer.append(Tag.end("div"))
        buffer.endElement()
    }
}

// MARK: - Typed interactive handlers

/// sort-header click: `(me, column)` — `me` is the table root (`ElementRef`),
/// `column` the clicked column index. the handler decides the next sort state.
public typealias TableSortHandler = @Sendable (ElementRef, Int) async -> [FragmentUpdate]

/// select-all checkbox click: `(me)` — handler decides the new selection set.
public typealias TableSelectAllHandler = @Sendable (ElementRef) async -> [FragmentUpdate]

/// per-row select checkbox click: `(me, rowID)`.
public typealias TableSelectRowHandler = @Sendable (ElementRef, String) async -> [FragmentUpdate]

/// expand/collapse button click: `(me, rowID)`.
public typealias TableExpandHandler = @Sendable (ElementRef, String) async -> [FragmentUpdate]

// MARK: - WebUI Table
public struct WebUITable: View {
    /// Per-column cell alignment. `.trailing` maps to the `.num` class
    /// (right-aligned + tabular numerals, the numeric-column convention).
    public enum Alignment: Sendable {
        case leading
        case center
        case trailing
    }

    /// Compact empty state rendered inside the table body when `rows` is
    /// empty. Distinct from the standalone `WebUIEmptyState` card: it sits in
    /// a colspan row so the table frame stays visible with no data.
    public struct EmptyState: Sendable {
        public let icon: IconName
        public let title: String
        public let message: String

        public init(icon: IconName = .inbox, title: String, message: String) {
            self.icon = icon
            self.title = title
            self.message = message
        }
    }

    public let headers: [String]
    public let rows: [[any View]]
    public let striped: Bool
    public let hoverable: Bool
    public let compact: Bool
    public let responsive: Bool
    public let wrapped: Bool
    public let alignments: [Alignment]
    public let footer: [any View]?
    public let emptyState: EmptyState?

    /// Sort direction for the active column.
    public enum SortDirection: String, Sendable {
        case ascending
        case descending
    }

    /// Stable element id for the outermost rendered element (the `.table-wrap`
    /// div when `wrapped`, otherwise the `<table>` tag). Interactive tables
    /// re-emit themselves as `FragmentUpdate(id:)` patches and register typed
    /// handlers (`onSort`/`onSelectAll`/`onSelect`/`onToggleExpand`) under
    /// stable control ids derived from this value (`{id}-sort-{col}`,
    /// `{id}-select-all`, `{id}-select-{rowId}`, `{id}-expand-{rowId}`).
    public let id: String?
    /// Column indices that may be clicked to sort (emit `.sort` affordance).
    public let sortableColumns: Set<Int>
    /// columns removed from the render entirely, by index into `headers`. the
    /// host owns this set (it is a view of the host's state), which is how the
    /// table stays server-rendered: a visibility toggle mutates host state and
    /// re-renders, rather than hiding cells in the client.
    public let hiddenColumns: Set<Int>
    /// The active sort (column + direction), rendered with `aria-sort`.
    public let sort: (column: Int, direction: SortDirection)?
    /// Render a select-all + per-row selection control (server is source of
    /// truth; `selectedRows` must be re-passed on each re-render).
    public let selectable: Bool
    /// Row identifiers, parallel to `rows`; required when `selectable` or
    /// `rowDetails` is used.
    public let rowIds: [String]
    /// Currently selected row ids (renders `tr--selected`).
    public let selectedRows: Set<String>
    /// Currently expanded row ids (renders the detail row, rotates the icon).
    public let expandedRows: Set<String>
    /// Per-row expanded detail content, keyed by row id.
    public let rowDetails: [String: any View]?

    /// sorted-column click; `nil` renders sort headers statically (no routing).
    public var onSort: TableSortHandler?
    /// select-all click; `nil` renders the checkbox statically.
    public var onSelectAll: TableSelectAllHandler?
    /// per-row select click; `nil` renders row checkboxes statically.
    public var onSelect: TableSelectRowHandler?
    /// expand/collapse click; `nil` renders expand buttons statically.
    public var onToggleExpand: TableExpandHandler?
    private static let log = Logger(label: "webui.table")

    public init(
        headers: [String],
        rows: [[any View]],
        striped: Bool = true,
        hoverable: Bool = true,
        compact: Bool = false,
        responsive: Bool = false,
        wrapped: Bool = false,
        alignments: [Alignment] = [],
        footer: [any View]? = nil,
        emptyState: EmptyState? = nil,
        id: String? = nil,
        sortableColumns: Set<Int> = [],
        hiddenColumns: Set<Int> = [],
        sort: (column: Int, direction: SortDirection)? = nil,
        selectable: Bool = false,
        rowIds: [String] = [],
        selectedRows: Set<String> = [],
        expandedRows: Set<String> = [],
        rowDetails: [String: any View]? = nil
    ) {
        self.headers = headers
        self.rows = rows
        self.striped = striped
        self.hoverable = hoverable
        self.compact = compact
        self.responsive = responsive
        self.wrapped = wrapped
        self.alignments = alignments
        self.footer = footer
        self.emptyState = emptyState
        self.id = id
        self.sortableColumns = sortableColumns
        self.hiddenColumns = hiddenColumns
        self.sort = sort
        self.selectable = selectable
        self.rowIds = rowIds
        self.selectedRows = selectedRows
        self.expandedRows = expandedRows
        self.rowDetails = rowDetails
        self.onSort = nil
        self.onSelectAll = nil
        self.onSelect = nil
        self.onToggleExpand = nil
    }

    public func render() -> String {
        var classes = ["table"]
        if striped { classes.append("table--striped") }
        if hoverable { classes.append("table--hoverable") }
        if compact { classes.append("table--compact") }
        if responsive { classes.append("table--responsive") }

        // interactive geometry
        let base = id ?? "webui-table"
        let hasSelect = selectable && !rows.isEmpty && rowIds.count == rows.count
        let hasExpand = !(rowDetails?.isEmpty ?? true) && !rows.isEmpty
        let visibleColumnCount = headers.indices.filter { !hiddenColumns.contains($0) }.count
        let totalColumns = visibleColumnCount + (hasSelect ? 1 : 0) + (hasExpand ? 1 : 0)

        let interactiveWanted = onSort != nil || onSelectAll != nil || onSelect != nil || onToggleExpand != nil
        if interactiveWanted, id == nil {
            Self.log.warning("WebUITable: typed handlers require a stable `id:` for routing; rendering controls statically.")
        }
        // `me` is the ref the typed handlers receive; the table root carries
        // the caller's stable `id`, so `me.update(...)` patches the table in
        // place and re-emitted fragments carry identical routing ids.
        let me = ElementRef.stable(base)
        let wired = interactiveWanted && id != nil

        let sortArrow = Tag.element("svg",
            [Tag.classes(["sort__arrow"]),
             Tag.attr("viewBox", "0 0 10 10"), Tag.attr("width", "10"), Tag.attr("height", "10"),
             Tag.attr("fill", "none"), Tag.attr("aria-hidden", "true")],
            Tag.selfClose("path",
                Tag.attr("d", "M2 6.5L5 3.5l3 3"),
                Tag.attr("stroke", "currentColor"), Tag.attr("stroke-width", "1.5"),
                Tag.attr("stroke-linecap", "butt"), Tag.attr("stroke-linejoin", "miter")))
        let expandIcon = Tag.element("svg",
            [Tag.classes(["table__expand-icon"]),
             Tag.attr("viewBox", "0 0 10 10"), Tag.attr("width", "10"), Tag.attr("height", "10"),
             Tag.attr("fill", "none"), Tag.attr("aria-hidden", "true")],
            Tag.selfClose("path",
                Tag.attr("d", "M3.5 2.5L6.5 5l-3 2.5"),
                Tag.attr("stroke", "currentColor"), Tag.attr("stroke-width", "1.5"),
                Tag.attr("stroke-linecap", "butt"), Tag.attr("stroke-linejoin", "miter")))

        func alignmentClass(_ index: Int) -> String? {
            guard index < alignments.count else { return nil }
            switch alignments[index] {
            case .leading: return nil
            case .center: return "align-center"
            case .trailing: return "num"
            }
        }

        var tableOpen = Tag.begin("table", id.map { Tag.escAttr("id", $0) } ?? "", Tag.classes(classes))

        var html = tableOpen
        if !headers.isEmpty {
            html += Tag.begin("thead")
            html += Tag.begin("tr")
            if hasSelect {
                let state: String
                if selectedRows.count == rowIds.count { state = "true" }
                else if selectedRows.isEmpty { state = "false" }
                else { state = "mixed" }
                var selectAllHandler: EventHandler? = nil
                if let onSelectAll {
                    let h: TableSelectAllHandler = onSelectAll
                    selectAllHandler = { event in await h(me) }
                }
                let selectAllAttrs = wired
                    ? controlAttributes(id: "\(base)-select-all", handler: selectAllHandler)
                    : ""
                html += Tag.element("th",
                    [Tag.classes(["table__select-col align-center"]), Tag.attr("scope", "col")],
                    Tag.element("span",
                        [Tag.classes(["table__select"]),
                         Tag.attr("id", "\(htmlEscape(base))-select-all"),
                         Tag.attr("role", "checkbox"), Tag.attr("aria-checked", state),
                         Tag.attr("aria-label", "Select all rows"), Tag.attr("tabindex", "0"),
                         selectAllAttrs],
                        ""))
            }
            if hasExpand {
                html += Tag.element("th", [Tag.classes(["table__expand-col"]), Tag.attr("aria-hidden", "true")], "")
            }
            for (i, h) in headers.enumerated() where !hiddenColumns.contains(i) {
                let align = alignmentClass(i)
                let sortPrefix = (align.map { "\($0) " } ?? "") + "sort-cell"
                var sortHandler: EventHandler? = nil
                if let onSort {
                    let h: TableSortHandler = onSort
                    sortHandler = { event in await h(me, i) }
                }
                let sortAttrs = wired
                    ? controlAttributes(id: "\(base)-sort-\(i)", handler: sortHandler)
                    : ""
                if let sort, sort.column == i {
                    let aria = sort.direction == .ascending ? "ascending" : "descending"
                    let desc = sort.direction == .descending ? " sort--desc" : ""
                    html += Tag.begin("th", Tag.classes([sortPrefix]), Tag.attr("aria-sort", aria))
                    html += Tag.element("span",
                        [Tag.classes(["sort sort--active", desc]),
                         Tag.attr("id", "\(htmlEscape(base))-sort-\(i)"),
                         sortAttrs],
                        htmlEscape(h) + sortArrow)
                    html += Tag.end("th")
                } else if sortableColumns.contains(i) {
                    html += Tag.begin("th", Tag.classes([sortPrefix]))
                    html += Tag.element("span",
                        [Tag.classes(["sort"]),
                         Tag.attr("id", "\(htmlEscape(base))-sort-\(i)"),
                         sortAttrs],
                        htmlEscape(h) + sortArrow)
                    html += Tag.end("th")
                } else if let a = align {
                    html += Tag.element("th", [Tag.classes([a])], htmlEscape(h))
                } else {
                    html += Tag.element("th", [], htmlEscape(h))
                }
            }
            html += Tag.end("tr")
            html += Tag.end("thead")
        }
        html += Tag.begin("tbody")
        if rows.isEmpty, let empty = emptyState {
            let colspan = totalColumns > 0 ? totalColumns : 1
            html += Tag.begin("tr")
            html += Tag.begin("td", Tag.attr("colspan", "\(colspan)"), Tag.classes(["table__empty"]))
            html += Tag.element("div", [Tag.classes(["table__empty-icon fill-slot"])], WebUIIcon(empty.icon, size: .slot).render())
            html += Tag.element("div", [Tag.classes(["table__empty-title"])], htmlEscape(empty.title))
            if !empty.message.isEmpty {
                html += Tag.element("div", [Tag.classes(["table__empty-message"])], htmlEscape(empty.message))
            }
            html += Tag.end("td")
            html += Tag.end("tr")
        } else {
            for (rowIndex, row) in rows.enumerated() {
                let rowId = rowIndex < rowIds.count ? rowIds[rowIndex] : "row-\(rowIndex)"
                let selected = selectedRows.contains(rowId)
                let expanded = expandedRows.contains(rowId)
                let trClass = [
                    selected ? "tr--selected" : nil,
                    expanded ? "tr--expanded" : nil,
                ].compactMap { $0 }.joined(separator: " ")
                let trAttrs = trClass.isEmpty ? "" : Tag.classes([trClass])
                // DX-11a (CONTINUUM_DX §2.11): the typed per-control id
                // vocabulary on INTERACTIVE tables (wired = typed handlers) —
                // every data row carries `{id}-r{rowIndex}` + `data-key`
                // (the same rowId the select/expand control ids derive from),
                // so an op-emitting handler can target rows with attr/text
                // ops instead of a whole-region replace. gated on wired so a
                // static table (no handlers, no ops) stays byte-identical;
                // attribute order id → data-key → class.
                let trIdKey: String
                if wired, let tableID = id {
                    trIdKey = Tag.attr("id", "\(htmlEscape(tableID))-r\(rowIndex)") + Tag.escAttr("data-key", rowId)
                } else {
                    trIdKey = ""
                }
                html += Tag.begin("tr", trIdKey, trAttrs)
                if hasSelect {
                    var selectHandler: EventHandler? = nil
                    if let onSelect {
                        let h: TableSelectRowHandler = onSelect
                        selectHandler = { event in await h(me, rowId) }
                    }
                    let selectAttrs = wired
                        ? controlAttributes(id: "\(base)-select-\(rowId)", handler: selectHandler)
                        : ""
                    html += Tag.element("td",
                        [Tag.classes(["table__select-col align-center"])],
                        Tag.element("span",
                            [Tag.classes(["table__select"]),
                             Tag.attr("id", "\(htmlEscape(base))-select-\(htmlEscape(rowId))"),
                             Tag.attr("role", "checkbox"), Tag.attr("aria-checked", "\(selected)"),
                             Tag.attr("aria-label", "Select row \(htmlEscape(rowId))"),
                             Tag.attr("tabindex", "0"), selectAttrs],
                            ""))
                }
                if hasExpand {
                    let canExpand = rowDetails?[rowId] != nil
                    var expandHandler: EventHandler? = nil
                    if let onToggleExpand {
                        let h: TableExpandHandler = onToggleExpand
                        expandHandler = { event in await h(me, rowId) }
                    }
                    let expandAttrs = wired
                        ? controlAttributes(id: "\(base)-expand-\(rowId)", handler: expandHandler)
                        : ""
                    if canExpand {
                        html += Tag.element("td",
                            [Tag.classes(["table__expand-col"])],
                            Tag.element("button",
                                [Tag.attr("type", "button"),
                                 Tag.classes(["table__expand-btn"]),
                                 Tag.attr("id", "\(htmlEscape(base))-expand-\(htmlEscape(rowId))"),
                                 Tag.attr("aria-expanded", "\(expanded)"),
                                 expandAttrs],
                                expandIcon))
                    } else {
                        html += Tag.element("td",
                            [Tag.classes(["table__expand-col"])],
                            Tag.element("button",
                                [Tag.attr("type", "button"),
                                 Tag.classes(["table__expand-btn"]),
                                 Tag.attr("id", "\(htmlEscape(base))-expand-\(htmlEscape(rowId))"),
                                 Tag.attr("aria-disabled", "true"),
                                 Tag.flag("disabled"),
                                 expandAttrs],
                                expandIcon))
                    }
                }
                for (i, cell) in row.enumerated() where !hiddenColumns.contains(i) {
                    var tdAttrs: [String] = []
                    if responsive, i < headers.count {
                        tdAttrs.append(Tag.escAttr("data-label", headers[i]))
                    }
                    if let a = alignmentClass(i) {
                        tdAttrs.append(Tag.classes([a]))
                    }
                    html += Tag.element("td", tdAttrs, cell.render())
                }
                html += Tag.end("tr")
                if hasExpand, expanded, let detail = rowDetails?[rowId] {
                    html += Tag.element("tr",
                        [Tag.classes(["table__detail-row"])],
                        Tag.element("td",
                            [Tag.attr("colspan", "\(totalColumns)")],
                            Tag.element("div", [Tag.classes(["table__detail"])], detail.render())))
                }
            }
        }
        html += Tag.end("tbody")
        if let footer {
            html += Tag.begin("tfoot")
            html += Tag.begin("tr")
            for (i, cell) in footer.enumerated() {
                if let a = alignmentClass(i) {
                    html += Tag.element("td", [Tag.classes([a])], cell.render())
                } else {
                    html += Tag.element("td", [], cell.render())
                }
            }
            html += Tag.end("tr")
            html += Tag.end("tfoot")
        }
        html += Tag.end("table")
        if wrapped {
            html = Tag.element("div", [Tag.classes(["table-wrap"])], html)
        }
        return html
    }
}

// MARK: - WebUITable typed handlers

public extension WebUITable {
    /// attach a sorted-column click handler. `me` references the table root
    /// element; the receiver decides the next sort state.
    func onSort(_ handler: @escaping TableSortHandler) -> Self {
        var copy = self
        copy.onSort = handler
        return copy
    }

    /// attach a select-all click handler. `me` references the table root.
    func onSelectAll(_ handler: @escaping TableSelectAllHandler) -> Self {
        var copy = self
        copy.onSelectAll = handler
        return copy
    }

    /// attach a per-row select handler; receives the clicked row id.
    func onSelect(_ handler: @escaping TableSelectRowHandler) -> Self {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    /// attach an expand/collapse handler; receives the toggled row id.
    func onToggleExpand(_ handler: @escaping TableExpandHandler) -> Self {
        var copy = self
        copy.onToggleExpand = handler
        return copy
    }
}

// MARK: - WebUI Chip
public struct WebUIChip: View, Dismissible {
    public enum Variant: String, Sendable {
        case primary   = "chip--primary"
        case secondary = "chip--secondary"
        case success   = "chip--success"
        case warning   = "chip--warning"
        case danger    = "chip--danger"
        case info      = "chip--info"
        case neutral   = "chip--neutral"
    }

    public let text: String
    public let variant: Variant
    public let removable: Bool
    public let id: String?
    /// handler wired onto the remove button; `nil` renders the static
    /// `data-remove` marker only.
    public var onDismiss: DismissHandler?

    public init(
        _ text: String,
        variant: Variant = .neutral,
        removable: Bool = false,
        id: String? = nil
    ) {
        self.text = text
        self.variant = variant
        self.removable = removable
        self.id = id
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "chip__remove" }
    public var dismissMarker: String { "data-remove" }
    public var dismissRootIdentifier: String? { id }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: "Remove")
        var attributeText = Tag.classes(["chip", variant.rawValue])
        if let elementID = dismissal.elementID ?? id {
            attributeText += Tag.escAttr("id", elementID)
        }
        buffer.beginElement("span", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.element("span", [Tag.classes(["chip__label"])], htmlEscape(text)))
        if removable || onDismiss != nil {
            buffer.append(dismissal.buttonHTML)
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Empty State
public struct WebUIEmptyState: View {
    public let icon: IconName
    public let title: String
    public let message: String
    public let action: (label: String, id: String)?

    public init(
        icon: IconName = .inbox,
        title: String,
        message: String,
        action: (String, String)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", Tag.classes(["empty-state"]))
        buffer.endOpenTag()
        buffer.append(Tag.element("div", [Tag.classes(["empty-state__icon fill-slot"])], WebUIIcon(icon, size: .slot).render()))
        buffer.append(Tag.element("h3", [Tag.classes(["empty-state__title"])], htmlEscape(title)))
        buffer.append(Tag.element("p", [Tag.classes(["empty-state__message"])], htmlEscape(message)))
        if let (label, actionId) = action {
            buffer.append(Tag.element("button", [Tag.classes(["button button--primary"]), Tag.escAttr("id", actionId)], htmlEscape(label)))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Spinner
public struct WebUISpinner: View {
    public enum Size: String, Sendable {
        case sm = "spinner--sm"
        case md = "spinner--md"
        case lg = "spinner--lg"
    }

    public let size: Size
    public let label: String?

    public init(size: Size = .md, label: String? = nil) {
        self.size = size
        self.label = label
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var attributeText = Tag.classes(["spinner", size.rawValue]) + Tag.attr("role", "status")
        if let label { attributeText += Tag.escAttr("aria-label", label) }
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.element("div", [Tag.classes(["spinner__ring"])], ""))
        if let label {
            buffer.append(Tag.element("span", [Tag.classes(["spinner__label"])], htmlEscape(label)))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Tooltip
public struct WebUITooltip: View {
    public enum Position: String, Sendable {
        case top    = "tooltip--top"
        case bottom = "tooltip--bottom"
        case left   = "tooltip--left"
        case right  = "tooltip--right"
    }

    public let text: String
    public let position: Position
    public let children: [any View]

    public init(
    _ text: String,
        position: Position = .top,
        @ViewBuilder content: () -> [any View]
    ) {
        self.text = text
        self.position = position
        self.children = content()
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", Tag.classes(["tooltip-container"]))
        buffer.endOpenTag()
        for child in children {
            child.render(into: &buffer)
        }
        buffer.append(Tag.begin("div", Tag.classes(["tooltip", position.rawValue]), Tag.attr("role", "tooltip")))
        buffer.append(Tag.element("span", [Tag.classes(["tooltip__arrow"])], ""))
        buffer.append(Tag.element("span", [Tag.classes(["tooltip__text"])], htmlEscape(text)))
        buffer.append(Tag.end("div"))
        buffer.endElement()
    }
}

// MARK: - WebUI Stat
/// KPI / metric card: a label, a large tabular value, an optional
/// trend (direction + magnitude) and compare note, and an optional
/// sparkline. Renders the canonical `.stat` block.
public struct WebUIStat: View {
    public enum Size: String, Sendable {
        case sm = "stat stat--sm"
        case md = "stat"
        case lg = "stat stat--lg"
    }

    public enum Trend: String, Sendable {
        case up   = "stat__trend--up"
        case down = "stat__trend--down"
    }

    public let label: String
    public let value: String
    public let size: Size
    /// Trend magnitude text, e.g. "+4.2%" — renders with the up/down
    /// arrow when `trendDirection` is set.
    public let trend: String?
    public let trendDirection: Trend?
    /// Small muted note beside the trend, e.g. "vs last week".
    public let compare: String?
    /// Normalized sparkline data points (any indexed series).
    public let spark: [Double]?

    public init(
        label: String,
        value: String,
        size: Size = .md,
        trend: String? = nil,
        trendDirection: Trend? = nil,
        compare: String? = nil,
        spark: [Double]? = nil
    ) {
        self.label = label
        self.value = value
        self.size = size
        self.trend = trend
        self.trendDirection = trendDirection
        self.compare = compare
        self.spark = spark
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", Tag.classes([size.rawValue]))
        buffer.endOpenTag()
        buffer.append(Tag.element("span", [Tag.classes(["stat__label"])], htmlEscape(label)))
        buffer.append(Tag.element("span", [Tag.classes(["stat__value"])], htmlEscape(value)))
        if let trend, let trendDirection {
            let arrowPath = trendDirection == .up ? "M2 6.5L5 3.5l3 3" : "M2 3.5L5 6.5l3-3"
            let arrow = Tag.element("svg",
                [Tag.classes(["stat__trend-arrow"]),
                 Tag.attr("viewBox", "0 0 10 10"), Tag.attr("width", "10"), Tag.attr("height", "10"),
                 Tag.attr("fill", "none"), Tag.attr("aria-hidden", "true")],
                Tag.selfClose("path",
                    Tag.attr("d", arrowPath),
                    Tag.attr("stroke", "currentColor"), Tag.attr("stroke-width", "1.5"),
                    Tag.attr("stroke-linecap", "butt"), Tag.attr("stroke-linejoin", "miter")))
            buffer.append(Tag.begin("span", Tag.classes(["stat__row"])))
            buffer.append(Tag.element("span", [Tag.classes(["stat__trend", trendDirection.rawValue])], arrow + htmlEscape(trend)))
            if let compare {
                buffer.append(Tag.element("span", [Tag.classes(["stat__compare"])], htmlEscape(compare)))
            }
            buffer.append(Tag.end("span"))
        } else if let compare {
            buffer.append(Tag.element("span", [Tag.classes(["stat__compare"])], htmlEscape(compare)))
        }
        if let spark, spark.count >= 2 {
            buffer.append(Tag.begin("span", Tag.classes(["stat__spark"])))
            buffer.append(sparklineSVG(spark))
            buffer.append(Tag.end("span"))
        }
        buffer.endElement()
    }

    /// A 100×32 viewBox sparkline: the series as a polyline, with a soft
    /// area fill beneath (CSS carries the token colors).
    private func sparklineSVG(_ points: [Double]) -> String {
        let (minV, maxV) = (points.min() ?? 0, points.max() ?? 1)
        let span = maxV - minV
        let h = 32.0
        let step = 100.0 / Double(points.count - 1)
        let coords = points.enumerated().map { (i, v) -> String in
            let x = Double(i) * step
            let y = span == 0 ? h / 2 : h - ((v - minV) / span) * h
            return webuiFixedPoint(x, places: 1) + "," + webuiFixedPoint(y, places: 1)
        }
        let line = coords.joined(separator: " ")
        let area = "\(coords.first ?? "0,16") \(line) 100,32 0,32"
        return Tag.begin("svg", Tag.attr("viewBox", "0 0 100 32"), Tag.attr("preserveAspectRatio", "none"), Tag.attr("aria-hidden", "true"))
            + Tag.selfClose("polygon", Tag.classes(["stat__spark-area"]), Tag.attr("points", area))
            + Tag.selfClose("polyline", Tag.classes(["stat__spark-line"]), Tag.attr("points", line))
            + Tag.end("svg")
    }
}

// MARK: - WebUI Pagination
/// Page navigation with prev/next controls, a windowed page-number list
/// (first, last, and a ±1 window around the current page, gaps
/// ellipsized), and an optional rows-per-page meta control.
/// Renders `.pagination`.
public struct WebUIPagination: View {
    public let page: Int
    public let pages: Int
    /// Stable id prefix for interactive use: `{id}-prev`, `{id}-next`,
    /// `{id}-page-{n}`, `{id}-rows`. Omit for a purely display pagination.
    public let id: String?
    /// Rows-per-page meta: current size + allowed sizes.
    public let rowsPerPage: Int?
    public let rowsPerPageOptions: [Int]
    /// page-change click (prev/next/number); `nil` renders the controls
    /// statically. receives `(me, targetPage)`.
    public var onPageChange: (@Sendable (ElementRef, Int) async -> [FragmentUpdate])?
    /// rows-per-page select change (`.change` event); receives `(me, newSize)`.
    public var onRowsPerPageChange: (@Sendable (ElementRef, Int) async -> [FragmentUpdate])?
    private static let log = Logger(label: "webui.pagination")

    public init(
        page: Int,
        pages: Int,
        id: String? = nil,
        rowsPerPage: Int? = nil,
        rowsPerPageOptions: [Int] = [10, 25, 50, 100]
    ) {
        self.page = page
        self.pages = pages
        self.id = id
        self.rowsPerPage = rowsPerPage
        self.rowsPerPageOptions = rowsPerPageOptions
        self.onPageChange = nil
        self.onRowsPerPageChange = nil
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let page = max(1, page)
        let pages = max(1, pages)
        let base = id.map { htmlEscape($0) }
        func pid(_ s: String) -> String? { base.map { "\($0)-\(s)" } }

        let interactiveWanted = onPageChange != nil || onRowsPerPageChange != nil
        if interactiveWanted, id == nil {
            Self.log.warning("WebUIPagination: typed handlers require a stable `id:` for routing; rendering controls statically.")
        }
        let wired = interactiveWanted && id != nil
        let me = id.map { ElementRef.stable($0) } ?? ElementRef.stable("webui-pagination")

        let attributeText = Tag.classes(["pagination"]) + Tag.attr("aria-label", "Pagination")
        buffer.beginElement("nav", attributeText)
        buffer.endOpenTag()
        let prevIdAttr = pid("prev").map { Tag.attr("id", $0) } ?? ""
        let prevDisabled = page <= 1 ? Tag.flag("disabled") : ""
        var prevHandler: EventHandler? = nil
        if wired, let onPageChange {
            let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
            prevHandler = { event in await h(me, max(1, page - 1)) }
        }
        let prevRoute = wired
            ? controlAttributes(id: base.map { "\($0)-prev" } ?? "", handler: prevHandler)
            : ""
        buffer.append(Tag.element("button",
            [Tag.classes(["pagination__btn"]), prevIdAttr, Tag.attr("type", "button"),
             Tag.attr("aria-label", "Previous page"), prevDisabled, prevRoute],
            "&#8249;"))
        for item in pageWindow(page: page, pages: pages) {
            switch item {
            case .ellipsis:
                buffer.append(Tag.element("span", [Tag.classes(["pagination__ellipsis"])], "…"))
            case .number(let n):
                let isActive = n == page
                let cls = isActive ? "pagination__btn pagination__btn--active" : "pagination__btn"
                let idAttr = pid("page-\(n)").map { Tag.attr("id", $0) } ?? ""
                let current = isActive ? Tag.attr("aria-current", "page") : ""
                var pageHandler: EventHandler? = nil
                if wired, let onPageChange {
                    let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
                    pageHandler = { event in await h(me, n) }
                }
                let pageRoute = wired
                    ? controlAttributes(id: base.map { "\($0)-page-\(n)" } ?? "", handler: pageHandler)
                    : ""
                buffer.append(Tag.element("button",
                    [Tag.classes([cls]), idAttr, Tag.attr("type", "button"), current, pageRoute],
                    "\(n)"))
            }
        }
        let nextIdAttr = pid("next").map { Tag.attr("id", $0) } ?? ""
        let nextDisabled = page >= pages ? Tag.flag("disabled") : ""
        var nextHandler: EventHandler? = nil
        if wired, let onPageChange {
            let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
            nextHandler = { event in await h(me, min(pages, page + 1)) }
        }
        let nextRoute = wired
            ? controlAttributes(id: base.map { "\($0)-next" } ?? "", handler: nextHandler)
            : ""
        buffer.append(Tag.element("button",
            [Tag.classes(["pagination__btn"]), nextIdAttr, Tag.attr("type", "button"),
             Tag.attr("aria-label", "Next page"), nextDisabled, nextRoute],
            "&#8250;"))
        if let rowsPerPage {
            let rowsIdAttr = pid("rows").map { Tag.attr("id", $0) } ?? ""
            var rowsHandler: EventHandler? = nil
            if wired, let onRowsPerPageChange {
                let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onRowsPerPageChange
                rowsHandler = { event in
                    let raw = event.string("value") ?? ""
                    let size = Int(raw) ?? rowsPerPage
                    return await h(me, size)
                }
            }
            let rowsRoute = wired
                ? controlAttributes(
                    id: base.map { "\($0)-rows" } ?? "",
                    event: .change,
                    handler: rowsHandler
                )
                : ""
            buffer.append(Tag.begin("span", Tag.classes(["pagination__meta"])))
            buffer.append(Tag.element("label", [], "Rows per page"))
            buffer.append(Tag.begin("select", Tag.classes(["select"]), rowsIdAttr, rowsRoute))
            for opt in rowsPerPageOptions {
                let selected = opt == rowsPerPage ? Tag.flag("selected") : ""
                buffer.append(Tag.element("option", [Tag.attr("value", "\(opt)"), selected], "\(opt)"))
            }
            buffer.append(Tag.end("select"))
            buffer.append(Tag.end("span"))
        }
        buffer.endElement()
    }

    private enum Item {
        case number(Int)
        case ellipsis
    }

    /// 1 … 4 5 6 … 12 style windowing: first + last always, ±1 around the
    /// current page, gaps collapsed to a single ellipsis.
    private func pageWindow(page: Int, pages: Int) -> [Item] {
        if pages <= 7 { return (1...pages).map { .number($0) } }
        var shown: Set<Int> = [1, 2, pages - 1, pages]
        for n in max(1, page - 1)...min(pages, page + 1) { shown.insert(n) }
        var items: [Item] = []
        var prev = 0
        for n in shown.sorted() {
            if n - prev > 1 { items.append(.ellipsis) }
            items.append(.number(n))
            prev = n
        }
        return items
    }
}

// MARK: - WebUIPagination typed handlers

public extension WebUIPagination {
    /// attach a page-change handler. `me` references the pagination root;
    /// the receiver decides the next page.
    func onPageChange(_ handler: @escaping @Sendable (ElementRef, Int) async -> [FragmentUpdate]) -> Self {
        var copy = self
        copy.onPageChange = handler
        return copy
    }

    /// attach a rows-per-page change handler; receives the new size.
    func onRowsPerPageChange(_ handler: @escaping @Sendable (ElementRef, Int) async -> [FragmentUpdate]) -> Self {
        var copy = self
        copy.onRowsPerPageChange = handler
        return copy
    }
}

// MARK: - WebUI Timeline
/// A vertical (or horizontal) event timeline with status dots. Each event
/// can be plain, completed (filled dot + check), current (pulsing dot), or
/// error (danger dot). Renders `.timeline`.
public struct WebUITimeline: View {
    public enum Orientation: String, Sendable {
        case vertical   = "timeline"
        case horizontal = "timeline timeline--horizontal"
    }

    public enum Status: String, Sendable {
        case plain
        case completed = "timeline__event--completed"
        case current   = "timeline__event--current"
        case error     = "timeline__event--error"
    }

    public struct Event: Sendable {
        public let time: String
        public let title: String
        public let desc: String?
        public let status: Status

        public init(time: String, title: String, desc: String? = nil, status: Status = .plain) {
            self.time = time
            self.title = title
            self.desc = desc
            self.status = status
        }
    }

    public let events: [Event]
    public let orientation: Orientation

    public init(events: [Event], orientation: Orientation = .vertical) {
        self.events = events
        self.orientation = orientation
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", Tag.classes([orientation.rawValue]))
        buffer.endOpenTag()
        for event in events {
            let statusCls = event.status == .plain ? "" : " \(event.status.rawValue)"
            buffer.append(Tag.begin("div", Tag.classes(["timeline__event", statusCls])))
            buffer.append(Tag.element("span", [Tag.classes(["timeline__dot"])], ""))
            buffer.append(Tag.element("span", [Tag.classes(["timeline__time"])], htmlEscape(event.time)))
            buffer.append(Tag.element("div", [Tag.classes(["timeline__title"])], htmlEscape(event.title)))
            if let desc = event.desc {
                buffer.append(Tag.element("div", [Tag.classes(["timeline__desc"])], htmlEscape(desc)))
            }
            buffer.append(Tag.end("div"))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Tree
/// A recursive node tree with rotating carets, leaf indicators, icons,
/// and row selection. Open/closed state and selection are rendered from
/// the passed-in state (server-driven, like the interactive table); row
/// elements carry stable `id`s when a base `id` is provided.
/// Renders `.tree`.
public struct WebUITree: View {
    public struct Node: Sendable {
        public let id: String
        public let label: String
        public let icon: IconName?
        public let children: [Node]?

        public init(id: String, label: String, icon: IconName? = nil, children: [Node]? = nil) {
            self.id = id
            self.label = label
            self.icon = icon
            self.children = children
        }
    }

    public let nodes: [Node]
    public let id: String?
    public let expanded: Set<String>
    public let selected: String?
    public let onToggle: EventHandler?

    public init(nodes: [Node], id: String? = nil, expanded: Set<String> = [], selected: String? = nil, onToggle: EventHandler? = nil) {
        self.nodes = nodes
        self.id = id
        self.expanded = expanded
        self.selected = selected
        self.onToggle = onToggle
    }

    public func render() -> String {
        let interactive = onToggle != nil && id != nil
        var attrs = Tag.classes(["tree", interactive ? " tree--interactive" : ""]) + Tag.attr("role", "tree")
        if let id = id {
            attrs += Tag.escAttr("id", id)
        }
        if onToggle != nil, let id = id {
            attrs += controlAttributes(id: id, event: .click, handler: onToggle)
        }
        var html = Tag.begin("div", attrs)
        for node in nodes { html += renderNode(node, level: 1, interactive: interactive) }
        html += Tag.end("div")
        return html
    }

    private func renderNode(_ node: Node, level: Int, interactive: Bool) -> String {
        let hasChildren = !(node.children?.isEmpty ?? true)
        let isOpen = hasChildren && expanded.contains(node.id)
        let nodeCls = isOpen ? "tree__node tree__node--open" : "tree__node"
        let rowCls = selected == node.id ? "tree__row tree__row--selected" : "tree__row"
        let caretCls = hasChildren ? "tree__caret" : "tree__caret tree__caret--leaf"

        var rowAttrs = ""
        if let base = id {
            rowAttrs += Tag.attr("id", "\(htmlEscape(base))-node-\(htmlEscape(node.id))")
        }
        rowAttrs += Tag.attr("role", "treeitem")
        rowAttrs += Tag.attr("aria-level", String(level))
        if hasChildren {
            rowAttrs += Tag.attr("aria-expanded", String(isOpen))
        }
        if interactive {
            rowAttrs += Tag.attr("tabindex", "0")
        }

        var html = Tag.begin("div", Tag.classes([nodeCls]), hasChildren ? Tag.attr("role", "group") : "")
        html += Tag.begin("div", Tag.classes([rowCls]), rowAttrs)
        html += Tag.element("span", [Tag.classes([caretCls])], "")
        if let icon = node.icon {
            html += Tag.element("span", [Tag.classes(["tree__icon fill-slot"])], WebUIIcon(icon, size: .slot).render())
        }
        html += Tag.element("span", [Tag.classes(["tree__label"])], htmlEscape(node.label))
        html += Tag.end("div")
        if let children = node.children, !children.isEmpty {
            html += Tag.begin("div", Tag.classes(["tree__children"]))
            for child in children { html += renderNode(child, level: level + 1, interactive: interactive) }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: - WebUI Breadcrumb
/// Hierarchical navigation trail. Leading items render as links; the
/// current item is emphasized and aria-current. When `collapse` is set and
/// the trail exceeds `maxItems`, the middle collapses to an ellipsis
/// button. Renders `.breadcrumb`.
public struct WebUIBreadcrumb: View {
    public struct Item: Sendable {
        public let label: String
        public let href: String?

        public init(_ label: String, href: String? = nil) {
            self.label = label
            self.href = href
        }
    }

    public let items: [Item]
    public let current: Item
    public let slash: Bool
    public let id: String?
    /// Collapse the middle when the total exceeds `maxItems`.
    public let collapse: Bool
    public let maxItems: Int

    public init(
        items: [Item],
        current: Item,
        slash: Bool = false,
        id: String? = nil,
        collapse: Bool = true,
        maxItems: Int = 5
    ) {
        self.items = items
        self.current = current
        self.slash = slash
        self.id = id
        self.collapse = collapse
        self.maxItems = maxItems
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let all = items + [current]
        let sep: String = slash ? "/" : "›"
        let base = id.map { htmlEscape($0) }
        let slashCls = slash ? " breadcrumb--slash" : ""

        // which segments render as links (head), which are collapsed into
        // the ellipsis, which render as the tail
        let collapsed = collapse && all.count > maxItems
        let headCount = collapsed ? 1 : all.count - 1
        // the tail always carries the current segment: the last two entries
        // when collapsed (last link + current), and just the current otherwise —
        // a zero-length tail dropped the current entirely on every short trail.
        let tailCount = collapsed ? 2 : 1

        func itemHTML(_ item: Item, index: Int, isCurrent: Bool) -> String {
            let idAttr = isCurrent ? "" : base.map { Tag.attr("id", "\($0)-item-\(index)") } ?? ""
            if isCurrent {
                return Tag.element("span",
                    [Tag.classes(["breadcrumb__item breadcrumb__item--current"]), Tag.attr("aria-current", "page")],
                    htmlEscape(item.label))
            }
            if let href = item.href {
                // canonical URL policy: a blocked scheme degrades to plain
                // text (never an href) — mirrors the Link/Image primitives.
                guard let safe = sanitizeURL(href) else {
                    return Tag.element("span", [Tag.classes(["breadcrumb__item"]), idAttr], htmlEscape(item.label))
                }
                return Tag.element("a", [Tag.classes(["breadcrumb__item"]), idAttr, Tag.escAttr("href", safe)], htmlEscape(item.label))
            }
            return Tag.element("span", [Tag.classes(["breadcrumb__item"]), idAttr], htmlEscape(item.label))
        }
        func sepHTML() -> String {
            Tag.element("span", [Tag.classes(["breadcrumb__separator"]), Tag.attr("aria-hidden", "true")], htmlEscape(sep))
        }

        let attributeText = Tag.classes(["breadcrumb", slashCls]) + Tag.attr("aria-label", "Breadcrumb")
        buffer.beginElement("nav", attributeText)
        buffer.endOpenTag()
        // head (links)
        for i in 0..<headCount {
            buffer.append(itemHTML(all[i], index: i, isCurrent: false))
            buffer.append(sepHTML())
        }
        // collapsed middle
        if collapsed {
            let ellipsisId = base.map { Tag.attr("id", "\($0)-ellipsis") } ?? ""
            buffer.append(Tag.element("button",
                [Tag.attr("type", "button"), Tag.classes(["breadcrumb__ellipsis"]), ellipsisId,
                 Tag.attr("aria-label", "Show omitted items")],
                "…"))
            buffer.append(sepHTML())
        }
        // tail (last N−1 as links, final as current)
        let tailStart = all.count - tailCount
        for i in 0..<tailCount {
            let idx = tailStart + i
            let isCurrent = idx == all.count - 1
            buffer.append(itemHTML(all[idx], index: idx, isCurrent: isCurrent))
            if !isCurrent { buffer.append(sepHTML()) }
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Description List
/// A term/detail description list — the canonical payload for an
/// expanded table row or a detail panel. Renders `.list--desc` (a
/// two-column grid: medium-weight term, muted detail).
public struct WebUIDescriptionList: View {
    public let items: [(term: String, detail: String)]

    public init(_ items: [(String, String)]) {
        self.items = items.map { (term: $0.0, detail: $0.1) }
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("dl", Tag.classes(["list--desc"]))
        buffer.endOpenTag()
        for item in items {
            buffer.append(Tag.element("dt", [], htmlEscape(item.term)))
            buffer.append(Tag.element("dd", [], htmlEscape(item.detail)))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Aspect Ratio
/// a box locked to a fixed width:height ratio, for media, embeds and
/// placeholders. it fills the width its container gives it, so compose it with
/// a sized parent (grid track, fixed `.width(_:)`, or a full-width block).
/// the sheet ships the dashed-form variants (`aspect--16-9`); the
/// older `x` spellings (`16x9-style`) stay in the sheet for legacy call sites
/// and are not addressable from here.
public struct WebUIAspectRatio: View {
    public enum Ratio: String, Sendable {
        case wide = "aspect--21-9"
        case standard = "aspect--16-9"
        case photo = "aspect--4-3"
        case square = "aspect--1-1"
        case portrait = "aspect--3x4"
        case tall = "aspect--9x16"
    }

    public let ratio: Ratio
    /// caption drawn inside the box, e.g. "16 / 9".
    public let label: String?

    public init(_ ratio: Ratio = .standard, label: String? = nil) {
        self.ratio = ratio
        self.label = label
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.beginElement("div", Tag.classes(["aspect", ratio.rawValue]))
        buffer.endOpenTag()
        if let label {
            buffer.append(Tag.element("span", [Tag.classes(["aspect__label"])], htmlEscape(label)))
        }
        buffer.endElement()
    }
}

// MARK: - WebUI Circular Progress
/// a radial progress ring with an optional centre label. the arc uses the
/// sheet's stroke-dashoffset technique on a 36-unit viewBox, so the
/// circumference is 100 and the dash offset reads directly as a percentage.
public struct WebUICircularProgress: View {
    public enum Tone: String, Sendable {
        case primary = ""
        case success = "ring--success"
        case warning = "ring--warning"
        case danger = "ring--danger"
    }

    public enum Size: String, Sendable {
        case small = "ring--sm"
        case medium = ""
        case large = "ring--lg"
    }

    /// completion in 0...1 (clamped). ignored when `indeterminate`.
    public let value: Double
    public let label: String?
    public let sublabel: String?
    public let tone: Tone
    public let size: Size
    public let indeterminate: Bool
    /// accessible name for the `progressbar` role.
    public let ariaLabel: String

    public init(
        value: Double,
        label: String? = nil,
        sublabel: String? = nil,
        tone: Tone = .primary,
        size: Size = .medium,
        indeterminate: Bool = false,
        ariaLabel: String = "progress"
    ) {
        self.value = value
        self.label = label
        self.sublabel = sublabel
        self.tone = tone
        self.size = size
        self.indeterminate = indeterminate
        self.ariaLabel = ariaLabel
    }

    public func render() -> String {
        renderThroughBuffer()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let clamped = value < 0 ? 0 : (value > 1 ? 1 : value)
        var classes = ["ring"]
        if !size.rawValue.isEmpty { classes.append(size.rawValue) }
        if !tone.rawValue.isEmpty { classes.append(tone.rawValue) }
        if indeterminate { classes.append("ring--indeterminate") }
        var attributeText = Tag.classes(classes) + Tag.attr("role", "progressbar")
        attributeText += Tag.escAttr("aria-label", ariaLabel)
        if !indeterminate {
            attributeText += Tag.attr("aria-valuemin", "0") + Tag.attr("aria-valuemax", "100") + Tag.attr("aria-valuenow", "\(Int((clamped * 100).rounded()))")
        }
        buffer.beginElement("div", attributeText)
        buffer.endOpenTag()
        buffer.append(Tag.begin("svg", Tag.attr("viewBox", "0 0 36 36"), Tag.attr("aria-hidden", "true")))
        buffer.append(Tag.selfClose("circle", Tag.classes(["ring__track"]), Tag.attr("cx", "18"), Tag.attr("cy", "18"), Tag.attr("r", "15.915")))
        if indeterminate {
            buffer.append(Tag.selfClose("circle", Tag.classes(["ring__fill"]), Tag.attr("cx", "18"), Tag.attr("cy", "18"), Tag.attr("r", "15.915")))
        } else {
            let offset = webuiFixedPoint((1 - clamped) * 100, places: 1)
            buffer.append(Tag.selfClose("circle", Tag.classes(["ring__fill"]), Tag.attr("cx", "18"), Tag.attr("cy", "18"), Tag.attr("r", "15.915"), Tag.attr("stroke-dasharray", "100"), Tag.attr("stroke-dashoffset", offset)))
        }
        buffer.append(Tag.end("svg"))
        if label != nil || sublabel != nil {
            buffer.append(Tag.begin("span", Tag.classes(["ring__label"])))
            if let label { buffer.append(htmlEscape(label)) }
            if let sublabel { buffer.append(Tag.element("span", [Tag.classes(["ring__label-sub"])], htmlEscape(sublabel))) }
            buffer.append(Tag.end("span"))
        }
        buffer.endElement()
    }
}
