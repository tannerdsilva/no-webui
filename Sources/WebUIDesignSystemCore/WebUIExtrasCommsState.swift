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

    public func render() -> String {
        if options.isEmpty {
            return Tag.element("span", [Tag.classes(["mention"])], "@" + htmlEscape(text))
        }
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = Tag.begin("div", Tag.classes(["mention-dropdown"]), attrs)
        for (i, option) in options.enumerated() {
            html += Tag.begin("div", Tag.classes(["mention-option", option.active ? " mention-option--active" : ""]), id.map { Tag.escAttr("id", "\($0)-option-\(i)") } ?? "")
            html += Tag.element("span", [Tag.classes(["mention-option__avatar"])], "")
            html += Tag.element("span", [Tag.classes(["mention-option__name"])], htmlEscape(option.name))
            html += Tag.element("span", [Tag.classes(["mention-option__handle"])], htmlEscape(option.handle))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onChange) } ?? ""
        var html = Tag.begin("div", Tag.classes(["reactions"]), attrs)
        for (i, r) in reactions.enumerated() {
            html += Tag.begin("button", Tag.classes(["reactions__emoji", r.active ? " reactions__emoji--active" : ""]), id.map { Tag.escAttr("id", "\($0)-r-\(i)") } ?? "")
            html += Tag.element("span", [Tag.attr("aria-hidden", "true")], htmlEscape(r.emoji))
            html += Tag.element("span", [Tag.classes(["reactions__count"])], "\(r.count)")
            html += Tag.end("button")
        }
        html += Tag.element("button", [Tag.classes(["reactions__more"]), Tag.attr("aria-label", "Add reaction")], "＋")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Typing Indicator
/// an animated typing indicator.
public struct WebUITypingIndicator: View {
    public let inline: Bool
    public init(inline: Bool = false) { self.inline = inline }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["typing", inline ? " typing--inline" : ""]), Tag.attr("role", "status"), Tag.attr("aria-label", "Someone is typing"))
        html += Tag.element("span", [Tag.classes(["typing__dot"])], "")
        html += Tag.element("span", [Tag.classes(["typing__dot"])], "")
        html += Tag.element("span", [Tag.classes(["typing__dot"])], "")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Notification
/// a notification row within a panel.
public struct WebUINotification: View {
    public enum Kind: String { case info, success, warning, danger }
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

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = Tag.begin("div", Tag.classes(["notification", read ? " notification--read" : ""]), attrs)
        if let icon {
            html += Tag.element("span", [Tag.classes(["notification__icon"])], WebUIIcon(icon, size: .medium).render())
        } else {
            html += Tag.element("span", [Tag.classes(["notification__icon"])], Tag.element("span", [Tag.classes(["notification__unread"])], ""))
        }
        html += Tag.begin("div", Tag.classes(["notification__body"]))
        if let title { html += Tag.element("div", [Tag.classes(["notification__title"])], htmlEscape(title)) }
        html += Tag.element("div", [Tag.classes(["notification__text"])], htmlEscape(text))
        if !time.isEmpty { html += Tag.element("div", [Tag.classes(["notification__time"])], htmlEscape(time)) }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Toast Stack
/// a stack container for toasts.
public struct WebUIToastStack: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["toast-stack"]), Tag.attr("aria-live", "polite"))
        for c in children { html += c.render() }
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = Tag.begin("button", Tag.classes(["bell"]), attrs, Tag.attr("aria-label", "Notifications\(count > 0 ? ", \(count) unread" : "")"))
        html += Tag.element("span", [Tag.classes(["bell__icon"])], WebUIIcon(icon, size: .medium).render())
        if count > 0 { html += Tag.element("span", [Tag.classes(["bell__badge"])], "\(count)") }
        html += Tag.end("button")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["stat-card", accent ? " stat-card--accent" : ""]))
        html += Tag.element("div", [Tag.classes(["stat-card__label"])], htmlEscape(label))
        html += Tag.element("div", [Tag.classes(["stat-card__value"])], htmlEscape(value))
        if let delta = delta {
            let up = (trend ?? "") != "down"
            html += Tag.element("div", [Tag.classes(["stat-card__delta delta", up ? "delta--up" : "delta--down"])], htmlEscape(delta))
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Delta
/// a small up/down trend indicator.
public struct WebUIDelta: View {
    public enum Direction: String, Sendable { case up = " delta--up", down = " delta--down" }
    public let text: String
    public let direction: Direction
    public init(_ text: String, direction: Direction = .up) { self.text = text; self.direction = direction }

    public func render() -> String {
        return Tag.element("span", [Tag.classes(["delta", direction.rawValue])], (direction == .up ? "▲" : "▼") + " " + htmlEscape(text))
    }
}

// MARK: WebUI Celebrate
/// a celebratory card.
public struct WebUICelebrate: View {
    public let emoji: String
    public let title: String
    public let text: String?
    public init(emoji: String, title: String, text: String? = nil) { self.emoji = emoji; self.title = title; self.text = text }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["celebrate"]))
        html += Tag.element("div", [Tag.classes(["celebrate__emoji"])], htmlEscape(emoji))
        html += Tag.element("div", [Tag.classes(["celebrate__title"])], htmlEscape(title))
        if let text { html += Tag.element("div", [Tag.classes(["celebrate__text"])], htmlEscape(text)) }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Confetti
