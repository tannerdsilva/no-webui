import Foundation
import WebUI

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

    public init(
        _ label: String,
        variant: Variant = .primary,
        size: Size = .md,
        disabled: Bool = false,
        id: String? = nil,
        fullWidth: Bool = false,
        loading: Bool = false
    ) {
        self.label = label
        self.variant = variant
        self.size = size
        self.disabled = disabled
        self.id = id
        self.fullWidth = fullWidth
        self.loading = loading
    }

    public func render() -> String {
        var classes = "button \(variant.rawValue) \(size.rawValue)"
        if fullWidth { classes += " button--full" }
        if loading { classes += " button--loading" }

        var html = "<button"
        if let id { html += " id=\"\(id)\"" }
        html += " class=\"\(classes)\""
        if disabled { html += " disabled" }
        if loading { html += " aria-busy=\"true\"" }
        html += ">"
        if loading {
            html += "<span class=\"button__spinner\"></span>"
        }
        html += "<span class=\"button__label\">\(htmlEscape(label))</span>"
        html += "</button>"
        return html
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
        var html = ""

        if let label {
            html += "<label class=\"input__label\""
            if let id { html += " for=\"\(id)\"" }
            html += ">\(htmlEscape(label))</label>"
        }

        html += "<div class=\"input-wrapper\">"
        html += "<input"
        if let id { html += " id=\"\(id)\"" }
        html += " type=\"\(type.rawValue)\""
        html += " class=\"input \(state.rawValue)\""
        html += " placeholder=\"\(htmlEscape(placeholder))\""
        if disabled { html += " disabled" }
        html += ">"
        html += "</div>"

        if let helpText {
            let helpClass = state == .error ? "input__help input__help--error" : "input__help"
            html += "<span class=\"\(helpClass)\">\(htmlEscape(helpText))</span>"
        }

        return html
    }
}

// MARK: - WebUI Card
public struct WebUICard: View {
    public enum Variant: String, Sendable {
        case elevated = "card--elevated"
        case outlined = "card--outlined"
        case flat     = "card--flat"
        case interactive = "card--interactive"
    }

    public let variant: Variant
    public let id: String?
    public let children: [any View]

    public init(
        variant: Variant = .elevated,
        id: String? = nil,
        @ViewBuilder content: () -> [any View]
    ) {
        self.variant = variant
        self.id = id
        self.children = content()
    }

    public func render() -> String {
        var html = "<div class=\"card \(variant.rawValue)\""
        if let id { html += " id=\"\(id)\"" }
        html += ">"
        for child in children {
            html += child.render()
        }
        html += "</div>"
        return html
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
        var classes = "badge \(variant.rawValue) \(size.rawValue)"
        if dot { classes += " badge--dot" }

        var html = "<span class=\"\(classes)\">"
        if dot {
            html += "<span class=\"badge__dot\"></span> "
        }
        html += "\(htmlEscape(text))</span>"
        return html
    }
}

// MARK: - WebUI Alert
public struct WebUIAlert: View {
    public enum Variant: String, Sendable {
        case info    = "alert--info"
        case success = "alert--success"
        case warning = "alert--warning"
        case danger  = "alert--danger"
    }

    public let variant: Variant
    public let title: String?
    public let message: String
    public let dismissible: Bool
    public let icon: String?

    public init(
        variant: Variant = .info,
        title: String? = nil,
        message: String,
        dismissible: Bool = false,
        icon: String? = nil
    ) {
        self.variant = variant
        self.title = title
        self.message = message
        self.dismissible = dismissible
        self.icon = icon
    }

    public func render() -> String {
        var html = "<div class=\"alert \(variant.rawValue)\" role=\"alert\""
        if dismissible { html += " data-dismissible" }
        html += ">"
        if let icon {
            html += "<div class=\"alert__icon\">\(htmlEscape(icon))</div>"
        }
        html += "<div class=\"alert__body\">"
        if let title {
            html += "<div class=\"alert__title\">\(htmlEscape(title))</div>"
        }
        html += "<div class=\"alert__message\">\(htmlEscape(message))</div>"
        html += "</div>"
        if dismissible {
            html += "<button class=\"alert__close\" aria-label=\"Dismiss\">&times;</button>"
        }
        html += "</div>"
        return html
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

    public init(
        tabs: [TabItem],
        activeTab: String,
        id: String? = nil
    ) {
        self.tabs = tabs
        self.activeTab = activeTab
        self.id = id
    }

    public func render() -> String {
        var html = "<nav class=\"tabs\""
        if let id { html += " id=\"\(id)\"" }
        html += " role=\"tablist\">"
        for tab in tabs {
            let active = tab.id == activeTab ? " tabs__tab--active" : ""
            html += "<button class=\"tabs__tab\(active)\" role=\"tab\" aria-selected=\"\(tab.id == activeTab ? "true" : "false")\" data-tab=\"\(htmlEscape(tab.id))\">\(htmlEscape(tab.label))</button>"
        }
        html += "</nav>"
        return html
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
        var html = "<div class=\"avatar \(size.rawValue)\""
        if let status {
            html += " data-status=\"\(status)\""
        }
        html += ">"
        if let src {
            html += "<img class=\"avatar__img\" src=\"\(htmlEscape(src))\" alt=\"\(htmlEscape(initials))\">"
        } else {
            html += "<span class=\"avatar__initials\">\(htmlEscape(initials))</span>"
        }
        if status != nil {
            html += "<span class=\"avatar__status\"></span>"
        }
        html += "</div>"
        return html
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
        let classes = "progress \(variant.rawValue) \(size.rawValue)"

        var html = "<div class=\"\(classes)\" role=\"progressbar\" aria-valuenow=\"\(Int(value * 100))\" aria-valuemin=\"0\" aria-valuemax=\"100\">"
        html += "<div class=\"progress__bar\" style=\"width: \(Int(value * 100))%\">"
        if showLabel {
            html += "<span class=\"progress__label\">\(Int(value * 100))%</span>"
        }
        html += "</div></div>"
        return html
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
            var html = "<div class=\"skeleton \(variant.rawValue)\""
            if let width { html += " style=\"width:\(width)\"" }
            if let height { html += " style=\"height:\(height)\"" }
            html += " aria-hidden=\"true\"></div>"
            result += html
        }
        return result
    }
}

