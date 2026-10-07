import WebUICore

// ============================================================================
// MARK: - Forms & input extras
// ============================================================================

// MARK: WebUI Slider
/// a range slider with fill, thumb, ticks, and labels.
public struct WebUISlider: View {
    public enum Size: String, Sendable { case sm = " slider--sm", md = "", lg = " slider--lg" }
    public let value: Double
    public let min: Double
    public let max: Double
    public let size: Size
    public let vertical: Bool
    public let showLabels: Bool
    public let minLabel: String
    public let maxLabel: String
    /// stable id; when set with `onChange` the range input self-wires
    /// (`targetId == "<id>-input"`, event `.input`).
    public let id: String?
    public let onChange: EventHandler?
    public init(_ value: Double, min: Double = 0, max: Double = 100, size: Size = .md,
                vertical: Bool = false, showLabels: Bool = false, minLabel: String = "", maxLabel: String = "",
                id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.min = min; self.max = max; self.size = size
        self.vertical = vertical; self.showLabels = showLabels; self.minLabel = minLabel; self.maxLabel = maxLabel
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let range = Swift.max(self.max - self.min, 1e-9)
        let pct = Swift.min(Swift.max((self.max - self.min) / range * 100.0, 0), 100)
        let inputID = id.map { htmlEscape("\($0)-input") } ?? ""
        let inputAttrs = id.map { controlAttributes(id: "\($0)-input", event: .input, handler: onChange) } ?? ""
        let idAttr = inputID.isEmpty ? "" : Tag.attr("id", inputID)
        var html = Tag.begin("div", Tag.classes(["slider", size.rawValue, vertical ? " slider--vertical" : ""]))
        html += Tag.void(
            "input",
            Tag.attr("type", "range"),
            Tag.classes(["slider__input"]),
            idAttr,
            Tag.attr("min", "\(min)"),
            Tag.attr("max", "\(max)"),
            Tag.attr("value", "\(value)"),
            Tag.attr("aria-valuenow", "\(value)"),
            inputAttrs)
        html += Tag.begin("div", Tag.classes(["slider__track"]))
        html += Tag.element("div", [Tag.classes(["slider__fill"]), Tag.attr("style", "width:\(webuiFixedPoint(pct, places: 2))%")], "")
        html += Tag.element("span", [Tag.classes(["slider__thumb"]), Tag.attr("style", "left:\(webuiFixedPoint(pct, places: 2))%")], "")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["slider__ticks"]))
        for _ in 0..<11 { html += Tag.element("span", [Tag.classes(["slider__tick"])], "") }
        html += Tag.end("div")
        if showLabels {
            html += Tag.begin("div", Tag.classes(["slider__labels"]))
            html += Tag.element("span", [], htmlEscape(minLabel.isEmpty ? "\(min)" : minLabel))
            html += Tag.element("span", [], htmlEscape(maxLabel.isEmpty ? "\(max)" : maxLabel))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Toggle
/// a switch control with label.
public struct WebUIToggle: View {
    public enum Size: String, Sendable { case sm = " toggle--sm", md = "", lg = " toggle--lg" }
    public let label: String
    public let checked: Bool
    public let size: Size
    public let labelLeft: Bool
    public let loading: Bool
    public let disabled: Bool
    /// stable id; when set with `onChange` the checkbox input self-wires
    /// (`targetId == "<id>-input"`, event `.change`).
    public let id: String?
    public let onChange: EventHandler?
    public init(_ label: String = "", checked: Bool = false, size: Size = .md,
                labelLeft: Bool = false, loading: Bool = false, disabled: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.label = label; self.checked = checked; self.size = size
        self.labelLeft = labelLeft; self.loading = loading; self.disabled = disabled
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        var classes = ["toggle", size.rawValue]
        if labelLeft { classes.append("toggle--label-left") }
        if loading { classes.append("toggle--loading") }
        if disabled { classes.append("toggle--disabled") }
        let inputID = id.map { htmlEscape("\($0)-input") } ?? ""
        let inputAttrs = id.map { controlAttributes(id: "\($0)-input", event: .change, handler: onChange) } ?? ""
        let idAttr = inputID.isEmpty ? "" : Tag.attr("id", inputID)
        var html = Tag.begin("label", Tag.classes(classes))
        if labelLeft && !label.isEmpty { html += Tag.element("span", [Tag.classes(["toggle__label"])], htmlEscape(label)) }
        html += Tag.void(
            "input",
            Tag.attr("type", "checkbox"),
            Tag.classes(["toggle__input"]),
            idAttr,
            checked ? Tag.flag("checked") : "",
            disabled ? Tag.flag("disabled") : "",
            inputAttrs)
        html += Tag.begin("span", Tag.classes(["toggle__track"]))
        html += Tag.element("span", [Tag.classes(["toggle__thumb"])], "")
        html += Tag.end("span")
        if !labelLeft && !label.isEmpty { html += Tag.element("span", [Tag.classes(["toggle__label"])], htmlEscape(label)) }
        html += Tag.end("label")
        return html
    }
}

// MARK: WebUI Stepper
/// a numeric stepper with +/− buttons.
public struct WebUIStepper: View {
    public enum Size: String, Sendable { case sm = " stepper--sm", md = "", lg = " stepper--lg" }
    public let value: Int
    public let size: Size
    /// stable container id; when set with `onChange` the +/− buttons
    /// self-wire (`targetId == "<id>-inc" | "<id>-dec"`).
    public let id: String?
    public let onChange: EventHandler?
    public init(_ value: Int, size: Size = .md, id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.size = size; self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let attrs: String
        if let id, let onChange {
            attrs = controlAttributes(id: id, event: .click, handler: onChange)
        } else {
            attrs = ""
        }
        let decID = id.map { Tag.escAttr("id", "\($0)-dec") } ?? ""
        let incID = id.map { Tag.escAttr("id", "\($0)-inc") } ?? ""
        var html = Tag.begin("div", Tag.classes(["stepper", size.rawValue]), attrs, Tag.attr("role", "group"), Tag.attr("aria-label", "Stepper"))
        html += Tag.element("button", [Tag.classes(["stepper__btn"]), decID, Tag.attr("aria-label", "Decrease")], "−")
        html += Tag.element("span", [Tag.classes(["stepper__value"])], "\(value)")
        html += Tag.element("button", [Tag.classes(["stepper__btn"]), incID, Tag.attr("aria-label", "Increase")], "+")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI OTP
/// a one-time-code input with per-digit cells.
public struct WebUIOTP: View {
    public enum Size: String, Sendable { case sm = " otp--sm", md = "", lg = " otp--lg" }
    public let length: Int
    public let value: [Int]?
    public let size: Size
    public let error: Bool
    /// stable id; when set with `onChange` each digit cell self-wires
    /// (`targetId == "<id>-cell-<index>"`, event `.input`).
    public let id: String?
    public let onChange: EventHandler?
    public init(length: Int = 6, value: [Int]? = nil, size: Size = .md, error: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.length = length; self.value = value; self.size = size; self.error = error
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let digits = value ?? []
        var html = Tag.begin("div", Tag.classes(["otp", size.rawValue, error ? " otp--error" : ""]), Tag.attr("aria-label", "One-time code"))
        for i in 0..<length {
            let filled = i < digits.count
            let cellID = id.map { Tag.escAttr("id", "\($0)-cell-\(i)") } ?? ""
            let cellAttrs = id.map { controlAttributes(id: "\($0)-cell-\(i)", event: .input, handler: onChange) } ?? ""
            html += Tag.void(
                "input",
                Tag.classes(["otp__cell", filled ? " otp__cell--filled" : "", i == digits.count ? " otp__cell--active" : ""]),
                cellID,
                Tag.attr("type", "text"),
                Tag.attr("inputmode", "numeric"),
                Tag.attr("maxlength", "1"),
                Tag.attr("value", filled ? "\(digits[i])" : ""),
                Tag.attr("aria-label", "Digit \(i + 1)"),
                cellAttrs)
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI MFA
/// a multi-factor auth flow: QR, steps, recovery codes.
public struct WebUIMFA: View {
    public struct Recovery: Sendable { public let code: String
        public init(_ code: String) { self.code = code } }
    public let recoveryCodes: [Recovery]
    public init(recoveryCodes: [Recovery] = []) { self.recoveryCodes = recoveryCodes }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["mfa"]))
        html += Tag.begin("div", Tag.classes(["mfa__qr"]))
        html += Tag.begin("div", Tag.classes(["qr"]))
        html += Tag.begin("div", Tag.classes(["qr__code"]))
        for _ in 0..<(11 * 11) { html += Tag.element("span", [Tag.classes(["qr__cell"])], "") }
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["mfa__steps"]))
        html += Tag.begin("div", Tag.classes(["mfa__step"]))
        html += Tag.element("span", [Tag.classes(["mfa__step-label"])], "Scan")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["mfa__step mfa__step--current"]))
        html += Tag.element("span", [Tag.classes(["mfa__step-label"])], "Enter code")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["mfa__step"]))
        html += Tag.element("span", [Tag.classes(["mfa__step-label"])], "Verify")
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["mfa__code"]))
        for i in 0..<6 {
            html += Tag.element("span", [Tag.classes(["mfa__digit"])], i < 2 ? "•" : "·")
        }
        html += Tag.end("div")
        if !recoveryCodes.isEmpty {
            html += Tag.begin("div", Tag.classes(["mfa__recovery"]))
            for r in recoveryCodes { html += Tag.element("div", [Tag.classes(["mfa__recovery-item"])], htmlEscape(r.code)) }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Recurrence
/// a recurring-event frequency selector.
public struct WebUIRecurrence: View {
    public struct Option: Sendable { public let label: String; public let active: Bool
        public init(_ label: String, active: Bool = false) { self.label = label; self.active = active } }
    public let options: [Option]
    public let days: [String]
    /// stable id; when set with `onChange` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); each chip gets
    /// `id == "<id>-chip-<index>"` and each day `id == "<id>-day-<index>"`.
    public let id: String?
    public let onChange: EventHandler?
    public init(options: [Option], days: [String] = ["M", "T", "W", "T", "F", "S", "S"],
                id: String? = nil, onChange: EventHandler? = nil) {
        self.options = options; self.days = days
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["recurrence"]), rootAttrs)
        html += Tag.begin("div", Tag.classes(["recurrence__options"]))
        for (i, opt) in options.enumerated() {
            let chipID = id.map { Tag.escAttr("id", "\($0)-chip-\(i)") } ?? ""
            html += Tag.element("button", [Tag.classes(["recurrence__chip", opt.active ? " recurrence__chip--active" : ""]), chipID], htmlEscape(opt.label))
        }
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["recurrence__days"]))
        for (i, d) in days.enumerated() {
            let dayID = id.map { Tag.escAttr("id", "\($0)-day-\(i)") } ?? ""
            html += Tag.element("button", [Tag.classes(["recurrence__day", i < 5 ? " recurrence__day--active" : ""]), dayID], htmlEscape(d))
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Multi Select
/// a searchable multi-value select.
public struct WebUIMultiSelect: View {
    public struct Option: Sendable { public let label: String; public let selected: Bool
        public init(_ label: String, selected: Bool = false) { self.label = label; self.selected = selected } }
    public let options: [Option]
    public let placeholder: String
    /// stable id; when set with `onChange` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); each option gets
    /// `id == "<id>-opt-<index>"`.
    public let id: String?
    public let onChange: EventHandler?
    public init(options: [Option], placeholder: String = "Select…",
                id: String? = nil, onChange: EventHandler? = nil) {
        self.options = options; self.placeholder = placeholder
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let sel = options.filter(\.selected)
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["multiselect"]), rootAttrs)
        html += Tag.begin("button", Tag.classes(["multiselect__trigger"]))
        if sel.isEmpty {
            html += Tag.element("span", [Tag.classes(["multiselect__placeholder"])], htmlEscape(placeholder))
        } else {
            for s in sel { html += Tag.element("span", [Tag.classes(["chip chip--sm"])], htmlEscape(s.label)) }
            if sel.count > 2 { html += Tag.element("span", [Tag.classes(["multiselect__more"])], "+\(sel.count - 2)") }
        }
        html += Tag.element("span", [Tag.classes(["multiselect__chevron"])], "▾")
        html += Tag.end("button")
        html += Tag.begin("div", Tag.classes(["multiselect__panel"]))
        html += Tag.begin("div", Tag.classes(["multiselect__search"]))
        html += Tag.void("input", Tag.attr("type", "search"), Tag.attr("placeholder", "Filter…"))
        html += Tag.end("div")
        for (i, option) in options.enumerated() {
            let optID = id.map { Tag.escAttr("id", "\($0)-opt-\(i)") } ?? ""
            html += Tag.element("div", [Tag.classes(["multiselect__option", option.selected ? " multiselect__option--selected" : ""]), optID], htmlEscape(option.label))
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Validation
/// an inline validation message.
public struct WebUIValidation: View {
    public enum State: String, Sendable { case success = " validation--success", error = " validation--error", warning = " validation--warning" }
    public let message: String
    public let state: State
    public init(_ message: String, state: State = .error) { self.message = message; self.state = state }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["validation", state.rawValue]), Tag.attr("role", "status"))
        html += Tag.element("span", [Tag.classes(["validation__icon"]), Tag.attr("aria-hidden", "true")], state == .success ? "✓" : (state == .warning ? "!" : "✗"))
        html += Tag.element("span", [Tag.classes(["validation__text"])], htmlEscape(message))
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Drop Zone
/// a drag-and-drop file target.
public struct WebUIDropZone: View {
    public let title: String
    public let hint: String
    public let hover: Bool
    public init(_ title: String, hint: String = "", hover: Bool = false) { self.title = title; self.hint = hint; self.hover = hover }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["dropzone", hover ? " dropzone--hover" : ""]), Tag.attr("role", "button"), Tag.attr("tabindex", "0"))
        html += Tag.element("div", [Tag.classes(["file-drop__icon"]), Tag.attr("aria-hidden", "true")], "⇪")
        html += Tag.element("div", [Tag.classes(["file-drop__title"])], htmlEscape(title))
        if !hint.isEmpty { html += Tag.element("div", [Tag.classes(["file-drop__hint"])], htmlEscape(hint)) }
        html += Tag.void("input", Tag.attr("type", "file"), Tag.attr("style", "display:none"))
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Signature
/// a signature capture pad.
public struct WebUISignature: View {
    public let label: String
    public init(_ label: String = "Sign here") { self.label = label }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["sigpad"]))
        html += Tag.element("div", [Tag.classes(["sigpad__canvas"]), Tag.attr("role", "img"), Tag.escAttr("aria-label", label)], "")
        html += Tag.begin("div", Tag.classes(["sigpad__tools"]))
        html += Tag.element("button", [Tag.classes(["button button--ghost button--sm"])], "Clear")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Inline Edit