/// a confetti burst.
public struct WebUIConfetti: View {
    public let round: Bool
    public init(round: Bool = true) { self.round = round }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["confetti-stage"]))
        html += Tag.begin("div", Tag.classes(["confetti", round ? " confetti--round" : ""]), Tag.attr("aria-hidden", "true"))
        for _ in 0..<24 { html += Tag.element("span", [Tag.classes(["confetti__piece"])], "") }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["countdown", urgent ? " countdown--urgent" : ""]))
        if !label.isEmpty { html += Tag.element("div", [Tag.classes(["countdown__label"])], htmlEscape(label)) }
        html += Tag.begin("div", Tag.classes(["countdown__units"]))
        for u in units {
            html += Tag.begin("div", Tag.classes(["countdown__unit"]))
            html += Tag.element("span", [Tag.classes(["countdown__value"])], webuiZeroPad(u.value, width: 2))
            html += Tag.element("span", [Tag.classes(["countdown__unit-label"])], htmlEscape(u.label))
            html += Tag.end("div")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onSelect) } ?? ""
        var html = Tag.begin("div", Tag.classes(["cookie-consent"]), attrs, Tag.attr("role", "dialog"), Tag.attr("aria-modal", "false"))
        html += Tag.begin("div", Tag.classes(["cookie-consent__body"]))
        if let title { html += Tag.element("div", [Tag.classes(["cookie-consent__title"])], htmlEscape(title)) }
        html += Tag.element("div", [Tag.classes(["cookie-consent__text"])], htmlEscape(text))
        html += Tag.begin("div", Tag.classes(["cookie-consent__actions"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Pull Refresh
/// a pull-to-refresh indicator.
public struct WebUIPullRefresh: View {
    public enum State: String, Sendable { case idle = " pull-refresh--idle", active = " pull-refresh--active" }
    public let state: State
    public let text: String?
    public let id: String?
    public let onRefresh: EventHandler?
    public init(state: State = .idle, text: String? = nil, id: String? = nil, onRefresh: EventHandler? = nil) {
        self.state = state; self.text = text; self.id = id; self.onRefresh = onRefresh
    }

    public func render() -> String {
        let attrs = id.map { controlAttributes(id: $0, event: .click, handler: onRefresh) } ?? ""
        var html = Tag.begin("div", Tag.classes(["pull-refresh", state.rawValue]), attrs, Tag.attr("role", "status"))
        html += Tag.begin("div", Tag.classes(["pull-refresh__indicator"]))
        html += Tag.element("span", [Tag.classes(["pull-refresh__spinner"])], "")
        if let text { html += Tag.element("span", [Tag.classes(["pull-refresh__text"])], htmlEscape(text)) }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Skeleton Card
/// a skeleton placeholder card.
public struct WebUISkeletonCard: View {
    public let withMedia: Bool
    public init(withMedia: Bool = true) { self.withMedia = withMedia }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["skeleton-card"]))
        if withMedia { html += Tag.element("div", [Tag.classes(["skeleton-card__media skeleton skeleton--rect"])], "") }
        html += Tag.element("div", [Tag.classes(["skeleton__text skeleton__text--w100 skeleton"])], "")
        html += Tag.element("div", [Tag.classes(["skeleton__text skeleton__text--w60 skeleton"])], "")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Applet Card
/// a small stat/action card (e.g. applet tile).
public struct WebUIAppletCard: View {
    public let title: String
    public let value: String
    public init(title: String, value: String) { self.title = title; self.value = value }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["applet-card"]))
        html += Tag.element("div", [Tag.classes(["applet-card__label"])], htmlEscape(title))
        html += Tag.element("div", [Tag.classes(["applet-card__value"])], htmlEscape(value))
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Avatar Stack
/// overlapping avatars.
public struct WebUIAvatarStack: View {
    public let initials: [String]
    public let more: Int
    public init(initials: [String], more: Int = 0) { self.initials = initials; self.more = more }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["avatar-stack"]))
        for initi in initials {
            html += Tag.element("span", [Tag.classes(["avatar avatar--md avatar--initials"])], htmlEscape(initi))
        }
        if more > 0 { html += Tag.element("span", [Tag.classes(["avatar avatar--md avatar--more"])], "+\(more)") }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Badge Status
/// an online/away/busy status badge.
public struct WebUIBadgeStatus: View {
    public enum Status: String, Sendable { case online = " badge-status__dot--online", away = " badge-status__dot--away",
        busy = " badge-status__dot--busy", offline = " badge-status__dot--offline", live = " badge-status__dot--live" }
    public let label: String
    public let status: Status
    public init(_ label: String, status: Status = .online) { self.label = label; self.status = status }

    public func render() -> String {
        return Tag.begin("span", Tag.classes(["badge-status"]))
            // the status rawValue's own leading space plus the template's
            // literal space make a DOUBLE space — byte-pinned by the base capture
            + Tag.element("span", [Tag.classes(["badge-status__dot", " " + status.rawValue])], "")
            + htmlEscape(label)
            + Tag.end("span")
    }
}

// MARK: WebUI Badge Count
/// a count badge attached to an icon.
public struct WebUIBadgeCount: View {
    public let count: Int
    public let icon: IconName
    public init(count: Int, icon: IconName) { self.count = count; self.icon = icon }

    public func render() -> String {
        var html = Tag.begin("span", Tag.classes(["badge-count"]))
        html += Tag.element("span", [Tag.classes(["badge-count__icon"])], WebUIIcon(icon, size: .medium).render())
        html += Tag.element("span", [Tag.classes(["badge-count__num"])], "\(count)")
        html += Tag.end("span")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["radio-group", inline ? " radio-group--inline" : ""]), Tag.attr("role", "radiogroup"))
        for option in options {
            let checked = option.value == selected
            html += Tag.begin("label", Tag.classes(["radio"]))
            html += Tag.void("input",
                Tag.attr("type", "radio"),
                Tag.attr("name", "radio-group"),
                Tag.escAttr("value", option.value),
                checked ? Tag.flag("checked") : "",
                Tag.classes(["radio__input"]))
            html += Tag.element("span", [Tag.classes(["radio__circle"])], "")
            html += Tag.element("span", [Tag.classes(["radio__label"])], htmlEscape(option.label))
            html += Tag.end("label")
        }
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["checkbox-group", inline ? " checkbox-group--inline" : ""]))
        for option in options {
            html += Tag.begin("label", Tag.classes(["checkbox"]))
            html += Tag.void("input",
                Tag.attr("type", "checkbox"),
                Tag.classes(["checkbox__input"]),
                option.checked ? Tag.flag("checked") : "")
            html += Tag.element("span", [Tag.classes(["checkbox__box"])], "")
            html += Tag.element("span", [Tag.classes(["checkbox__label"])], htmlEscape(option.label))
            html += Tag.end("label")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Banner
/// a page-level message strip: full-bleed, persistent, dismissible. distinct
/// from the in-content alert, which is rounded and inset; the sheet gives the
/// banner a bottom border and no radius, for the top of a page or a section.
public struct WebUIBanner: View, Dismissible {
    public enum Variant: String, Sendable {
        case info = "banner--info"
        case success = "banner--success"
        case warning = "banner--warning"
        case danger = "banner--error"
    }

    private static func defaultIcon(for variant: Variant) -> IconName {
        switch variant {
        case .info: return .info
        case .success: return .checkCircle
        case .warning: return .alertTriangle
        case .danger: return .xCircle
        }
    }

    public let variant: Variant
    public let title: String?
    public let message: String
    public let dismissible: Bool
    public let icon: IconName
    public let id: String?
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

    public var dismissButtonClass: String { "banner__close" }
    public var dismissMarker: String { "data-dismiss" }
    public var dismissRootIdentifier: String? { id }

    public func render() -> String {
        let dismissal = makeDismissal(ariaLabel: "Dismiss")
        var attrs = Tag.classes(["banner", variant.rawValue]) + Tag.attr("role", "status")
        if let elementID = dismissal.elementID ?? id {
            attrs += Tag.escAttr("id", elementID)
        }
        var html = Tag.begin("div", attrs)
        html += Tag.element("div", [Tag.classes(["banner__icon fill-slot"])], WebUIIcon(icon, size: .slot).render())
        html += Tag.begin("div", Tag.classes(["banner__body"]))
        if let title {
            html += Tag.element("span", [Tag.classes(["banner__title"])], htmlEscape(title))
        }
        html += Tag.element("div", [Tag.classes(["banner__text"])], htmlEscape(message))
        html += Tag.end("div")
        if dismissible || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["activity"]))
        for group in groups {
            html += Tag.element("div", [Tag.classes(["activity__group"])], htmlEscape(group.title))
            for item in group.items {
                html += Tag.begin("div", Tag.classes(["activity__item"]))
                html += Tag.element("div", [Tag.classes(["activity__icon fill-slot"])], WebUIIcon(item.icon, size: .slot).render())
                html += Tag.element("div", [Tag.classes(["activity__text"])], htmlEscape(item.text))
                if let time = item.time {
                    html += Tag.element("span", [Tag.classes(["activity__time"])], htmlEscape(time))
                }
                html += Tag.end("div")
            }
        }
        html += Tag.end("div")
        return html
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
        ariaLabel: String = "Messages",
        @ViewBuilder content: () -> [any View]
    ) {
        self.height = height
        self.id = id
        self.fade = fade
        self.ariaLabel = ariaLabel
        self.children = content()
    }

    public func render() -> String {
        let size = htmlEscape(height)
        var html = Tag.begin("div",
            Tag.classes(["scroll-area scroll-area--reverse", fade ? " scroll-area--fade-y" : ""]),
            id.map { Tag.escAttr("id", $0) } ?? "",
            Tag.attr("style", "height: \(size); max-height: \(size)"),
            Tag.attr("role", "log"),
            Tag.attr("aria-live", "polite"),
            Tag.escAttr("aria-label", ariaLabel),
            Tag.attr("tabindex", "0"))
        for child in children.reversed() {
            html += child.render()
        }
        html += Tag.end("div")
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["marker", sticky ? " marker--sticky" : ""]), Tag.attr("role", "separator"))
        if spread { html += Tag.element("span", [Tag.classes(["marker__rule"])], "") }
        if let icon {
            html += Tag.element("span", [Tag.classes(["marker__glyph"])], WebUIIcon(icon, size: .slot).render())
        }
        html += Tag.element("span", [Tag.classes(["marker__label"])], htmlEscape(label))
        if spread { html += Tag.element("span", [Tag.classes(["marker__rule"])], "") }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Attachment
