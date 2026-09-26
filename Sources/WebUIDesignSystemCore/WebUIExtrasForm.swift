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
        let idAttr = inputID.isEmpty ? "" : " id=\"\(inputID)\""
        var html = "<div class=\"slider\(size.rawValue)\(vertical ? " slider--vertical" : "")\">"
        html += "<input type=\"range\" class=\"slider__input\"\(idAttr) min=\"\(min)\" max=\"\(max)\" value=\"\(value)\" aria-valuenow=\"\(value)\"\(inputAttrs)>"
        html += "<div class=\"slider__track\"><div class=\"slider__fill\" style=\"width:\(webuiFixedPoint(pct, places: 2))%\"></div><span class=\"slider__thumb\" style=\"left:\(webuiFixedPoint(pct, places: 2))%\"></span></div>"
        html += "<div class=\"slider__ticks\">"
        for _ in 0..<11 { html += "<span class=\"slider__tick\"></span>" }
        html += "</div>"
        if showLabels {
            html += "<div class=\"slider__labels\"><span>\(htmlEscape(minLabel.isEmpty ? "\(min)" : minLabel))</span><span>\(htmlEscape(maxLabel.isEmpty ? "\(max)" : maxLabel))</span></div>"
        }
        html += "</div>"
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
        var classes = "toggle\(size.rawValue)"
        if labelLeft { classes += " toggle--label-left" }
        if loading { classes += " toggle--loading" }
        if disabled { classes += " toggle--disabled" }
        let inputID = id.map { htmlEscape("\($0)-input") } ?? ""
        let inputAttrs = id.map { controlAttributes(id: "\($0)-input", event: .change, handler: onChange) } ?? ""
        let idAttr = inputID.isEmpty ? "" : " id=\"\(inputID)\""
        var html = "<label class=\"\(classes)\">"
        if labelLeft && !label.isEmpty { html += "<span class=\"toggle__label\">\(htmlEscape(label))</span>" }
        html += "<input type=\"checkbox\" class=\"toggle__input\"\(idAttr)\(checked ? " checked" : "")\(disabled ? " disabled" : "")\(inputAttrs)>"
        html += "<span class=\"toggle__track\"><span class=\"toggle__thumb\"></span></span>"
        if !labelLeft && !label.isEmpty { html += "<span class=\"toggle__label\">\(htmlEscape(label))</span>" }
        html += "</label>"
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
        let decID = id.map { " id=\"\(htmlEscape("\($0)-dec"))\"" } ?? ""
        let incID = id.map { " id=\"\(htmlEscape("\($0)-inc"))\"" } ?? ""
        var html = "<div class=\"stepper\(size.rawValue)\"\(attrs) role=\"group\" aria-label=\"Stepper\">"
        html += "<button class=\"stepper__btn\"\(decID) aria-label=\"Decrease\">−</button>"
        html += "<span class=\"stepper__value\">\(value)</span>"
        html += "<button class=\"stepper__btn\"\(incID) aria-label=\"Increase\">+</button>"
        html += "</div>"
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
        var html = "<div class=\"otp\(size.rawValue)\(error ? " otp--error" : "")\" aria-label=\"One-time code\">"
        for i in 0..<length {
            let filled = (value != nil && i < value!.count)
            let cellID = id.map { " id=\"\(htmlEscape("\($0)-cell-\(i)"))\"" } ?? ""
            let cellAttrs = id.map { controlAttributes(id: "\($0)-cell-\(i)", event: .input, handler: onChange) } ?? ""
            html += "<input class=\"otp__cell\(filled ? " otp__cell--filled" : "")\(i == (value?.count ?? 0) ? " otp__cell--active" : "")\"\(cellID) type=\"text\" inputmode=\"numeric\" maxlength=\"1\" value=\"\(filled ? "\(value![i])" : "")\" aria-label=\"Digit \(i + 1)\"\(cellAttrs)>"
        }
        html += "</div>"
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
        var html = "<div class=\"mfa\">"
        html += "<div class=\"mfa__qr\"><div class=\"qr\"><div class=\"qr__code\">"
        for _ in 0..<(11 * 11) { html += "<span class=\"qr__cell\"></span>" }
        html += "</div></div></div>"
        html += "<div class=\"mfa__steps\"><div class=\"mfa__step\"><span class=\"mfa__step-label\">Scan</span></div><div class=\"mfa__step mfa__step--current\"><span class=\"mfa__step-label\">Enter code</span></div><div class=\"mfa__step\"><span class=\"mfa__step-label\">Verify</span></div></div>"
        html += "<div class=\"mfa__code\">"
        for i in 0..<6 {
            html += "<span class=\"mfa__digit\">\(i < 2 ? "•" : "·")</span>"
        }
        html += "</div>"
        if !recoveryCodes.isEmpty {
            html += "<div class=\"mfa__recovery\">"
            for r in recoveryCodes { html += "<div class=\"mfa__recovery-item\">\(htmlEscape(r.code))</div>" }
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"recurrence\"\(rootAttrs)>"
        html += "<div class=\"recurrence__options\">"
        for (i, opt) in options.enumerated() {
            let chipID = id.map { " id=\"\(htmlEscape("\($0)-chip-\(i)"))\"" } ?? ""
            html += "<button class=\"recurrence__chip\(opt.active ? " recurrence__chip--active" : "")\"\(chipID)>\(htmlEscape(opt.label))</button>"
        }
        html += "</div>"
        html += "<div class=\"recurrence__days\">"
        for (i, d) in days.enumerated() {
            let dayID = id.map { " id=\"\(htmlEscape("\($0)-day-\(i)"))\"" } ?? ""
            html += "<button class=\"recurrence__day\(i < 5 ? " recurrence__day--active" : "")\"\(dayID)>\(htmlEscape(d))</button>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"multiselect\"\(rootAttrs)>"
        html += "<button class=\"multiselect__trigger\">"
        if sel.isEmpty {
            html += "<span class=\"multiselect__placeholder\">\(htmlEscape(placeholder))</span>"
        } else {
            for s in sel { html += "<span class=\"chip chip--sm\">\(htmlEscape(s.label))</span>" }
            if sel.count > 2 { html += "<span class=\"multiselect__more\">+\(sel.count - 2)</span>" }
        }
        html += "<span class=\"multiselect__chevron\">▾</span></button>"
        html += "<div class=\"multiselect__panel\"><div class=\"multiselect__search\"><input type=\"search\" placeholder=\"Filter…\"></div>"
        for (i, option) in options.enumerated() {
            let optID = id.map { " id=\"\(htmlEscape("\($0)-opt-\(i)"))\"" } ?? ""
            html += "<div class=\"multiselect__option\(option.selected ? " multiselect__option--selected" : "")\"\(optID)>\(htmlEscape(option.label))</div>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"validation\(state.rawValue)\" role=\"status\">"
        html += "<span class=\"validation__icon\" aria-hidden=\"true\">\(state == .success ? "✓" : (state == .warning ? "!" : "✗"))</span>"
        html += "<span class=\"validation__text\">\(htmlEscape(message))</span>"
        html += "</div>"
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
        var html = "<div class=\"dropzone\(hover ? " dropzone--hover" : "")\" role=\"button\" tabindex=\"0\">"
        html += "<div class=\"file-drop__icon\" aria-hidden=\"true\">⇪</div>"
        html += "<div class=\"file-drop__title\">\(htmlEscape(title))</div>"
        if !hint.isEmpty { html += "<div class=\"file-drop__hint\">\(htmlEscape(hint))</div>" }
        html += "<input type=\"file\" style=\"display:none\">"
        html += "</div>"
        return html
    }
}

// MARK: WebUI Signature
/// a signature capture pad.
public struct WebUISignature: View {
    public let label: String
    public init(_ label: String = "Sign here") { self.label = label }

    public func render() -> String {
        var html = "<div class=\"sigpad\">"
        html += "<div class=\"sigpad__canvas\" role=\"img\" aria-label=\"\(htmlEscape(label))\"></div>"
        html += "<div class=\"sigpad__tools\"><button class=\"button button--ghost button--sm\">Clear</button></div>"
        html += "</div>"
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
        let saveID = id.map { " id=\"\(htmlEscape("\($0)-save"))\"" } ?? ""
        let cancelID = id.map { " id=\"\(htmlEscape("\($0)-cancel"))\"" } ?? ""
        var html = "<div class=\"inline-edit\(state.rawValue)\(error ? " inline-edit--error" : "")\"\(rootAttrs)>"
        html += "<div class=\"inline-edit__value\">\(htmlEscape(value))<span class=\"inline-edit__pencil\" aria-hidden=\"true\">✎</span></div>"
        if state == .editing {
            html += "<div class=\"inline-edit__editing\"><input class=\"inline-edit__input\(error ? " inline-edit__input--error" : "")\" value=\"\(htmlEscape(value))\">"
            html += "<div class=\"inline-edit__actions\"><button class=\"inline-edit__check\"\(saveID) aria-label=\"Save\">✓</button><button class=\"inline-edit__pencil\"\(cancelID) aria-label=\"Cancel\">✕</button></div></div>"
        }
        html += "</div>"
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
        var html = "<div class=\"masked\">"
        if let prefix { html += "<span class=\"masked__prefix\">\(htmlEscape(prefix))</span>" }
        html += "<input type=\"text\" value=\"\(htmlEscape(display))\" aria-label=\"masked value\">"
        html += "<span class=\"masked__caret\" aria-hidden=\"true\"></span>"
        html += "</div>"
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
        var classes = "rating\(size.rawValue)"
        if heart { classes += " rating--heart" }
        if full > 0 { classes += " rating--filled" }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = "<div class=\"\(classes)\"\(rootAttrs) role=\"img\" aria-label=\"\(value) of \(max)\">"
        for i in 1...max {
            let glyph = heart ? "♥" : "★"
            let filled = i <= full
            let starID = id.map { " id=\"\(htmlEscape("\($0)-star-\(i)"))\"" } ?? ""
            html += "<span class=\"rating__star\(filled ? " rating__star--filled" : "")\"\(starID) aria-hidden=\"true\">\(glyph)</span>"
        }
        if showValue { html += "<span class=\"rating__value\">\(value)</span>" }
        html += "</div>"
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
        var classes = "tag\(variant.rawValue)"
        if clickable { classes += " tag--clickable" }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onRemove) } ?? ""
        let removeID = id.map { " id=\"\(htmlEscape("\($0)-remove"))\"" } ?? ""
        var html = "<span class=\"\(classes)\"\(rootAttrs)>"
        if let icon { html += "<span class=\"tag__icon\">\(WebUIIcon(icon, size: .small).render())</span>" }
        html += "<span class=\"tag__label\">\(htmlEscape(label))</span>"
        if let count { html += "<span class=\"tag__count\">\(count)</span>" }
        if removable { html += "<button class=\"tag__remove\"\(removeID) aria-label=\"Remove \(htmlEscape(label))\">×</button>" }
        html += "</span>"
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
        var html = "<div class=\"chip-input\"\(rootAttrs)>"
        for (i, chip) in chips.enumerated() {
            let removeID = id.map { " id=\"\(htmlEscape("\($0)-chip-\(i)"))\"" } ?? ""
            html += "<span class=\"chip chip--sm chip--primary\">\(htmlEscape(chip))<button class=\"chip__remove\"\(removeID) aria-label=\"Remove\">×</button></span>"
        }
        html += "<input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\">"
        html += "</div>"
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
        var html = "<div class=\"card-input\">"
        html += "<div class=\"card-input__row\"><div class=\"card-input__preview\"><span class=\"card-input__chip\"></span><span class=\"card-input__number\">\(htmlEscape(number))</span><span class=\"card-input__holder\">\(htmlEscape(holder))</span>"
        if let brand { html += "<span class=\"card-input__brand-icon\(brand.rawValue)\"></span>" }
        html += "</div></div>"
        html += "<div class=\"card-input__row\"><div class=\"card-input__field\"><label>Card number</label><input class=\"input\" value=\"\(htmlEscape(number))\"></div></div>"
        html += "<div class=\"card-input__row\"><div class=\"card-input__field\"><label>Card holder</label><input class=\"input\" value=\"\(htmlEscape(holder))\"></div></div>"
        html += "</div>"
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
        var html = "<div class=\"input input--with-affix"
        if !state.rawValue.isEmpty { html += " \(state.rawValue)" }
        html += "\">"
        if let icon {
            html += "<span class=\"input__affix input__affix--left\">" + WebUIIcon(icon, size: .small).render() + "</span>"
        }
        if let prefix {
            html += "<span class=\"input__prefix\">\(htmlEscape(prefix))</span>"
        }
        html += "<input class=\"input__el\" type=\"\(type.rawValue)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        html += " placeholder=\"\(htmlEscape(placeholder))\""
        if let value { html += " value=\"\(htmlEscape(value))\"" }
        if state == .error { html += " aria-invalid=\"true\"" }
        if disabled { html += " disabled" }
        html += ">"
        if let suffix {
            let suffixClass = state == .error ? "input__suffix input__suffix--error" : "input__suffix"
            html += "<span class=\"\(suffixClass)\">\(htmlEscape(suffix))</span>"
        }
        html += "</div>"
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
        var html = "<div class=\"field\">"
        if label != nil || note != nil || count != nil {
            html += "<div class=\"field__row\">"
            if let label {
                html += "<label class=\"field__label\(required ? " field__label--required" : "")\""
                if let controlID { html += " for=\"\(htmlEscape(controlID))\"" }
                html += ">\(htmlEscape(label))</label>"
            }
            if let note {
                html += "<span class=\"field__hint\(noteKind.rawValue.isEmpty ? "" : " " + noteKind.rawValue)\">\(htmlEscape(note))</span>"
            }
            if let count {
                html += "<span class=\"field__count\">\(htmlEscape(count))</span>"
            }
            html += "</div>"
        }
        for child in children { html += child.render() }
        if let helper {
            html += "<span class=\"field__helper\(helperIsError ? " field__helper--error" : "")\">\(htmlEscape(helper))</span>"
        }
        html += "</div>"
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
        var html = "<div style=\"display: flex; flex-wrap: wrap; gap: var(--space-2)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += " role=\"group\"\(attrs)>"
        for (index, option) in options.enumerated() {
            var cls = "chip chip--filter"
            if option.selected { cls += " chip--filter-active" }
            let chipID = id.map { " id=\"\(htmlEscape("\($0)-opt-\(index)"))\"" } ?? ""
            html += "<button type=\"button\" class=\"\(cls)\"\(chipID)"
            if option.selected { html += " aria-pressed=\"true\"" }
            html += ">\(htmlEscape(option.label))</button>"
        }
        html += "</div>"
        return html
    }
}