/// an editable inline value with idle/editing/saved states.
public struct WebUIInlineEdit: View {
    public enum State: String, Sendable { case idle = " inline-edit--idle", editing = " inline-edit--editing", saved = " inline-edit--saved" }
    public let value: String
    public let state: State
    public let error: Bool
    /// stable id; when set with `onSave` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); the save button gets
    /// `id == "<id>-save"` and cancel `<id>-cancel`.
    public let id: String?
    public let onSave: EventHandler?
    public init(_ value: String, state: State = .idle, error: Bool = false,
                id: String? = nil, onSave: EventHandler? = nil) {
        self.value = value; self.state = state; self.error = error
        self.id = id; self.onSave = onSave
    }

    public func render() -> String {
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onSave) } ?? ""
        let saveID = id.map { Tag.escAttr("id", "\($0)-save") } ?? ""
        let cancelID = id.map { Tag.escAttr("id", "\($0)-cancel") } ?? ""
        var html = Tag.begin("div", Tag.classes(["inline-edit", state.rawValue, error ? " inline-edit--error" : ""]), rootAttrs)
        html += Tag.begin("div", Tag.classes(["inline-edit__value"]))
        html += htmlEscape(value)
        html += Tag.element("span", [Tag.classes(["inline-edit__pencil"]), Tag.attr("aria-hidden", "true")], "✎")
        html += Tag.end("div")
        if state == .editing {
            html += Tag.begin("div", Tag.classes(["inline-edit__editing"]))
            html += Tag.void("input",
                Tag.classes(["inline-edit__input", error ? " inline-edit__input--error" : ""]),
                Tag.escAttr("value", value))
            html += Tag.begin("div", Tag.classes(["inline-edit__actions"]))
            html += Tag.element("button", [Tag.classes(["inline-edit__check"]), saveID, Tag.attr("aria-label", "Save")], "✓")
            html += Tag.element("button", [Tag.classes(["inline-edit__pencil"]), cancelID, Tag.attr("aria-label", "Cancel")], "✕")
            html += Tag.end("div")
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Masked
/// a masked input with a prefix marker.
public struct WebUIMasked: View {
    public let value: String
    public let prefix: String?
    public let masked: Bool
    public init(_ value: String, prefix: String? = nil, masked: Bool = true) { self.value = value; self.prefix = prefix; self.masked = masked }

    public func render() -> String {
        let display = masked ? String(repeating: "•", count: value.count) : value
        var html = Tag.begin("div", Tag.classes(["masked"]))
        if let prefix { html += Tag.element("span", [Tag.classes(["masked__prefix"])], htmlEscape(prefix)) }
        html += Tag.void("input", Tag.attr("type", "text"), Tag.escAttr("value", display), Tag.attr("aria-label", "masked value"))
        html += Tag.element("span", [Tag.classes(["masked__caret"]), Tag.attr("aria-hidden", "true")], "")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Rating
/// a star rating.
public struct WebUIRating: View {
    public enum Size: String, Sendable { case sm = " rating--sm", md = "", lg = " rating--lg" }
    public let value: Double
    public let max: Int
    public let size: Size
    public let heart: Bool
    public let showValue: Bool
    /// stable id; when set with `onChange` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); each star gets
    /// `id == "<id>-star-<index>"` (1-based).
    public let id: String?
    public let onChange: EventHandler?
    public init(_ value: Double, max: Int = 5, size: Size = .md, heart: Bool = false, showValue: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.max = max; self.size = size; self.heart = heart; self.showValue = showValue
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let full = Int(value)
        var classes = ["rating", size.rawValue]
        if heart { classes.append("rating--heart") }
        if full > 0 { classes.append("rating--filled") }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(classes), rootAttrs, Tag.attr("role", "img"), Tag.attr("aria-label", "\(value) of \(max)"))
        for i in 1...max {
            let glyph = heart ? "♥" : "★"
            let filled = i <= full
            let starID = id.map { Tag.escAttr("id", "\($0)-star-\(i)") } ?? ""
            html += Tag.element("span", [Tag.classes(["rating__star", filled ? " rating__star--filled" : ""]), starID, Tag.attr("aria-hidden", "true")], glyph)
        }
        if showValue { html += Tag.element("span", [Tag.classes(["rating__value"])], "\(value)") }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Tag
/// an inline tag/label.
public struct WebUITag: View {
    public enum Variant: String, Sendable { case solid = " tag--solid", outlined = " tag--outlined", ghost = " tag--ghost",
        primary = " tag--primary", success = " tag--success", warning = " tag--warning", danger = " tag--danger", info = " tag--info" }
    public let label: String
    public let variant: Variant
    public let removable: Bool
    public let clickable: Bool
    public let count: Int?
    public let icon: IconName?
    /// stable id; when set with `onRemove` the root span self-wires
    /// (`targetId == "<id>"`, event `.click`); the remove button gets
    /// `id == "<id>-remove"`.
    public let id: String?
    public let onRemove: EventHandler?
    public init(_ label: String, variant: Variant = .solid, removable: Bool = false, clickable: Bool = false,
                count: Int? = nil, icon: IconName? = nil,
                id: String? = nil, onRemove: EventHandler? = nil) {
        self.label = label; self.variant = variant; self.removable = removable
        self.clickable = clickable; self.count = count; self.icon = icon
        self.id = id; self.onRemove = onRemove
    }

    public func render() -> String {
        var classes = ["tag", variant.rawValue]
        if clickable { classes.append("tag--clickable") }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onRemove) } ?? ""
        let removeID = id.map { Tag.escAttr("id", "\($0)-remove") } ?? ""
        var html = Tag.begin("span", Tag.classes(classes), rootAttrs)
        if let icon { html += Tag.element("span", [Tag.classes(["tag__icon"])], WebUIIcon(icon, size: .small).render()) }
        html += Tag.element("span", [Tag.classes(["tag__label"])], htmlEscape(label))
        if let count { html += Tag.element("span", [Tag.classes(["tag__count"])], "\(count)") }
        if removable { html += Tag.element("button", [Tag.classes(["tag__remove"]), removeID, Tag.escAttr("aria-label", "Remove \(htmlEscape(label))")], "×") }
        html += Tag.end("span")
        return html
    }
}

// MARK: WebUI Chip Input
/// a chip-in-array input.
public struct WebUIChipInput: View {
    public let chips: [String]
    public let placeholder: String
    /// stable id; when set with `onChange` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); each remove button gets
    /// `id == "<id>-chip-<index>"`.
    public let id: String?
    public let onChange: EventHandler?
    public init(chips: [String], placeholder: String = "Type and press enter…",
                id: String? = nil, onChange: EventHandler? = nil) {
        self.chips = chips; self.placeholder = placeholder
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["chip-input"]), rootAttrs)
        for (i, chip) in chips.enumerated() {
            let removeID = id.map { Tag.escAttr("id", "\($0)-chip-\(i)") } ?? ""
            html += Tag.begin("span", Tag.classes(["chip chip--sm chip--primary"]))
            html += htmlEscape(chip)
            html += Tag.element("button", [Tag.classes(["chip__remove"]), removeID, Tag.attr("aria-label", "Remove")], "×")
            html += Tag.end("span")
        }
        html += Tag.void("input", Tag.attr("type", "text"), Tag.escAttr("placeholder", placeholder))
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Card Input
/// a payment-card input with brand detection and preview.
public struct WebUICardInput: View {
    public enum Brand: String, Sendable { case visa = " card-input__brand-icon--visa", mc = " card-input__brand-icon--mc", amex = " card-input__brand-icon--amex" }
    public let number: String
    public let holder: String
    public let brand: Brand?
    public init(number: String, holder: String, brand: Brand? = nil) { self.number = number; self.holder = holder; self.brand = brand }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["card-input"]))
        html += Tag.begin("div", Tag.classes(["card-input__row"]))
        html += Tag.begin("div", Tag.classes(["card-input__preview"]))
        html += Tag.element("span", [Tag.classes(["card-input__chip"])], "")
        html += Tag.element("span", [Tag.classes(["card-input__number"])], htmlEscape(number))
        html += Tag.element("span", [Tag.classes(["card-input__holder"])], htmlEscape(holder))
        if let brand { html += Tag.element("span", [Tag.classes(["card-input__brand-icon", brand.rawValue])], "") }
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["card-input__row"]))
        html += Tag.begin("div", Tag.classes(["card-input__field"]))
        html += Tag.element("label", [], "Card number")
        html += Tag.void("input", Tag.classes(["input"]), Tag.escAttr("value", number))
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["card-input__row"]))
        html += Tag.begin("div", Tag.classes(["card-input__field"]))
        html += Tag.element("label", [], "Card holder")
        html += Tag.void("input", Tag.classes(["input"]), Tag.escAttr("value", holder))
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Input Group
/// an input with affixes inside one field box: a leading glyph, a leading text
/// (currency, protocol) and a trailing text (unit, domain, or the error note).
/// the sheet styles the container as `input--with-affix` around a bare
/// `input__el`, so the box, focus ring and state colours come from the shared
/// `.input` rules rather than a parallel set.
public struct WebUIInputGroup: View {
    public let placeholder: String
    /// text before the field. rendered in the muted prefix tone.
    public let prefix: String?
    /// glyph before the field, rendered outside the input itself.
    public let icon: IconName?
    /// text after the field. turns danger-coloured in the error state.
    public let suffix: String?
    public let type: InputType
    public let state: WebUIInput.State
    public let name: String?
    public let id: String?
    public let value: String?
    public let disabled: Bool