/// a file chip: glyph, name, a meta line (size, type, or why it failed) and an
/// optional remove affordance. conforms to `Dismissible`, so the remove button
/// takes the standard `.onDismiss { me, _ in [me.remove()] }` handler.
public struct WebUIAttachment: View, Dismissible {
    public enum State: String, Sendable {
        case ready = ""
        case uploading = "attachment--uploading"
        case error = "attachment--error"
    }

    public let name: String
    /// secondary line: size, mime type, or the failure reason.
    public let meta: String?
    public let icon: IconName
    public let state: State
    public let removable: Bool
    public let id: String?
    public var onDismiss: DismissHandler?

    public init(
        name: String,
        meta: String? = nil,
        icon: IconName? = nil,
        state: State = .ready,
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

    public func render() -> String {
        let dismissal = makeDismissal(ariaLabel: "Remove attachment")
        var attrs = Tag.classes(["attachment", state.rawValue])
        if let elementID = dismissal.elementID ?? id {
            attrs += Tag.escAttr("id", elementID)
        }
        var html = Tag.begin("div", attrs)
        html += Tag.element("span", [Tag.classes(["attachment__icon"])], WebUIIcon(icon, size: .small).render())
        html += Tag.begin("span", Tag.classes(["attachment__body"]))
        html += Tag.element("span", [Tag.classes(["attachment__name"])], htmlEscape(name))
        if let meta {
            html += Tag.element("span", [Tag.classes(["attachment__meta"])], htmlEscape(meta))
        }
        html += Tag.end("span")
        if removable || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Chat Bubble
/// one message bubble. `side` picks the outgoing (solid, right-aligned) or
/// incoming (inset, left-aligned) treatment; time, receipt and reaction pills
/// are optional. the sheet carries both a `--sent/--received` pair and an
/// `--own` pair for the same idea; this component uses the side pair and
/// `WebUIMessage` uses the owned pair inside a thread.
public struct WebUIChatBubble: View {
    public enum Side: String, Sendable {
        case sent = "chat__bubble--sent"
        case received = "chat__bubble--received"
    }

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
    public let side: Side
    /// timestamp shown at the bubble's trailing edge.
    public let time: String?
    /// only meaningful for `.sent`; renders a glyph with an accessible name.
    public let receipt: Receipt?
    public let reactions: [Reaction]
    public let id: String?

    public init(
        _ text: String,
        side: Side = .received,
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
            label = "Sent"
            extraClass = ""
        case .delivered:
            icon = .checkCheck
            label = "Delivered"
            extraClass = ""
        case .read:
            icon = .checkCheck
            label = "Read"
            extraClass = " chat__receipt--read"
        }
        return Tag.begin("span", Tag.classes(["chat__receipt", extraClass]), Tag.attr("role", "img"), Tag.escAttr("aria-label", label))
            + WebUIIcon(icon, size: .small).render() + Tag.end("span")
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["chat__bubble", side.rawValue]), id.map { Tag.escAttr("id", $0) } ?? "")
        html += htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>")
        if let time {
            html += Tag.begin("span", Tag.classes(["chat__time"]))
            html += htmlEscape(time)
            if let receipt, side == .sent {
                html += receiptHTML(for: receipt)
            }
            html += Tag.end("span")
        }
        html += Tag.end("div")
        if !reactions.isEmpty {
            var row = Tag.begin("div", Tag.classes(["chat__reactions"]))
            for reaction in reactions {
                row += Tag.begin("span", Tag.classes(["chat__reaction", reaction.active ? " chat__reaction--active" : ""]))
                row += Tag.element("span", [Tag.attr("aria-hidden", "true")], htmlEscape(reaction.label))
                row += Tag.element("span", [], "\(reaction.count)")
                row += Tag.end("span")
            }
            row += Tag.end("div")
            html += row
        }
        return html
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

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["chat__thread", own ? " chat__thread--own" : ""]))
        html += Tag.begin("div", Tag.classes(["chat__meta"]))
        html += Tag.element("span", [], htmlEscape(name))
        if let time { html += Tag.element("span", [], htmlEscape(time)) }
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["chat__bubble", own ? " chat__bubble--own" : ""]))
        html += htmlEscape(text).replacingOccurrences(of: "\n", with: "<br>")
        html += Tag.end("div")
        if !reactions.isEmpty {
            var row = Tag.begin("div", Tag.classes(["chat__reactions"]))
            for reaction in reactions {
                row += Tag.begin("span", Tag.classes(["chat__reaction", reaction.active ? " chat__reaction--active" : ""]))
                row += Tag.element("span", [Tag.attr("aria-hidden", "true")], htmlEscape(reaction.label))
                row += Tag.element("span", [], "\(reaction.count)")
                row += Tag.end("span")
            }
            row += Tag.end("div")
            html += row
        }
        html += Tag.end("div")
        return html
    }
}
