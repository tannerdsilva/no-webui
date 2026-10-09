import WebUICore

// ============================================================================
// MARK: - Comms & social extras
// ============================================================================

// MARK: WebUI Mention
/// an inline @mention chip within text, or a mention suggestion dropdown.
public struct WebUIMention: View {
    public struct Option: Sendable { public let name: String; public let handle: String; public let active: Bool
        public init(_ name: String, handle: String, active: Bool = false) { self.name = name; self.handle = handle; self.active = active } }
    public let text: String
    public let options: [Option]
    public let id: String?
    public let onSelect: EventHandler?
    public init(text: String = "", options: [Option] = [], id: String? = nil, onSelect: EventHandler? = nil) {
        self.text = text; self.options = options; self.id = id; self.onSelect = onSelect
    }

    public func render(into buffer: inout HTMLBuffer) {
            if options.isEmpty {
                buffer.append("<span class=\"mention\">@\(htmlEscape(text))</span>")
                return
            }
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = "<div class=\"mention-dropdown\"\(attrs)>"
        for (i, option) in options.enumerated() {
            html += "<div class=\"mention-option\(option.active ? " mention-option--active" : "")\""
            if let id { html += " id=\"\(htmlEscape(id))-option-\(i)\"" }
            html += "><span class=\"mention-option__avatar\"></span><span class=\"mention-option__name\">\(htmlEscape(option.name))</span><span class=\"mention-option__handle\">\(htmlEscape(option.handle))</span></div>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Reactions
/// an emoji reaction summary with counts.
public struct WebUIReactions: View {
    public struct Reaction: Sendable { public let emoji: String; public let count: Int; public let active: Bool
        public init(_ emoji: String, count: Int = 0, active: Bool = false) { self.emoji = emoji; self.count = count; self.active = active } }
    public let reactions: [Reaction]
    public let id: String?
    public let onChange: EventHandler?
    public init(reactions: [Reaction], id: String? = nil, onChange: EventHandler? = nil) {
        self.reactions = reactions; self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = "<div class=\"reactions\"\(attrs)>"
        for (i, r) in reactions.enumerated() {
            html += "<button class=\"reactions__emoji\(r.active ? " reactions__emoji--active" : "")\""
            if let id { html += " id=\"\(htmlEscape(id))-r-\(i)\"" }
            html += "><span aria-hidden=\"true\">\(htmlEscape(r.emoji))</span><span class=\"reactions__count\">\(r.count)</span></button>"
        }
        html += "<button class=\"reactions__more\" aria-label=\"\(RenderContext.currentStrings.addReaction)\">＋</button>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Typing Indicator
/// an animated typing indicator.
public struct WebUITypingIndicator: View {
    public let inline: Bool
    public init(inline: Bool = false) { self.inline = inline }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"typing\(inline ? " typing--inline" : "")\" role=\"status\" aria-label=\"\(RenderContext.currentStrings.someoneIsTyping)\">"
        html += "<span class=\"typing__dot\"></span><span class=\"typing__dot\"></span><span class=\"typing__dot\"></span>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Notification
/// a notification row within a panel.
public struct WebUINotification: View {
    // measured (W1.4): `Kind` was declared but never referenced — no property, no
    // init parameter, no render use. a vocabulary duplicate with no reader, so it
    // resolves to the shared `Tone` rather than carrying a private case set.
    @available(*, deprecated, renamed: "Tone")
    public typealias Kind = Tone
    public let title: String?
    public let text: String
    public let time: String
    public let read: Bool
    public let icon: IconName?
    public let id: String?
    public let onTap: EventHandler?
    public init(title: String? = nil, text: String, time: String = "", read: Bool = false, icon: IconName? = nil, id: String? = nil, onTap: EventHandler? = nil) {
        self.title = title; self.text = text; self.time = time; self.read = read; self.icon = icon; self.id = id; self.onTap = onTap
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = "<div class=\"notification\(read ? " notification--read" : "")\"\(attrs)>"
        if let icon { html += "<span class=\"notification__icon\">\(WebUIIcon(icon, size: .medium).renderThroughBuffer())</span>" }
        else { html += "<span class=\"notification__icon\"><span class=\"notification__unread\"></span></span>" }
        html += "<div class=\"notification__body\">"
        if let title { html += "<div class=\"notification__title\">\(htmlEscape(title))</div>" }
        html += "<div class=\"notification__text\">\(htmlEscape(text))</div>"
        if !time.isEmpty { html += "<div class=\"notification__time\">\(htmlEscape(time))</div>" }
        html += "</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Toast Stack
/// a stack container for toasts.
public struct WebUIToastStack: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"toast-stack\" aria-live=\"polite\">"
        for c in children { html += c.renderThroughBuffer() }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Bell
/// a notification bell with a badge.
public struct WebUIBell: View {
    public let count: Int
    public let icon: IconName
    public let id: String?
    public let onTap: EventHandler?
    public init(count: Int = 0, icon: IconName = .bell, id: String? = nil, onTap: EventHandler? = nil) {
        self.count = count; self.icon = icon; self.id = id; self.onTap = onTap
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = "<button class=\"bell\"\(attrs) aria-label=\"\(RenderContext.currentStrings.notifications)\(count > 0 ? RenderContext.currentStrings.unreadCount(count) : "")\">"
        html += "<span class=\"bell__icon\">\(WebUIIcon(icon, size: .medium).renderThroughBuffer())</span>"
        if count > 0 { html += "<span class=\"bell__badge\">\(count)</span>" }
        html += "</button>"
        buffer.append(html)
    }
}

// ============================================================================
// MARK: - Feedback & state extras
// ============================================================================

// MARK: WebUI Stat Card
/// a metric card with a delta.
public struct WebUIStatCard: View {
    public let label: String
    public let value: String
    public let delta: String?
    public let trend: String?
    public let accent: Bool
    public init(_ label: String, value: String, delta: String? = nil, trend: String? = nil, accent: Bool = false) {
        self.label = label; self.value = value; self.delta = delta; self.trend = trend; self.accent = accent
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"stat-card\(accent ? " stat-card--accent" : "")\">"
        html += "<div class=\"stat-card__label\">\(htmlEscape(label))</div>"
        html += "<div class=\"stat-card__value\">\(htmlEscape(value))</div>"
        if let delta = delta {
            let up = (trend ?? "") != "down"
            html += "<div class=\"stat-card__delta delta \(up ? "delta--up" : "delta--down")\">\(htmlEscape(delta))</div>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Delta
/// a small up/down trend indicator.
public struct WebUIDelta: View {
    @available(*, deprecated, renamed: "Trend")
    public typealias Direction = Trend

    public let text: String
    public let direction: Trend
    public init(_ text: String, direction: Trend = .up) { self.text = text; self.direction = direction }

    public func render(into buffer: inout HTMLBuffer) {
        // the shared Trend offers `flat`, which Delta never did: it forwards the
        // component's own class pattern and a neutral bar glyph.
        let cls: String
        let glyph: String
        switch direction {
            case .up: cls = " delta--up"; glyph = "▲"
            case .down: cls = " delta--down"; glyph = "▼"
            case .flat: cls = " delta--flat"; glyph = "▬"
        }
        buffer.append("<span class=\"delta\(cls)\">\(glyph) \(htmlEscape(text))</span>")
    }
}

// MARK: WebUI Celebrate
/// a celebratory card.
public struct WebUICelebrate: View {
    public let emoji: String
    public let title: String
    public let text: String?
    public init(emoji: String, title: String, text: String? = nil) { self.emoji = emoji; self.title = title; self.text = text }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"celebrate\">"
        html += "<div class=\"celebrate__emoji\">\(htmlEscape(emoji))</div>"
        html += "<div class=\"celebrate__title\">\(htmlEscape(title))</div>"
        if let text { html += "<div class=\"celebrate__text\">\(htmlEscape(text))</div>" }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Confetti
/// a confetti burst.
public struct WebUIConfetti: View {
    public let round: Bool
    public init(round: Bool = true) { self.round = round }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"confetti-stage\"><div class=\"confetti\(round ? " confetti--round" : "")\" aria-hidden=\"true\">"
        for _ in 0..<24 { html += "<span class=\"confetti__piece\"></span>" }
        html += "</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Countdown
/// a countdown timer display.
public struct WebUICountdown: View {
    public struct Unit: Sendable { public let value: Int; public let label: String
        public init(_ value: Int, label: String) { self.value = value; self.label = label } }
    public let label: String
    public let units: [Unit]
    public let urgent: Bool
    public init(label: String = "", units: [Unit], urgent: Bool = false) { self.label = label; self.units = units; self.urgent = urgent }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"countdown\(urgent ? " countdown--urgent" : "")\">"
        if !label.isEmpty { html += "<div class=\"countdown__label\">\(htmlEscape(label))</div>" }
        html += "<div class=\"countdown__units\">"
        for u in units {
            html += "<div class=\"countdown__unit\"><span class=\"countdown__value\">\(webuiZeroPad(u.value, width: 2))</span><span class=\"countdown__unit-label\">\(htmlEscape(u.label))</span></div>"
        }
        html += "</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Cookie Consent
/// a cookie-consent banner.
public struct WebUICookieConsent: View {
    public let title: String?
    public let text: String
    public let children: [any View]
    public let id: String?
    public let onSelect: EventHandler?
    public init(title: String? = nil, text: String, id: String? = nil, onSelect: EventHandler? = nil,
                @ViewBuilder content: () -> [any View]) {
        self.title = title; self.text = text; self.children = content(); self.id = id; self.onSelect = onSelect
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = "<div class=\"cookie-consent\"\(attrs) role=\"dialog\" aria-modal=\"false\">"
        html += "<div class=\"cookie-consent__body\">"
        if let title { html += "<div class=\"cookie-consent__title\">\(htmlEscape(title))</div>" }
        html += "<div class=\"cookie-consent__text\">\(htmlEscape(text))</div>"
        html += "<div class=\"cookie-consent__actions\">"
        for c in children { html += c.renderThroughBuffer() }
        html += "</div></div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Pull Refresh
/// a pull-to-refresh indicator.
public struct WebUIPullRefresh: View {
    @available(*, deprecated, renamed: "LoadState")
    public typealias State = LoadState

    public let state: LoadState
    public let text: String?
    public let id: String?
    public let onRefresh: EventHandler?

    /// this component's own class for a shared load state — `loading` keeps the
    /// 1.x `active` bytes; `ready`/`failed` forward the pattern.
    private static func classFor(_ state: LoadState) -> String {
        switch state {
            case .idle: return " pull-refresh--idle"
            case .loading: return " pull-refresh--active"
            case .ready: return " pull-refresh--ready"
            case .failed: return " pull-refresh--failed"
        }
    }

    public init(state: LoadState = .idle, text: String? = nil, id: String? = nil, onRefresh: EventHandler? = nil) {
        self.state = state; self.text = text; self.id = id; self.onRefresh = onRefresh
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onRefresh) } ?? ""
        var html = "<div class=\"pull-refresh\(Self.classFor(state))\"\(attrs) role=\"status\">"
        html += "<div class=\"pull-refresh__indicator\"><span class=\"pull-refresh__spinner\"></span>"
        if let text { html += "<span class=\"pull-refresh__text\">\(htmlEscape(text))</span>" }
        html += "</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Skeleton Card
/// a skeleton placeholder card.
public struct WebUISkeletonCard: View {
    public let withMedia: Bool
    public init(withMedia: Bool = true) { self.withMedia = withMedia }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"skeleton-card\">"
        if withMedia { html += "<div class=\"skeleton-card__media skeleton skeleton--rect\"></div>" }
        html += "<div class=\"skeleton__text skeleton__text--w100 skeleton\"></div>"
        html += "<div class=\"skeleton__text skeleton__text--w60 skeleton\"></div>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Applet Card
/// a small stat/action card (e.g. applet tile).
public struct WebUIAppletCard: View {
    public let title: String
    public let value: String
    public init(title: String, value: String) { self.title = title; self.value = value }

    public func render(into buffer: inout HTMLBuffer) {
        let html = "<div class=\"applet-card\"><div class=\"applet-card__label\">\(htmlEscape(title))</div><div class=\"applet-card__value\">\(htmlEscape(value))</div></div>"
        buffer.append(html)
    }
}

// MARK: WebUI Avatar Stack
/// overlapping avatars.
public struct WebUIAvatarStack: View {
    public let initials: [String]
    public let more: Int
    public init(initials: [String], more: Int = 0) { self.initials = initials; self.more = more }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"avatar-stack\">"
        for initi in initials {
            html += "<span class=\"avatar avatar--md avatar--initials\">\(htmlEscape(initi))</span>"
        }
        if more > 0 { html += "<span class=\"avatar avatar--md avatar--more\">+\(more)</span>" }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Badge Status
/// an online/away/busy status badge.
public struct WebUIBadgeStatus: View {
    @available(*, deprecated, renamed: "Presence")
    public typealias Status = Presence

    public let label: String
    public let status: Presence

    /// this component's own class for a shared presence — an exact case-for-case
    /// match, so every 1.x byte is unchanged (leading space included).
    private static func classFor(_ status: Presence) -> String {
        switch status {
            case .online: return " badge-status__dot--online"
            case .away: return " badge-status__dot--away"
            case .busy: return " badge-status__dot--busy"
            case .offline: return " badge-status__dot--offline"
            case .live: return " badge-status__dot--live"
        }
    }

    public init(_ label: String, status: Presence = .online) { self.label = label; self.status = status }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.append("<span class=\"badge-status\"><span class=\"badge-status__dot \(Self.classFor(status))\"></span>\(htmlEscape(label))</span>")
    }
}

// MARK: WebUI Badge Count
/// a count badge attached to an icon.
public struct WebUIBadgeCount: View {
    public let count: Int
    public let icon: IconName
    public init(count: Int, icon: IconName) { self.count = count; self.icon = icon }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<span class=\"badge-count\">"
        html += "<span class=\"badge-count__icon\">\(WebUIIcon(icon, size: .medium).renderThroughBuffer())</span>"
        html += "<span class=\"badge-count__num\">\(count)</span>"
        html += "</span>"
        buffer.append(html)
    }
}

// MARK: WebUI Radio Group
/// a grouped set of radio options.
public struct WebUIRadioGroup: View {
    public struct Option: Sendable { public let label: String; public let value: String
        public init(_ label: String, value: String? = nil) { self.label = label; self.value = value ?? label } }
    public let options: [Option]
    public let selected: String?
    public let inline: Bool
    public init(options: [Option], selected: String? = nil, inline: Bool = false) { self.options = options; self.selected = selected; self.inline = inline }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"radio-group\(inline ? " radio-group--inline" : "")\" role=\"radiogroup\">"
        for option in options {
            let checked = option.value == selected
            html += "<label class=\"radio\">"
            html += "<input type=\"radio\" name=\"radio-group\" value=\"\(htmlEscape(option.value))\"\(checked ? " checked" : "") class=\"radio__input\">"
            html += "<span class=\"radio__circle\"></span><span class=\"radio__label\">\(htmlEscape(option.label))</span>"
            html += "</label>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Checkbox Group
/// a grouped set of checkbox options.
public struct WebUICheckboxGroup: View {
    public struct Option: Sendable { public let label: String; public let checked: Bool
        public init(_ label: String, checked: Bool = false) { self.label = label; self.checked = checked } }
    public let options: [Option]
    public let inline: Bool
    public init(options: [Option], inline: Bool = false) { self.options = options; self.inline = inline }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"checkbox-group\(inline ? " checkbox-group--inline" : "")\">"
        for option in options {
            html += "<label class=\"checkbox\">"
            html += "<input type=\"checkbox\" class=\"checkbox__input\"\(option.checked ? " checked" : "")>"
            html += "<span class=\"checkbox__box\"></span><span class=\"checkbox__label\">\(htmlEscape(option.label))</span>"
            html += "</label>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Banner
/// a page-level message strip: full-bleed, persistent, dismissible. distinct
/// from the in-content alert, which is rounded and inset; the sheet gives the
/// banner a bottom border and no radius, for the top of a page or a section.
public struct WebUIBanner: View, Dismissible {    @available(*, deprecated, renamed: "Tone")
    public typealias Variant = Tone

    /// this component's own class for a shared tone. a tone this component
    /// never offered forwards the same pattern (`"banner--neutral"`) rather than
    /// silently rendering the default — the class stays an extension point.
    private static func classFor(_ tone: Tone) -> String {
        switch tone {
            case .neutral: return "banner--neutral"
            case .primary: return "banner--primary"
            case .secondary: return "banner--secondary"
            case .info: return "banner--info"
            case .success: return "banner--success"
            case .warning: return "banner--warning"
            case .danger: return "banner--error"
        }
    }

    private static func defaultIcon(for tone: Tone) -> IconName {
        switch tone {
        case .info: return .info
        case .success: return .checkCircle
        case .warning: return .alertTriangle
        case .danger: return .xCircle
                case .neutral, .primary, .secondary: return .info
}
    }

    public let tone: Tone
    public let title: String?
    public let message: String
    public let dismissible: Bool
    public let icon: IconName
    public let id: String?
    public var onDismiss: DismissHandler?
    @available(*, deprecated, message: "use tone: — Tone is the shared vocabulary")

    public init(
        variant: Tone,
        title: String? = nil,
        message: String,
        dismissible: Bool = false,
        icon: IconName? = nil,
        id: String? = nil
    ) {
        self.tone = variant
        self.title = title
        self.message = message
        self.dismissible = dismissible
        self.icon = icon ?? Self.defaultIcon(for: variant)
        self.id = id
        self.onDismiss = nil
    }


    public init(
        tone: Variant = .info,
        title: String? = nil,
        message: String,
        dismissible: Bool = false,
        icon: IconName? = nil,
        id: String? = nil
    ) {
        self.tone = tone
        self.title = title
        self.message = message
        self.dismissible = dismissible
        self.icon = icon ?? Self.defaultIcon(for: tone)
        self.id = id
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "banner__close" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: RenderContext.currentStrings.dismiss)
        var html = "<div class=\"banner \(Self.classFor(tone))\" role=\"status\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        html += ">"
        html += "<div class=\"banner__icon fill-slot\">" + WebUIIcon(icon, size: .slot).renderThroughBuffer() + "</div>"
        html += "<div class=\"banner__body\">"
        if let title {
            html += "<span class=\"banner__title\">\(htmlEscape(title))</span>"
        }
        html += "<div class=\"banner__text\">\(htmlEscape(message))</div>"
        html += "</div>"
        if dismissible || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Activity Feed
/// a grouped activity stream: a group heading, then rows of glyph, text and
/// relative time. the sheet draws the group rule and the circular icon chip.
public struct WebUIActivityFeed: View {
    public struct Item: Sendable {
        public let icon: IconName
        public let text: String
        /// trailing relative time, e.g. "2h".
        public let time: String?
        public init(icon: IconName, text: String, time: String? = nil) {
            self.icon = icon
            self.text = text
            self.time = time
        }
    }

    public struct Group: Sendable {
        public let title: String
        public let items: [Item]
        public init(_ title: String, items: [Item]) {
            self.title = title
            self.items = items
        }
    }

    public let groups: [Group]

    public init(_ groups: [Group]) {
        self.groups = groups
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"activity\">"
        for group in groups {
            html += "<div class=\"activity__group\">\(htmlEscape(group.title))</div>"
            for item in group.items {
                html += "<div class=\"activity__item\">"
                html += "<div class=\"activity__icon fill-slot\">" + WebUIIcon(item.icon, size: .slot).renderThroughBuffer() + "</div>"
                html += "<div class=\"activity__text\">\(htmlEscape(item.text))</div>"
                if let time = item.time {
                    html += "<span class=\"activity__time\">\(htmlEscape(time))</span>"
                }
                html += "</div>"
            }
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Message Scroller
/// a bottom-anchored scroller for message streams. the sheet's `.scroll-area`
/// supplies the viewport and the sticky edge mask; the reverse-column modifier
/// keeps the view pinned to the newest item with no client javascript. that
/// layout requirement is why children are emitted in reverse dom order: pass
/// them chronologically (oldest first) and the newest lands lowest, with the
/// scroll origin already at the bottom.
public struct WebUIMessageScroller: View {
    /// viewport height as a css length, e.g. "20rem" or "60vh".
    public let height: String
    public let id: String?
    /// mask the top and bottom edges as they scroll out of view.
    public let fade: Bool
    /// accessible name for the log region.
    public let ariaLabel: String
    public let children: [any View]

    public init(
        height: String = "20rem",
        id: String? = nil,
        fade: Bool = true,
        ariaLabel: String = WebUIStrings.english.messages,
        @ViewBuilder content: () -> [any View]
    ) {
        self.height = height
        self.id = id
        self.fade = fade
        self.ariaLabel = ariaLabel
        self.children = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"scroll-area scroll-area--reverse"
        if fade { html += " scroll-area--fade-y" }
        html += "\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        let size = htmlEscape(height)
        html += " style=\"height: \(size); max-height: \(size)\""
        html += " role=\"log\" aria-live=\"polite\" aria-label=\"\(htmlEscape(ariaLabel))\" tabindex=\"0\">"
        for child in children.reversed() {
            html += child.renderThroughBuffer()
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Marker
/// a labelled break in a stream, e.g. a day divider. sits between two rules by
/// default; `spread: false` drops the rules for a bare label, and `sticky` pins
/// the marker to the top of its scroller while the stream moves under it.
public struct WebUIMarker: View {
    public let label: String
    public let icon: IconName?
    public let sticky: Bool
    public let spread: Bool

    public init(_ label: String, icon: IconName? = nil, sticky: Bool = false, spread: Bool = true) {
        self.label = label
        self.icon = icon
        self.sticky = sticky
        self.spread = spread
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"marker\(sticky ? " marker--sticky" : "")\" role=\"separator\">"
        if spread { html += "<span class=\"marker__rule\"></span>" }
        if let icon {
            html += "<span class=\"marker__glyph\">" + WebUIIcon(icon, size: .slot).renderThroughBuffer() + "</span>"
        }
        html += "<span class=\"marker__label\">\(htmlEscape(label))</span>"
        if spread { html += "<span class=\"marker__rule\"></span>" }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Attachment
/// a file chip: glyph, name, a meta line (size, type, or why it failed) and an
/// optional remove affordance. conforms to `Dismissible`, so the remove button
/// takes the standard `.onDismiss { me, _ in [me.remove()] }` handler.
public struct WebUIAttachment: View, Dismissible {
    @available(*, deprecated, renamed: "LoadState")
    public typealias State = LoadState

    public let name: String
    /// secondary line: size, mime type, or the failure reason.
    public let meta: String?
    public let icon: IconName
    public let state: LoadState
    public let removable: Bool
    public let id: String?
    public var onDismiss: DismissHandler?

    /// this component's own class for a shared load state — `ready` is the base
    /// surface (the 1.x empty string); `loading` keeps the `uploading` bytes and
    /// `failed` the `error` ones.
    private static func classFor(_ state: LoadState) -> String {
        switch state {
            case .idle: return "attachment--idle"
            case .loading: return "attachment--uploading"
            case .ready: return ""
            case .failed: return "attachment--error"
        }
    }

    public init(
        name: String,
        meta: String? = nil,
        icon: IconName? = nil,
        state: LoadState = .ready,
        removable: Bool = false,
        id: String? = nil
    ) {
        self.name = name
        self.meta = meta
        self.icon = icon ?? .fileText
        self.state = state
        self.removable = removable
        self.id = id
        self.onDismiss = nil
    }

    public var dismissButtonClass: String { "attachment__remove" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render(into buffer: inout HTMLBuffer) {
        let dismissal = makeDismissal(ariaLabel: RenderContext.currentStrings.removeAttachment)
        let stateClass = Self.classFor(state)
        var html = "<div class=\"attachment"
        if !stateClass.isEmpty { html += " \(stateClass)" }
        html += "\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        html += ">"
        html += "<span class=\"attachment__icon\">" + WebUIIcon(icon, size: .small).renderThroughBuffer() + "</span>"
        html += "<span class=\"attachment__body\">"
        html += "<span class=\"attachment__name\">\(htmlEscape(name))</span>"
        if let meta {
            html += "<span class=\"attachment__meta\">\(htmlEscape(meta))</span>"
        }
        html += "</span>"
        if removable || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Chat Bubble
/// one message bubble. `side` picks the outgoing (solid, right-aligned) or
/// incoming (inset, left-aligned) treatment; time, receipt and reaction pills
/// are optional. the sheet carries both a `--sent/--received` pair and an
/// `--own` pair for the same idea; this component uses the side pair and
/// `WebUIMessage` uses the owned pair inside a thread.
public struct WebUIChatBubble: View {
    /// the bubble's own axis, named for what it is: `Side` meant two unrelated
    /// things across the framework (this, and a popover's anchor), so neither
    /// keeps the bare name.
    public enum BubbleSide: String, Sendable {
        case sent = "chat__bubble--sent"
        case received = "chat__bubble--received"
    }

    @available(*, deprecated, renamed: "BubbleSide")
    public typealias Side = BubbleSide

    /// delivery state of an outgoing bubble.
    public enum Receipt: String, Sendable {
        case sent
        case delivered
        case read
    }

    public struct Reaction: Sendable {
        public let label: String
        public let count: Int
        public let active: Bool
        public init(label: String, count: Int = 1, active: Bool = false) {
            self.label = label
            self.count = count
            self.active = active
        }
    }

    public let text: String
    public let side: BubbleSide
    /// timestamp shown at the bubble's trailing edge.
    public let time: String?
    /// only meaningful for `.sent`; renders a glyph with an accessible name.
    public let receipt: Receipt?
    public let reactions: [Reaction]
    public let id: String?

    public init(
        _ text: String,
        side: BubbleSide = .received,
        time: String? = nil,
        receipt: Receipt? = nil,
        reactions: [Reaction] = [],
        id: String? = nil
    ) {
        self.text = text
        self.side = side
        self.time = time
        self.receipt = receipt
        self.reactions = reactions
        self.id = id
    }

    private func receiptHTML(for receipt: Receipt) -> String {
        let icon: IconName
        let label: String
        let extraClass: String
        switch receipt {
        case .sent:
            icon = .check
            label = RenderContext.currentStrings.sent
            extraClass = ""
        case .delivered:
            icon = .checkCheck
            label = RenderContext.currentStrings.delivered
            extraClass = ""
        case .read:
            icon = .checkCheck
            label = RenderContext.currentStrings.read
            extraClass = " chat__receipt--read"
        }
        return "<span class=\"chat__receipt\(extraClass)\" role=\"img\" aria-label=\"\(label)\">"
            + WebUIIcon(icon, size: .small).renderThroughBuffer() + "</span>"
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"chat__bubble \(side.rawValue)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += ">"
        html += htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>")
        if let time {
            html += "<span class=\"chat__time\">\(htmlEscape(time))"
            if let receipt, side == .sent {
                html += receiptHTML(for: receipt)
            }
            html += "</span>"
        }
        html += "</div>"
        if !reactions.isEmpty {
            var row = "<div class=\"chat__reactions\">"
            for reaction in reactions {
                row += "<span class=\"chat__reaction\(reaction.active ? " chat__reaction--active" : "")\">"
                row += "<span aria-hidden=\"true\">\(htmlEscape(reaction.label))</span>"
                row += "<span>\(reaction.count)</span>"
                row += "</span>"
            }
            row += "</div>"
            html += row
        }
        buffer.append(html)
    }
}

// MARK: WebUI Message
/// a threaded message: an author/time meta row above an owned or other bubble.
/// use it when messages carry an author; the bare `WebUIChatBubble` is enough
/// for a single-voice stream.
public struct WebUIMessage: View {
    public let name: String
    public let text: String
    public let time: String?
    /// true renders the thread (and its bubble) as the local participant.
    public let own: Bool
    public let reactions: [WebUIChatBubble.Reaction]

    public init(
        name: String,
        text: String,
        time: String? = nil,
        own: Bool = false,
        reactions: [WebUIChatBubble.Reaction] = []
    ) {
        self.name = name
        self.text = text
        self.time = time
        self.own = own
        self.reactions = reactions
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"chat__thread\(own ? " chat__thread--own" : "")\">"
        html += "<div class=\"chat__meta\"><span>\(htmlEscape(name))</span>"
        if let time { html += "<span>\(htmlEscape(time))</span>" }
        html += "</div>"
        html += "<div class=\"chat__bubble\(own ? " chat__bubble--own" : "")\">"
        html += htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>")
        html += "</div>"
        if !reactions.isEmpty {
            var row = "<div class=\"chat__reactions\">"
            for reaction in reactions {
                row += "<span class=\"chat__reaction\(reaction.active ? " chat__reaction--active" : "")\">"
                row += "<span aria-hidden=\"true\">\(htmlEscape(reaction.label))</span>"
                row += "<span>\(reaction.count)</span>"
                row += "</span>"
            }
            row += "</div>"
            html += row
        }
        html += "</div>"
        buffer.append(html)
    }
}