    public init(
        placeholder: String = "",
        prefix: String? = nil,
        icon: IconName? = nil,
        suffix: String? = nil,
        type: InputType = .text,
        state: WebUIInput.State = .normal,
        name: String? = nil,
        id: String? = nil,
        value: String? = nil,
        disabled: Bool = false
    ) {
        self.placeholder = placeholder
        self.prefix = prefix
        self.icon = icon
        self.suffix = suffix
        self.type = type
        self.state = state
        self.name = name
        self.id = id
        self.value = value
        self.disabled = disabled
    }

    public func render() -> String {
        var affixClasses = ["input input--with-affix"]
        if !state.rawValue.isEmpty { affixClasses.append(state.rawValue) }
        var html = Tag.begin("div", Tag.classes(affixClasses))
        if let icon {
            html += Tag.element("span", [Tag.classes(["input__affix input__affix--left"])], WebUIIcon(icon, size: .small).render())
        }
        if let prefix {
            html += Tag.element("span", [Tag.classes(["input__prefix"])], htmlEscape(prefix))
        }
        var inputAttrs = Tag.classes(["input__el"]) + Tag.attr("type", type.rawValue)
        if let id { inputAttrs += Tag.escAttr("id", id) }
        if let name { inputAttrs += Tag.escAttr("name", name) }
        inputAttrs += Tag.escAttr("placeholder", placeholder)
        if let value { inputAttrs += Tag.escAttr("value", value) }
        if state == .error { inputAttrs += Tag.attr("aria-invalid", "true") }
        if disabled { inputAttrs += Tag.flag("disabled") }
        html += Tag.void("input", inputAttrs)
        if let suffix {
            let suffixClass = state == .error ? "input__suffix input__suffix--error" : "input__suffix"
            html += Tag.element("span", [Tag.classes([suffixClass])], htmlEscape(suffix))
        }
        html += Tag.end("div")
        return html
    }
}


