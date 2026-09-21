import Foundation
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
    public init(text: String = "", options: [Option] = []) { self.text = text; self.options = options }

    public func render() -> String {
        if options.isEmpty {
            return "<span class=\"mention\">@\(htmlEscape(text))</span>"
        }
        var html = "<div class=\"mention-dropdown\">"
        for option in options {
            html += "<div class=\"mention-option\(option.active ? " mention-option--active" : "")\"><span class=\"mention-option__avatar\"></span><span class=\"mention-option__name\">\(htmlEscape(option.name))</span><span class=\"mention-option__handle\">\(htmlEscape(option.handle))</span></div>"
        }
        html += "</div>"
        return html
    }
}

// MARK: WebUI Reactions
/// an emoji reaction summary with counts.
public struct WebUIReactions: View {
    public struct Reaction: Sendable { public let emoji: String; public let count: Int; public let active: Bool
        public init(_ emoji: String, count: Int = 0, active: Bool = false) { self.emoji = emoji; self.count = count; self.active = active } }
    public let reactions: [Reaction]
    public init(reactions: [Reaction]) { self.reactions = reactions }

    public func render() -> String {
        var html = "<div class=\"reactions\">"
        for r in reactions {
            html += "<button class=\"reactions__emoji\(r.active ? " reactions__emoji--active" : "")\"><span aria-hidden=\"true\">\(htmlEscape(r.emoji))</span><span class=\"reactions__count\">\(r.count)</span></button>"
        }
        html += "<button class=\"reactions__more\" aria-label=\"Add reaction\">＋</button>"
        html += "</div>"
        return html
    }
}

// MARK: WebUI Typing Indicator
/// an animated typing indicator.
public struct WebUITypingIndicator: View {
    public let inline: Bool
    public init(inline: Bool = false) { self.inline = inline }

    public func render() -> String {
        var html = "<div class=\"typing\(inline ? " typing--inline" : "")\" role=\"status\" aria-label=\"Someone is typing\">"
        html += "<span class=\"typing__dot\"></span><span class=\"typing__dot\"></span><span class=\"typing__dot\"></span>"
        html += "</div>"
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
    public init(title: String? = nil, text: String, time: String = "", read: Bool = false, icon: IconName? = nil) {
        self.title = title; self.text = text; self.time = time; self.read = read; self.icon = icon
    }

    public func render() -> String {
        var html = "<div class=\"notification\(read ? " notification--read" : "")\">"
        if let icon { html += "<span class=\"notification__icon\">\(WebUIIcon(icon, size: .medium).render())</span>" }
        else { html += "<span class=\"notification__icon\"><span class=\"notification__unread\"></span></span>" }
        html += "<div class=\"notification__body\">"
        if let title { html += "<div class=\"notification__title\">\(htmlEscape(title))</div>" }
        html += "<div class=\"notification__text\">\(htmlEscape(text))</div>"
        if !time.isEmpty { html += "<div class=\"notification__time\">\(htmlEscape(time))</div>" }
        html += "</div></div>"
        return html
    }
}

// MARK: WebUI Toast Stack
/// a stack container for toasts.
public struct WebUIToastStack: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = "<div class=\"toast-stack\" aria-live=\"polite\">"
        for c in children { html += c.render() }
        html += "</div>"
        return html
    }
}

// MARK: WebUI Bell
/// a notification bell with a badge.
public struct WebUIBell: View {
    public let count: Int
    public let icon: IconName
    public init(count: Int = 0, icon: IconName = .bell) { self.count = count; self.icon = icon }

    public func render() -> String {
        var html = "<button class=\"bell\" aria-label=\"Notifications\(count > 0 ? ", \(count) unread" : "")\">"
        html += "<span class=\"bell__icon\">\(WebUIIcon(icon, size: .medium).render())</span>"
        if count > 0 { html += "<span class=\"bell__badge\">\(count)</span>" }
        html += "</button>"
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
        var html = "<div class=\"stat-card\(accent ? " stat-card--accent" : "")\">"
        html += "<div class=\"stat-card__label\">\(htmlEscape(label))</div>"
        html += "<div class=\"stat-card__value\">\(htmlEscape(value))</div>"
        if let delta = delta {
            let up = (trend ?? "") != "down"
            html += "<div class=\"stat-card__delta delta \(up ? "delta--up" : "delta--down")\">\(htmlEscape(delta))</div>"
        }
        html += "</div>"
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
        return "<span class=\"delta\(direction.rawValue)\">\(direction == .up ? "▲" : "▼") \(htmlEscape(text))</span>"
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
        var html = "<div class=\"celebrate\">"
        html += "<div class=\"celebrate__emoji\">\(htmlEscape(emoji))</div>"
        html += "<div class=\"celebrate__title\">\(htmlEscape(title))</div>"
        if let text { html += "<div class=\"celebrate__text\">\(htmlEscape(text))</div>" }
        html += "</div>"
        return html
    }
}

// MARK: WebUI Confetti
/// a confetti burst.
public struct WebUIConfetti: View {
    public let round: Bool
    public init(round: Bool = true) { self.round = round }