// MARK: - WebUI Toast
public struct WebUIToast: View {
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
    }

    public func render() -> String {
        var html = "<div class=\"toast \(variant.rawValue)\" role=\"alert\""
        if let id { html += " id=\"\(id)\"" }
        html += ">"
        html += "<span class=\"toast__icon\"></span>"
        html += "<span class=\"toast__message\">\(htmlEscape(message))</span>"
        if dismissible {
            html += "<button class=\"toast__close\" aria-label=\"Dismiss\">&times;</button>"
        }
        html += "</div>"
        return html
    }
}

// MARK: - WebUI Modal
public struct WebUIModal: View {
    public let title: String
    public let id: String?
    public let children: [any View]
    public let footer: [any View]?

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
    }

    public func render() -> String {
        var html = "<div class=\"modal-overlay\""
        if let id { html += " id=\"\(id)\"" }
        html += ">"
        html += "<div class=\"modal\" role=\"dialog\" aria-modal=\"true\" aria-labelledby=\"\(id ?? "")-title\">"
        html += "<div class=\"modal__header\">"
        html += "<h2 class=\"modal__title\" id=\"\(id ?? "")-title\">\(htmlEscape(title))</h2>"
        html += "<button class=\"modal__close\" aria-label=\"Close\">&times;</button>"
        html += "</div>"
        html += "<div class=\"modal__body\">"
        for child in children {
            html += child.render()
        }
        html += "</div>"
        if let footer, !footer.isEmpty {
            html += "<div class=\"modal__footer\">"
            for item in footer {
                html += item.render()
            }
            html += "</div>"
        }
        html += "</div></div>"
        return html
    }
}

// MARK: - WebUI Table
public struct WebUITable: View {
    public let headers: [String]
    public let rows: [[any View]]
    public let striped: Bool
    public let hoverable: Bool
    public let compact: Bool
    public init(
        headers: [String],
        rows: [[any View]],
        striped: Bool = true,
        hoverable: Bool = true,
        compact: Bool = false
    ) {
        self.headers = headers
        self.rows = rows
        self.striped = striped
        self.hoverable = hoverable
        self.compact = compact
    }

    public func render() -> String {
        var classes = "table"
        if striped { classes += " table--striped" }
        if hoverable { classes += " table--hoverable" }
        if compact { classes += " table--compact" }

        var html = "<table class=\"\(classes)\">"
        if !headers.isEmpty {
            html += "<thead><tr>"
            for h in headers {
                html += "<th>\(htmlEscape(h))</th>"
            }
            html += "</tr></thead>"
        }
        html += "<tbody>"
        for row in rows {
            html += "<tr>"
            for cell in row {
                html += "<td>\(cell.render())</td>"
            }
            html += "</tr>"
        }
        html += "</tbody></table>"
        return html
    }
}

// MARK: - WebUI Chip
public struct WebUIChip: View {
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
    }

    public func render() -> String {
        var html = "<span class=\"chip \(variant.rawValue)\""
        if let id { html += " id=\"\(id)\"" }
        html += ">"
        html += "<span class=\"chip__label\">\(htmlEscape(text))</span>"
        if removable {
            html += "<button class=\"chip__remove\" aria-label=\"Remove\">&times;</button>"
        }
        html += "</span>"
        return html
    }
}

// MARK: - WebUI Empty State
public struct WebUIEmptyState: View {
    public let icon: String
    public let title: String
    public let message: String
    public let action: (label: String, id: String)?

    public init(
        icon: String = "📭",
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
        var html = "<div class=\"empty-state\">"
        html += "<div class=\"empty-state__icon\">\(icon)</div>"
        html += "<h3 class=\"empty-state__title\">\(htmlEscape(title))</h3>"
        html += "<p class=\"empty-state__message\">\(htmlEscape(message))</p>"
        if let (label, actionId) = action {
            html += "<button class=\"button button--primary\" id=\"\(htmlEscape(actionId))\">\(htmlEscape(label))</button>"
        }
        html += "</div>"
        return html
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
        var html = "<div class=\"spinner \(size.rawValue)\" role=\"status\""
        if let label { html += " aria-label=\"\(htmlEscape(label))\"" }
        html += ">"
        html += "<div class=\"spinner__ring\"></div>"
        if let label {
            html += "<span class=\"spinner__label\">\(htmlEscape(label))</span>"
        }
        html += "</div>"
        return html
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
        var html = "<div class=\"tooltip-container\">"
        for child in children {
            html += child.render()
        }
        html += "<div class=\"tooltip \(position.rawValue)\" role=\"tooltip\">"
        html += "<span class=\"tooltip__arrow\"></span>"
        html += "<span class=\"tooltip__text\">\(htmlEscape(text))</span>"
        html += "</div></div>"
        return html
    }
}