// MARK: WebUI Field
/// a labelled form row: a label (with an optional required marker, a
/// validation note and a counter on its row) above the control, and helper
/// text below it. the control is whatever the caller passes as content.
public struct WebUIField: View {
    public enum Note: String, Sendable {
        case neutral = ""
        case error = "field__hint--error"
        case success = "field__hint--success"
    }

    public let label: String?
    /// associates the label with the control (`for=`).
    public let controlID: String?
    public let required: Bool
    /// inline note on the label row.
    public let note: String?
    public let noteKind: Note
    /// right-aligned counter on the label row, e.g. "12 / 80".
    public let count: String?
    /// helper text under the control; tinted when `helperIsError`.
    public let helper: String?
    public let helperIsError: Bool
    public let children: [any View]

    public init(
        label: String? = nil,
        controlID: String? = nil,
        required: Bool = false,
        note: String? = nil,
        noteKind: Note = .neutral,
        count: String? = nil,
        helper: String? = nil,
        helperIsError: Bool = false,
        @ViewBuilder content: () -> [any View]
    ) {
        self.label = label
        self.controlID = controlID
        self.required = required
        self.note = note
        self.noteKind = noteKind
        self.count = count
        self.helper = helper
        self.helperIsError = helperIsError
        self.children = content()
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["field"]))
        if label != nil || note != nil || count != nil {
            html += Tag.begin("div", Tag.classes(["field__row"]))
            if let label {
                html += Tag.begin("label", Tag.classes(["field__label", required ? " field__label--required" : ""]), controlID.map { Tag.escAttr("for", $0) } ?? "")
                html += htmlEscape(label)
                html += Tag.end("label")
            }
            if let note {
                var hintClasses = ["field__hint"]
                if !noteKind.rawValue.isEmpty { hintClasses.append(noteKind.rawValue) }
                html += Tag.element("span", [Tag.classes(hintClasses)], htmlEscape(note))
            }
            if let count {
                html += Tag.element("span", [Tag.classes(["field__count"])], htmlEscape(count))
            }
            html += Tag.end("div")
        }
        for child in children { html += child.render() }
        if let helper {
            html += Tag.element("span", [Tag.classes(["field__helper", helperIsError ? " field__helper--error" : ""])], htmlEscape(helper))
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Toggle Group
/// a row of independently toggleable filter chips (several may be active). single-select
/// segmentation is `WebUISegmentedControl`'s shape; this is the filter bar: the
/// sheet's `chip--filter` / `chip--filter-active` pair.
public struct WebUIToggleGroup: View {
    public struct Option: Sendable {
        public let id: String
        public let label: String
        public let selected: Bool
        public init(_ id: String, _ label: String, selected: Bool = false) {
            self.id = id
            self.label = label
            self.selected = selected
        }
    }

    public let options: [Option]
    /// stable container id; when set with `onToggle` the group self-wires and
    /// each chip carries `id + "-opt-<index>"`, so the handler can tell which
    /// chip was clicked from `targetId`.
    public let id: String?
    public let onToggle: EventHandler?

    public init(options: [Option], id: String? = nil, onToggle: EventHandler? = nil) {
        self.options = options
        self.id = id
        self.onToggle = onToggle
    }

    public func render() -> String {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var rootAttrs = Tag.attr("style", "display: flex; flex-wrap: wrap; gap: var(--space-2)")
        if let id { rootAttrs += Tag.escAttr("id", id) }
        rootAttrs += Tag.attr("role", "group")
        rootAttrs += attrs
        var html = Tag.begin("div", rootAttrs)
        for (index, option) in options.enumerated() {
            var cls = ["chip chip--filter"]
            if option.selected { cls.append("chip--filter-active") }
            let chipID = id.map { Tag.escAttr("id", "\($0)-opt-\(index)") } ?? ""
            var chipAttrs = Tag.attr("type", "button") + Tag.classes(cls) + chipID
            if option.selected { chipAttrs += Tag.attr("aria-pressed", "true") }
            html += Tag.begin("button", chipAttrs)
            html += htmlEscape(option.label)
            html += Tag.end("button")
        }
        html += Tag.end("div")
        return html
    }
}
