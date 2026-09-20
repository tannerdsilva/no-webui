import Foundation
import WebUICore

// MARK: - Sidebar

/// one navigation entry in a ``WebUISidebar``. when `href` is set the item
/// renders as an `<a>` (page navigation); otherwise it renders as a click
/// row routed to the sidebar's `onSelect` handler.
public struct WebUISidebarItem: Sendable, Equatable {
    public let id: String
    public let label: String
    public let icon: IconName
    public let badge: String?
    public let href: String?

    public init(id: String, label: String, icon: IconName, badge: String? = nil, href: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.badge = badge
        self.href = href
    }
}

/// a vertical navigation sidebar. `.rail` collapses the sidebar to an
/// icon-only nav rail (labels + section header hidden); `.full` renders the
/// label rows with an optional section header. every item routes a click to
/// the single `onSelect` handler, dispatched on `event.data["targetId"]`
/// (the clicked row's id). the row's children are `pointer-events: none` so
/// clicks resolve to the row itself.
public struct WebUISidebar: View {

    public enum Style: String, Sendable {
        case full
        case rail
    }

    public let items: [WebUISidebarItem]
    public let activeID: String?
    /// stable component id — the routing anchor that survives fragment
    /// re-renders (see ``controlAttributes``).
    public let id: String
    public let style: Style
    public let header: String?
    public let onSelect: EventHandler?

    public init(
        items: [WebUISidebarItem],
        activeID: String? = nil,
        id: String,
        style: Style = .full,
        header: String? = nil,
        onSelect: EventHandler? = nil
    ) {
        self.items = items
        self.activeID = activeID
        self.id = id
        self.style = style
        self.header = header
        self.onSelect = onSelect
    }

    public func render() -> String {
        let cls = style == .rail ? "sidebar sidebar--collapsed" : "sidebar"
        let attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        var html = "<nav class=\"\(cls)\"\(attrs)>"
        html += "<div class=\"sidebar__section\">"
        if let header, style == .full {
            html += "<div class=\"sidebar__section-label\">\(htmlEscape(header))</div>"
        }
        for item in items {
            let active = item.id == activeID ? " sidebar__item--active" : ""
            let link = item.href != nil
            html += link ? "<a" : "<div"
            html += " class=\"sidebar__item\(active)\""
            if let href = item.href {
                html += " href=\"\(htmlEscape(href))\""
            } else {
                html += " id=\"\(htmlEscape(item.id))\""
            }
            html += ">"
            html += "<span class=\"sidebar__icon fill-slot\">"
            html += WebUIIcon(item.icon, size: .slot).render()
            html += "</span>"
            html += "<span class=\"sidebar__item-label\">\(htmlEscape(item.label))</span>"
            if let badge = item.badge {
                html += "<span class=\"sidebar__item-badge\">\(htmlEscape(badge))</span>"
            }
            html += link ? "</a>" : "</div>"
        }
        html += "</div>"
        html += "</nav>"
        return html
    }
}

// MARK: - Segmented control

/// one option in a ``WebUISegmentedControl``.
public struct WebUISegmentedItem: Sendable, Equatable {
    public let id: String
    public let label: String
    public let count: Int?

    public init(id: String, label: String, count: Int? = nil) {
        self.id = id
        self.label = label
        self.count = count
    }
}

/// a segmented (tab-like) single-select control. the selected option clips a
/// count badge; clicks route to the single `onSelect` handler, dispatched on
/// `event.data["targetId"]`.
public struct WebUISegmentedControl: View {

    public let items: [WebUISegmentedItem]
    public let selectedID: String?
    public let id: String
    public let size: WebUISegmentedControlSize?
    public let onSelect: EventHandler?

    public init(
        items: [WebUISegmentedItem],
        selectedID: String? = nil,
        id: String,
        size: WebUISegmentedControlSize? = nil,
        onSelect: EventHandler? = nil
    ) {
        self.items = items
        self.selectedID = selectedID
        self.id = id
        self.size = size
        self.onSelect = onSelect
    }

