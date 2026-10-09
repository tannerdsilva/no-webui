import WebUICore

// ============================================================================
// MARK: - Forms & input extras
// ============================================================================

// MARK: WebUI Slider
/// a range slider with fill, thumb, ticks, and labels.
public struct WebUISlider: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let value: Double
    public let min: Double
    public let max: Double
    public let size: ControlSize
    public let vertical: Bool
    public let showLabels: Bool
    public let minLabel: String
    public let maxLabel: String
    /// stable id; when set with `onChange` the range input self-wires
    /// (`targetId == "<id>-input"`, event `.input`).
    public let id: String?
    public let onChange: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " slider--sm"
            case .md: return ""
            case .lg: return " slider--lg"
            case .xl: return " slider--xl"
        }
    }

    public init(_ value: Double, min: Double = 0, max: Double = 100, size: ControlSize = .md,
                vertical: Bool = false, showLabels: Bool = false, minLabel: String = "", maxLabel: String = "",
                id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.min = min; self.max = max; self.size = size
        self.vertical = vertical; self.showLabels = showLabels; self.minLabel = minLabel; self.maxLabel = maxLabel
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let range = Swift.max(self.max - self.min, 1e-9)
        let pct = Swift.min(Swift.max((self.max - self.min) / range * 100.0, 0), 100)
        let inputID = id.map { htmlEscape("\($0)-input") } ?? ""
        let inputAttrs = id.map { controlAttributes(id: "\($0)-input", event: .input, handler: onChange) } ?? ""
        let idAttr = inputID.isEmpty ? "" : " id=\"\(inputID)\""
        var html = "<div class=\"slider\(Self.classFor(size))\(vertical ? " slider--vertical" : "")\">"
        html += "<input type=\"range\" class=\"slider__input\"\(idAttr) min=\"\(min)\" max=\"\(max)\" value=\"\(value)\"" + Aria.valuenowDouble(value).render() + "\(inputAttrs)>"
        html += "<div class=\"slider__track\"><div class=\"slider__fill\" style=\"width:\(webuiFixedPoint(pct, places: 2))%\"></div><span class=\"slider__thumb\" style=\"left:\(webuiFixedPoint(pct, places: 2))%\"></span></div>"
        html += "<div class=\"slider__ticks\">"
        for _ in 0..<11 { html += "<span class=\"slider__tick\"></span>" }
        html += "</div>"
        if showLabels {
            html += "<div class=\"slider__labels\"><span>\(htmlEscape(minLabel.isEmpty ? "\(min)" : minLabel))</span><span>\(htmlEscape(maxLabel.isEmpty ? "\(max)" : maxLabel))</span></div>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Toggle
/// a switch control with label.
public struct WebUIToggle: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let label: String
    public let checked: Bool
    public let size: ControlSize
    public let labelLeft: Bool
    public let loading: Bool
    public let disabled: Bool
    /// stable id; when set with `onChange` the checkbox input self-wires
    /// (`targetId == "<id>-input"`, event `.change`).
    public let id: String?
    public let onChange: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " toggle--sm"
            case .md: return ""
            case .lg: return " toggle--lg"
            case .xl: return " toggle--xl"
        }
    }

    public init(_ label: String = "", checked: Bool = false, size: ControlSize = .md,
                labelLeft: Bool = false, loading: Bool = false, disabled: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.label = label; self.checked = checked; self.size = size
        self.labelLeft = labelLeft; self.loading = loading; self.disabled = disabled
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        var classes = "toggle\(Self.classFor(size))"
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
        buffer.append(html)
    }
}