    public func render() -> String {
        var html = "<div class=\"confetti-stage\"><div class=\"confetti\(round ? " confetti--round" : "")\" aria-hidden=\"true\">"
        for _ in 0..<24 { html += "<span class=\"confetti__piece\"></span>" }
        html += "</div></div>"
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
        var html = "<div class=\"countdown\(urgent ? " countdown--urgent" : "")\">"
        if !label.isEmpty { html += "<div class=\"countdown__label\">\(htmlEscape(label))</div>" }
        html += "<div class=\"countdown__units\">"
        for u in units {
            html += "<div class=\"countdown__unit\"><span class=\"countdown__value\">\(String(format: "%02d", u.value))</span><span class=\"countdown__unit-label\">\(htmlEscape(u.label))</span></div>"
        }
        html += "</div></div>"
        return html
    }
}

// MARK: WebUI Cookie Consent
/// a cookie-consent banner.
public struct WebUICookieConsent: View {
    public let title: String?
    public let text: String
    public let children: [any View]
    public init(title: String? = nil, text: String, @ViewBuilder content: () -> [any View] = { [] }) {
        self.title = title; self.text = text; self.children = content()
    }

    public func render() -> String {
        var html = "<div class=\"cookie-consent\" role=\"dialog\" aria-modal=\"false\">"
        html += "<div class=\"cookie-consent__body\">"
        if let title { html += "<div class=\"cookie-consent__title\">\(htmlEscape(title))</div>" }
        html += "<div class=\"cookie-consent__text\">\(htmlEscape(text))</div>"
        html += "<div class=\"cookie-consent__actions\">"
        for c in children { html += c.render() }
        html += "</div></div></div>"
        return html
    }
}

// MARK: WebUI Pull Refresh
/// a pull-to-refresh indicator.
public struct WebUIPullRefresh: View {
    public enum State: String, Sendable { case idle = " pull-refresh--idle", active = " pull-refresh--active" }
    public let state: State
    public let text: String?
    public init(state: State = .idle, text: String? = nil) { self.state = state; self.text = text }

    public func render() -> String {
        var html = "<div class=\"pull-refresh\(state.rawValue)\" role=\"status\">"
        html += "<div class=\"pull-refresh__indicator\"><span class=\"pull-refresh__spinner\"></span>"
        if let text { html += "<span class=\"pull-refresh__text\">\(htmlEscape(text))</span>" }
        html += "</div></div>"
        return html
    }
}

// MARK: WebUI Skeleton Card
/// a skeleton placeholder card.
public struct WebUISkeletonCard: View {
    public let withMedia: Bool
    public init(withMedia: Bool = true) { self.withMedia = withMedia }

    public func render() -> String {
        var html = "<div class=\"skeleton-card\">"
        if withMedia { html += "<div class=\"skeleton-card__media skeleton skeleton--rect\"></div>" }
        html += "<div class=\"skeleton__text skeleton__text--w100 skeleton\"></div>"
        html += "<div class=\"skeleton__text skeleton__text--w60 skeleton\"></div>"
        html += "</div>"
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
        var html = "<div class=\"applet-card\"><div class=\"applet-card__label\">\(htmlEscape(title))</div><div class=\"applet-card__value\">\(htmlEscape(value))</div></div>"
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
        var html = "<div class=\"avatar-stack\">"
        for (i, initi) in initials.enumerated() {
            html += "<span class=\"avatar avatar--md avatar--initials\">\(htmlEscape(initi))</span>"
        }
        if more > 0 { html += "<span class=\"avatar avatar--md avatar--more\">+\(more)</span>" }
        html += "</div>"
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
        return "<span class=\"badge-status\"><span class=\"badge-status__dot \(status.rawValue)\"></span>\(htmlEscape(label))</span>"
    }
}

// MARK: WebUI Badge Count
/// a count badge attached to an icon.
public struct WebUIBadgeCount: View {
    public let count: Int
    public let icon: IconName
    public init(count: Int, icon: IconName) { self.count = count; self.icon = icon }

    public func render() -> String {
        var html = "<span class=\"badge-count\">"
        html += "<span class=\"badge-count__icon\">\(WebUIIcon(icon, size: .medium).render())</span>"
        html += "<span class=\"badge-count__num\">\(count)</span>"
        html += "</span>"
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
        var html = "<div class=\"radio-group\(inline ? " radio-group--inline" : "")\" role=\"radiogroup\">"
        for option in options {
            let checked = option.value == selected
            html += "<label class=\"radio\">"
            html += "<input type=\"radio\" name=\"radio-group\" value=\"\(htmlEscape(option.value))\"\(checked ? " checked" : "") class=\"radio__input\">"
            html += "<span class=\"radio__circle\"></span><span class=\"radio__label\">\(htmlEscape(option.label))</span>"
            html += "</label>"
        }
        html += "</div>"
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
        var html = "<div class=\"checkbox-group\(inline ? " checkbox-group--inline" : "")\">"
        for option in options {
            html += "<label class=\"checkbox\">"
            html += "<input type=\"checkbox\" class=\"checkbox__input\"\(option.checked ? " checked" : "")>"
            html += "<span class=\"checkbox__box\"></span><span class=\"checkbox__label\">\(htmlEscape(option.label))</span>"
            html += "</label>"
        }
        html += "</div>"
        return html
    }
}