    public func render() -> String {
        var cls = "segmented"
        if let size { cls += " \(size.rawValue)" }
        let attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        var html = "<div class=\"\(cls)\"\(attrs)>"
        for item in items {
            let active = item.id == selectedID ? " segmented__item--active" : ""
            let selected = item.id == selectedID ? "true" : "false"
            html += "<div class=\"segmented__item\(active)\" id=\"\(htmlEscape(item.id))\" role=\"tab\" aria-selected=\"\(selected)\">"
            html += "<span class=\"segmented__label\">\(htmlEscape(item.label))</span>"
            if let count = item.count {
                html += "<span class=\"segmented__count\">\(count)</span>"
            }
            html += "</div>"
        }
        html += "</div>"
        return html
    }
}

/// the supported sizes of ``WebUISegmentedControl``.
public enum WebUISegmentedControlSize: String, Sendable {
    case sm = "segmented--sm"
    case md = "segmented--md"
    case lg = "segmented--lg"
}

// MARK: - Search field

/// a labelled search / filter input with a leading search glyph. typing
/// routes an `input` event to `onInput` (`event.data["value"]`).
public struct WebUISearchField: View {

    public let placeholder: String
    public let id: String
    public let value: String?
    public let onInput: EventHandler?

    public init(
        placeholder: String,
        id: String,
        value: String? = nil,
        onInput: EventHandler? = nil
    ) {
        self.placeholder = placeholder
        self.id = id
        self.value = value
        self.onInput = onInput
    }

    public func render() -> String {
        let attrs = controlAttributes(id: id, event: .input, handler: onInput)
        var html = "<div class=\"search-field\"\(attrs)>"
        html += "<span class=\"search-field__icon\">"
        html += WebUIIcon(.search, size: .slot).render()
        html += "</span>"
        html += "<input class=\"search-field__input\" type=\"search\" placeholder=\"\(htmlEscape(placeholder))\""
        if let value, !value.isEmpty {
            html += " value=\"\(htmlEscape(value))\""
        }
        html += ">"
        html += "</div>"
        return html
    }
}

// MARK: - List view

/// one selectable row in a ``WebUIListView``.
public struct WebUIListItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let meta: String?
    public let icon: IconName?

    public init(id: String, title: String, subtitle: String? = nil, meta: String? = nil, icon: IconName? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.icon = icon
    }
}

/// a vertical list of selectable rows (conversations, sessions, files…).
/// rows route a click to the single `onSelect` handler, dispatched on
/// `event.data["targetId"]`. row children are `pointer-events: none` so
/// clicks resolve to the row.
public struct WebUIListView: View {

    public let items: [WebUIListItem]
    public let selectedID: String?
    public let id: String
    public let onSelect: EventHandler?

    public init(
        items: [WebUIListItem],
        selectedID: String? = nil,
        id: String,
        onSelect: EventHandler? = nil
    ) {
        self.items = items
        self.selectedID = selectedID
        self.id = id
        self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        var html = "<ul class=\"list\" id=\"\(htmlEscape(id))\"\(attrs)>"
        for item in items {
            let selected = item.id == selectedID ? " list__item--selected" : ""
            html += "<li class=\"list__item\(selected)\" id=\"\(htmlEscape(item.id))\">"
            if let icon = item.icon {
                html += "<span class=\"list__icon fill-slot\">"
                html += WebUIIcon(icon, size: .slot).render()
                html += "</span>"
            }
            html += "<span class=\"list__body\">"
            html += "<span class=\"list__title\">\(htmlEscape(item.title))</span>"
            if let subtitle = item.subtitle {
                html += "<span class=\"list__sub\">\(htmlEscape(subtitle))</span>"
            }
            html += "</span>"
            if let meta = item.meta {
                html += "<span class=\"list__meta\">\(htmlEscape(meta))</span>"
            }
            html += "</li>"
        }
        html += "</ul>"
        return html
    }
}

// MARK: - Composer

/// a docked message composer: an input row (textarea + tool glyphs) with a
/// circular send button. submits a `submit` event to `onSubmit` with the
/// form payload (`event.data["message"]`). the caller supplies a fresh
/// `inputID` per render so a sent message can't be restored into the box;
/// the form keeps the stable `id` routing anchor.
///
/// the send button is **enabled by default** and never auto-disabled. the
/// host opts into a disabled state explicitly by passing `disabled: true` —
/// the component imposes no automatic busy/disabled behavior.
public struct WebUIComposer: View {