// MARK: WebUI Stepper
/// a numeric stepper with +/− buttons.
public struct WebUIStepper: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let value: Int
    public let size: ControlSize
    /// stable container id; when set with `onChange` the +/− buttons
    /// self-wire (`targetId == "<id>-inc" | "<id>-dec"`).
    public let id: String?
    public let onChange: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " stepper--sm"
            case .md: return ""
            case .lg: return " stepper--lg"
            case .xl: return " stepper--xl"
        }
    }

    public init(_ value: Int, size: ControlSize = .md, id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.size = size; self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onChange {
            attrs = controlAttributes(id: id, event: .click, handler: onChange)
        } else {
            attrs = ""
        }
        let decID = id.map { " id=\"\(htmlEscape("\($0)-dec"))\"" } ?? ""
        let incID = id.map { " id=\"\(htmlEscape("\($0)-inc"))\"" } ?? ""
        var html = "<div class=\"stepper\(Self.classFor(size))\"\(attrs)" + Aria.attributes([.label(RenderContext.currentStrings.stepper)], role: .group) + ">"
        html += "<button class=\"stepper__btn\"\(decID)" + Aria.label(RenderContext.currentStrings.decrease).render() + ">−</button>"
        html += "<span class=\"stepper__value\">\(value)</span>"
        html += "<button class=\"stepper__btn\"\(incID)" + Aria.label(RenderContext.currentStrings.increase).render() + ">+</button>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI OTP
/// a one-time-code input with per-digit cells.
public struct WebUIOTP: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let length: Int
    public let value: [Int]?
    public let size: ControlSize
    public let error: Bool
    /// stable id; when set with `onChange` each digit cell self-wires
    /// (`targetId == "<id>-cell-<index>"`, event `.input`).
    public let id: String?
    public let onChange: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " otp--sm"
            case .md: return ""
            case .lg: return " otp--lg"
            case .xl: return " otp--xl"
        }
    }

    public init(length: Int = 6, value: [Int]? = nil, size: ControlSize = .md, error: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.length = length; self.value = value; self.size = size; self.error = error
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let digits = value ?? []
        var html = "<div class=\"otp\(Self.classFor(size))\(error ? " otp--error" : "")\"" + Aria.label(RenderContext.currentStrings.oneTimeCode).render() + ">"
        for i in 0..<length {
            let filled = i < digits.count
            let cellID = id.map { " id=\"\(htmlEscape("\($0)-cell-\(i)"))\"" } ?? ""
            let cellAttrs = id.map { controlAttributes(id: "\($0)-cell-\(i)", event: .input, handler: onChange) } ?? ""
            html += "<input class=\"otp__cell\(filled ? " otp__cell--filled" : "")\(i == digits.count ? " otp__cell--active" : "")\"\(cellID) type=\"text\" inputmode=\"numeric\" maxlength=\"1\" value=\"\(filled ? "\(digits[i])" : "")\"\"" + Aria.label(RenderContext.currentStrings.digit(i + 1)).render() + "\(cellAttrs)>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI MFA
/// a multi-factor auth flow: QR, steps, recovery codes.
public struct WebUIMFA: View {
    public struct Recovery: Sendable { public let code: String
        public init(_ code: String) { self.code = code } }
    public let recoveryCodes: [Recovery]
    public init(recoveryCodes: [Recovery] = []) { self.recoveryCodes = recoveryCodes }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"mfa\">"
        html += "<div class=\"mfa__qr\"><div class=\"qr\"><div class=\"qr__code\">"
        for _ in 0..<(11 * 11) { html += "<span class=\"qr__cell\"></span>" }
        html += "</div></div></div>"
        html += "<div class=\"mfa__steps\"><div class=\"mfa__step\"><span class=\"mfa__step-label\">\(RenderContext.currentStrings.scan)</span></div><div class=\"mfa__step mfa__step--current\"><span class=\"mfa__step-label\">\(RenderContext.currentStrings.enterCode)</span></div><div class=\"mfa__step\"><span class=\"mfa__step-label\">\(RenderContext.currentStrings.verify)</span></div></div>"
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
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
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
        buffer.append(html)
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
    public init(options: [Option], placeholder: String = WebUIStrings.english.select,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.options = options; self.placeholder = placeholder
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
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
        html += "<div class=\"multiselect__panel\"><div class=\"multiselect__search\"><input type=\"search\" placeholder=\"\(RenderContext.currentStrings.filter)\"></div>"
        for (i, option) in options.enumerated() {
            let optID = id.map { " id=\"\(htmlEscape("\($0)-opt-\(i)"))\"" } ?? ""
            html += "<div class=\"multiselect__option\(option.selected ? " multiselect__option--selected" : "")\"\(optID)>\(htmlEscape(option.label))</div>"
        }
        html += "</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Validation
/// an inline validation message.
public struct WebUIValidation: View {
    @available(*, deprecated, renamed: "ValidationState")
    public typealias State = ValidationState

    public let message: String
    public let state: ValidationState

    /// this component's own class for a shared validation state — `none` maps to
    /// the empty string, the base surface.
    private static func classFor(_ state: ValidationState) -> String {
        switch state {
            case .none: return ""
            case .success: return " validation--success"
            case .warning: return " validation--warning"
            case .error: return " validation--error"
        }
    }

    /// a state's glyph. `none` renders nothing — an untouched field has no verdict.
    private static func icon(for state: ValidationState) -> String {
        switch state {
            case .none: return ""
            case .success: return "✓"
            case .warning: return "!"
            case .error: return "✗"
        }
    }

    public init(_ message: String, state: ValidationState = .error) { self.message = message; self.state = state }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"validation\(Self.classFor(state))\"" + AriaRole.status.render() + ">"
        html += "<span class=\"validation__icon\"" + Aria.hidden(.yes).render() + ">\(Self.icon(for: state))</span>"
        html += "<span class=\"validation__text\">\(htmlEscape(message))</span>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Drop Zone
/// a drag-and-drop file target.
public struct WebUIDropZone: View {
    public let title: String
    public let hint: String
    public let hover: Bool
    public init(_ title: String, hint: String = "", hover: Bool = false) { self.title = title; self.hint = hint; self.hover = hover }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"dropzone\(hover ? " dropzone--hover" : "")\"" + AriaRole.button.render() + " tabindex=\"0\">"
        html += "<div class=\"file-drop__icon\"" + Aria.hidden(.yes).render() + ">⇪</div>"
        html += "<div class=\"file-drop__title\">\(htmlEscape(title))</div>"
        if !hint.isEmpty { html += "<div class=\"file-drop__hint\">\(htmlEscape(hint))</div>" }
        html += "<input type=\"file\" style=\"display:none\">"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Signature
/// a signature capture pad.
public struct WebUISignature: View {
    public let label: String
    public init(_ label: String = WebUIStrings.english.signHere) { self.label = label }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"sigpad\">"
        html += "<div class=\"sigpad__canvas\"" + Aria.attributes([.label(label)], role: .img) + "></div>"
        html += "<div class=\"sigpad__tools\"><button class=\"button button--ghost button--sm\">\(RenderContext.currentStrings.clear)</button></div>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Inline Edit
/// an editable inline value with idle/editing/saved states.
public struct WebUIInlineEdit: View {
    @available(*, deprecated, renamed: "EditState")
    public typealias State = EditState

    public let value: String
    public let state: EditState
    public let error: Bool
    /// stable id; when set with `onSave` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); the save button gets
    /// `id == "<id>-save"` and cancel `<id>-cancel`.
    public let id: String?
    public let onSave: EventHandler?

    /// this component's own class for a shared edit state — same three values,
    /// same bytes.
    private static func classFor(_ state: EditState) -> String {
        switch state {
            case .idle: return " inline-edit--idle"
            case .editing: return " inline-edit--editing"
            case .saved: return " inline-edit--saved"
        }
    }

    public init(_ value: String, state: EditState = .idle, error: Bool = false,
                id: String? = nil, onSave: EventHandler? = nil) {
        self.value = value; self.state = state; self.error = error
        self.id = id; self.onSave = onSave
    }

    public func render(into buffer: inout HTMLBuffer) {
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onSave) } ?? ""
        let saveID = id.map { " id=\"\(htmlEscape("\($0)-save"))\"" } ?? ""
        let cancelID = id.map { " id=\"\(htmlEscape("\($0)-cancel"))\"" } ?? ""
        var html = "<div class=\"inline-edit\(Self.classFor(state))\(error ? " inline-edit--error" : "")\"\(rootAttrs)>"
        html += "<div class=\"inline-edit__value\">\(htmlEscape(value))<span class=\"inline-edit__pencil\"" + Aria.hidden(.yes).render() + ">✎</span></div>"
        if state == .editing {
            html += "<div class=\"inline-edit__editing\"><input class=\"inline-edit__input\(error ? " inline-edit__input--error" : "")\" value=\"\(htmlEscape(value))\">"
            html += "<div class=\"inline-edit__actions\"><button class=\"inline-edit__check\"\(saveID)" + Aria.label(RenderContext.currentStrings.save).render() + ">✓</button><button class=\"inline-edit__pencil\"\(cancelID)" + Aria.label(RenderContext.currentStrings.cancel).render() + ">✕</button></div></div>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Masked
/// a masked input with a prefix marker.
public struct WebUIMasked: View {
    public let value: String
    public let prefix: String?
    public let masked: Bool
    public init(_ value: String, prefix: String? = nil, masked: Bool = true) { self.value = value; self.prefix = prefix; self.masked = masked }

    public func render(into buffer: inout HTMLBuffer) {
        let display = masked ? String(repeating: "•", count: value.count) : value
        var html = "<div class=\"masked\">"
        if let prefix { html += "<span class=\"masked__prefix\">\(htmlEscape(prefix))</span>" }
        html += "<input type=\"text\" value=\"\(htmlEscape(display))\"" + Aria.label(RenderContext.currentStrings.maskedValue).render() + ">"
        html += "<span class=\"masked__caret\"" + Aria.hidden(.yes).render() + "></span>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Rating
/// a star rating.
public struct WebUIRating: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let value: Double
    public let max: Int
    public let size: ControlSize
    public let heart: Bool
    public let showValue: Bool
    /// stable id; when set with `onChange` the root div self-wires
    /// (`targetId == "<id>"`, event `.click`); each star gets
    /// `id == "<id>-star-<index>"` (1-based).
    public let id: String?
    public let onChange: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " rating--sm"
            case .md: return ""
            case .lg: return " rating--lg"
            case .xl: return " rating--xl"
        }
    }

    public init(_ value: Double, max: Int = 5, size: ControlSize = .md, heart: Bool = false, showValue: Bool = false,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.value = value; self.max = max; self.size = size; self.heart = heart; self.showValue = showValue
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let full = Int(value)
        var classes = "rating\(Self.classFor(size))"
        if heart { classes += " rating--heart" }
        if full > 0 { classes += " rating--filled" }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = "<div class=\"\(classes)\"\(rootAttrs)" + Aria.attributes([.label(RenderContext.currentStrings.ratingValue(value, max))], role: .img) + ">"
        for i in 1...max {
            let glyph = heart ? "♥" : "★"
            let filled = i <= full
            let starID = id.map { " id=\"\(htmlEscape("\($0)-star-\(i)"))\"" } ?? ""
            html += "<span class=\"rating__star\(filled ? " rating__star--filled" : "")\"\(starID)" + Aria.hidden(.yes).render() + ">\(glyph)</span>"
        }
        if showValue { html += "<span class=\"rating__value\">\(value)</span>" }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Tag
/// an inline tag/label.
public struct WebUITag: View {
    /// the tag's ONE appearance axis — eight discrete named appearances whose
    /// sheet classes CONFLICT (they set the same `background`/`border-color`/
    /// `color` properties), so there is nothing to split along. renamed from
    /// `Variant`.
    public enum Appearance: String, Sendable { case solid = " tag--solid", outlined = " tag--outlined", ghost = " tag--ghost",
        primary = " tag--primary", success = " tag--success", warning = " tag--warning", danger = " tag--danger", info = " tag--info" }

    @available(*, deprecated, renamed: "Appearance")
    public typealias Variant = Appearance

    public let label: String
    public let appearance: Appearance
    public let removable: Bool
    public let clickable: Bool
    public let count: Int?
    public let icon: IconName?
    /// stable id; when set with `onRemove` the root span self-wires
    /// (`targetId == "<id>"`, event `.click`); the remove button gets
    /// `id == "<id>-remove"`.
    public let id: String?
    public let onRemove: EventHandler?
    public init(_ label: String, appearance: Appearance = .solid, removable: Bool = false, clickable: Bool = false,
                count: Int? = nil, icon: IconName? = nil,
                id: String? = nil, onRemove: EventHandler? = nil) {
        self.label = label; self.appearance = appearance; self.removable = removable
        self.clickable = clickable; self.count = count; self.icon = icon
        self.id = id; self.onRemove = onRemove
    }

    /// the 1.x initializer. required (no default) so it discriminates from the
    /// `appearance:` one; forwards so a 1.x call site keeps compiling byte-identically.
    @available(*, deprecated, message: "use appearance: — the members are the tag's one appearance axis")
    public init(_ label: String, variant: Appearance, removable: Bool = false, clickable: Bool = false,
                count: Int? = nil, icon: IconName? = nil,
                id: String? = nil, onRemove: EventHandler? = nil) {
        self.init(label, appearance: variant, removable: removable, clickable: clickable,
                  count: count, icon: icon, id: id, onRemove: onRemove)
    }

    public func render(into buffer: inout HTMLBuffer) {
        var classes = "tag\(appearance.rawValue)"
        if clickable { classes += " tag--clickable" }
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onRemove) } ?? ""
        let removeID = id.map { " id=\"\(htmlEscape("\($0)-remove"))\"" } ?? ""
        var html = "<span class=\"\(classes)\"\(rootAttrs)>"
        if let icon { html += "<span class=\"tag__icon\">\(WebUIIcon(icon, size: .small).renderThroughBuffer())</span>" }
        html += "<span class=\"tag__label\">\(htmlEscape(label))</span>"
        if let count { html += "<span class=\"tag__count\">\(count)</span>" }
        if removable { html += "<button class=\"tag__remove\"\(removeID)" + Aria.label(RenderContext.currentStrings.removeItem(label)).render() + ">×</button>" }
        html += "</span>"
        buffer.append(html)
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
    public init(chips: [String], placeholder: String = WebUIStrings.english.typeAndPressEnter,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.chips = chips; self.placeholder = placeholder
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let rootAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = "<div class=\"chip-input\"\(rootAttrs)>"
        for (i, chip) in chips.enumerated() {
            let removeID = id.map { " id=\"\(htmlEscape("\($0)-chip-\(i)"))\"" } ?? ""
            html += "<span class=\"chip chip--sm chip--primary\">\(htmlEscape(chip))<button class=\"chip__remove\"\(removeID)" + Aria.label(RenderContext.currentStrings.remove).render() + ">×</button></span>"
        }
        html += "<input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\">"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Card Input
/// a payment-card input with brand detection and preview.
public struct WebUICardInput: View {
    @available(*, deprecated, renamed: "WebUIDesignSystemCore.Brand")
    public typealias Brand = WebUIDesignSystemCore.Brand

    public let number: String
    public let holder: String
    public let brand: WebUIDesignSystemCore.Brand?

    /// this component's own class for a shared brand — the 1.x raw values were
    /// class fragments, so the map carries them; `discover` forwards the pattern.
    private static func classFor(_ brand: WebUIDesignSystemCore.Brand) -> String {
        switch brand {
            case .visa: return " card-input__brand-icon--visa"
            case .mc: return " card-input__brand-icon--mc"
            case .amex: return " card-input__brand-icon--amex"
            case .discover: return " card-input__brand-icon--discover"
        }
    }

    public init(number: String, holder: String, brand: WebUIDesignSystemCore.Brand? = nil) { self.number = number; self.holder = holder; self.brand = brand }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"card-input\">"
        html += "<div class=\"card-input__row\"><div class=\"card-input__preview\"><span class=\"card-input__chip\"></span><span class=\"card-input__number\">\(htmlEscape(number))</span><span class=\"card-input__holder\">\(htmlEscape(holder))</span>"
        if let brand { html += "<span class=\"card-input__brand-icon\(Self.classFor(brand))\"></span>" }
        html += "</div></div>"
        html += "<div class=\"card-input__row\"><div class=\"card-input__field\"><label>\(RenderContext.currentStrings.cardNumber)</label><input class=\"input\" value=\"\(htmlEscape(number))\"></div></div>"
        html += "<div class=\"card-input__row\"><div class=\"card-input__field\"><label>\(RenderContext.currentStrings.cardHolder)</label><input class=\"input\" value=\"\(htmlEscape(holder))\"></div></div>"
        html += "</div>"
        buffer.append(html)
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
    public let state: ValidationState
    public let name: String?
    public let id: String?
    public let value: String?
    public let disabled: Bool
    /// the input's accessible name (aria-label) when the caller has no
    /// wrapping <label> to lean on; rendered through the typed aria surface.
    public let ariaLabel: String?

    /// this component's own class for a shared validation state — the sheet's
    /// bytes are unchanged, `none`'s empty string included. (this is why
    /// `WebUIInput.State` resolving to the shared type is not enough by itself:
    /// the raw value stopped being a class fragment, so every reader of it had
    /// to move to a `classFor` map.)
    private static func classFor(_ state: ValidationState) -> String {
        switch state {
            case .none: return ""
            case .success: return "input--success"
            case .warning: return "input--warning"
            case .error: return "input--error"
        }
    }

    public init(
        placeholder: String = "",
        prefix: String? = nil,
        icon: IconName? = nil,
        suffix: String? = nil,
        type: InputType = .text,
        state: ValidationState = .none,
        name: String? = nil,
        id: String? = nil,
        value: String? = nil,
        disabled: Bool = false,
        ariaLabel: String? = nil
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
        self.ariaLabel = ariaLabel
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"input input--with-affix"
        let stateClass = Self.classFor(state)
        if !stateClass.isEmpty { html += " \(stateClass)" }
        html += "\">"
        if let icon {
            html += "<span class=\"input__affix input__affix--left\">" + WebUIIcon(icon, size: .small).renderThroughBuffer() + "</span>"
        }
        if let prefix {
            html += "<span class=\"input__prefix\">\(htmlEscape(prefix))</span>"
        }
        html += "<input class=\"input__el\" type=\"\(type.rawValue)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        if let ariaLabel { html += Aria.label(ariaLabel).render() }
        if let name { html += " name=\"\(htmlEscape(name))\"" }
        html += " placeholder=\"\(htmlEscape(placeholder))\""
        if let value { html += " value=\"\(htmlEscape(value))\"" }
        if state == .error { html += Aria.invalid(true).render() }
        if disabled { html += " disabled" }
        html += ">"
        if let suffix {
            let suffixClass = state == .error ? "input__suffix input__suffix--error" : "input__suffix"
            html += "<span class=\"\(suffixClass)\">\(htmlEscape(suffix))</span>"
        }
        html += "</div>"
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
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
        for child in children { html += child.renderThroughBuffer() }
        if let helper {
            html += "<span class=\"field__helper\(helperIsError ? " field__helper--error" : "")\">\(htmlEscape(helper))</span>"
        }
        html += "</div>"
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var html = "<div style=\"display: flex; flex-wrap: wrap; gap: var(--space-2)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += AriaRole.group.render() + "\(attrs)>"
        for (index, option) in options.enumerated() {
            var cls = "chip chip--filter"
            if option.selected { cls += " chip--filter-active" }
            let chipID = id.map { " id=\"\(htmlEscape("\($0)-opt-\(index)"))\"" } ?? ""
            html += "<button type=\"button\" class=\"\(cls)\"\(chipID)"
            if option.selected { html += Aria.pressed(.yes).render() }
            html += ">\(htmlEscape(option.label))</button>"
        }
        html += "</div>"
        buffer.append(html)
    }
}