    public let placeholder: String
    public let inputID: String
    public let id: String
    public let disabled: Bool
    public let onSubmit: EventHandler?
    /// when set the attach tool is wired as an interactive control; when nil
    /// it renders disabled so the affordance is honest rather than a dead
    /// button the user clicks and nothing happens.
    public let onAttach: EventHandler?
    /// an optional muted helper line shown under the input row (e.g. the
    /// enter-to-send hint).
    public let hint: String?

    public init(
        placeholder: String,
        inputID: String,
        id: String,
        disabled: Bool = false,
        onSubmit: EventHandler? = nil,
        onAttach: EventHandler? = nil,
        hint: String? = nil
    ) {
        self.placeholder = placeholder
        self.inputID = inputID
        self.id = id
        self.disabled = disabled
        self.onSubmit = onSubmit
        self.onAttach = onAttach
        self.hint = hint
    }

    public func render() -> String {
        let attrs = controlAttributes(id: id, event: .submit, handler: onSubmit)
        var html = "<form class=\"composer\" id=\"\(htmlEscape(id))\"\(attrs)>"
        html += "<div class=\"composer__input-row\">"
        html += "<textarea class=\"composer__textarea\" id=\"\(htmlEscape(inputID))\" name=\"message\" rows=\"1\" placeholder=\"\(htmlEscape(placeholder))\"></textarea>"
        html += "<div class=\"composer__tools\">"
        let attachAttrs = onAttach != nil
            ? controlAttributes(id: id + "-attach", event: .click, handler: onAttach)
            : " disabled aria-disabled=\"true\""
        let toolClass = onAttach != nil ? "composer__tool" : "composer__tool composer__tool--disabled"
        html += "<button type=\"button\" class=\"\(toolClass)\" aria-label=\"attach\"\(attachAttrs)>"
        html += WebUIIcon(.paperclip, size: .slot).render()
        html += "</button>"
        html += "</div>"
        html += "<button type=\"submit\" class=\"composer__send\" aria-label=\"send\""
        if disabled { html += " disabled" }
        html += ">"
        html += WebUIIcon(.send, size: .slot).render()
        html += "</button>"
        html += "</div>"
        if let hint {
            html += "<div class=\"composer__hint\">\(htmlEscape(hint))</div>"
        }
        html += "</form>"
        return html
    }
}

// MARK: - Panel

/// a titled side panel: a header row (title, optional count, trailing
/// actions) above a body that owns its own scroll. the base for the
/// conversations list and the workspace/file-tree pane.
public struct WebUIPanel: View {

    /// which side carries the divider against an adjacent pane.
    public enum Edge: String, Sendable {
        case none
        case leading  = "panel panel--leading"
        case trailing = "panel panel--trailing"
    }

    public let title: String
    public let subtitle: String?
    public let actions: [any View]
    public let content: [any View]
    public let id: String?
    public let edge: Edge

    public init(
        title: String,
        subtitle: String? = nil,
        id: String? = nil,
        edge: Edge = .leading,
        actions: [any View] = [],
        @ViewBuilder content: () -> [any View]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.id = id
        self.edge = edge
        self.actions = actions
        self.content = content()
    }

    public func render() -> String {
        var html = "<section class=\"\(edge.rawValue)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += ">"
        html += "<header class=\"panel__header\">"
        html += "<div class=\"panel__title\">\(htmlEscape(title))"
        if let subtitle = subtitle {
            html += "<span class=\"panel__subtitle\">\(htmlEscape(subtitle))</span>"
        }
        html += "</div>"
        if !actions.isEmpty {
            html += "<div class=\"panel__actions\">"
            for action in actions {
                html += action.render()
            }
            html += "</div>"
        }
        html += "</header>"
        html += "<div class=\"panel__body\">"
        for child in content {
            html += child.render()
        }
        html += "</div>"
        html += "</section>"
        return html
    }
}
