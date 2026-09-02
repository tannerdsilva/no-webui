import Foundation
import Logging
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
        if let id { html += " id=\"\(htmlEscape(id))\"" }
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
        if let id { html += " id=\"\(htmlEscape(id))\"" }
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
        if let id { html += " id=\"\(htmlEscape(id))\"" }
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
        let dismissal = makeDismissal(ariaLabel: "Dismiss")
        var html = "<div class=\"alert \(variant.rawValue)\" role=\"alert\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        if dismissible || onDismiss != nil { html += " data-dismissible" }
        html += ">"
        html += "<div class=\"alert__icon fill-slot\">" + WebUIIcon(icon, size: .slot).render() + "</div>"
        html += "<div class=\"alert__body\">"
        if let title {
            html += "<div class=\"alert__title\">\(htmlEscape(title))</div>"
        }
        html += "<div class=\"alert__message\">\(htmlEscape(message))</div>"
        html += "</div>"
        if dismissible || onDismiss != nil {
            html += dismissal.buttonHTML
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
        if let id { html += " id=\"\(htmlEscape(id))\"" }
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
            html += " data-status=\"\(htmlEscape(status))\""
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
        let dismissal = makeDismissal(ariaLabel: "Dismiss")
        var html = "<div class=\"toast \(variant.rawValue)\" role=\"alert\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        html += ">"
        html += "<span class=\"toast__icon\"></span>"
        html += "<span class=\"toast__message\">\(htmlEscape(message))</span>"
        if dismissible || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += "</div>"
        return html
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
        let dismissal = makeDismissal(ariaLabel: "Close")
        var html = "<div class=\"modal-overlay\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        html += ">"
        html += "<div class=\"modal\" role=\"dialog\" aria-modal=\"true\" aria-labelledby=\"\(htmlEscape(id ?? ""))-title\">"
        html += "<div class=\"modal__header\">"
        html += "<h2 class=\"modal__title\" id=\"\(htmlEscape(id ?? ""))-title\">\(htmlEscape(title))</h2>"
        html += dismissal.buttonHTML
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
        var classes = "table"
        if striped { classes += " table--striped" }
        if hoverable { classes += " table--hoverable" }
        if compact { classes += " table--compact" }
        if responsive { classes += " table--responsive" }

        // interactive geometry
        let base = id ?? "webui-table"
        let hasSelect = selectable && !rows.isEmpty && rowIds.count == rows.count
        let hasExpand = !(rowDetails?.isEmpty ?? true) && !rows.isEmpty
        let totalColumns = headers.count + (hasSelect ? 1 : 0) + (hasExpand ? 1 : 0)

        let interactiveWanted = onSort != nil || onSelectAll != nil || onSelect != nil || onToggleExpand != nil
        if interactiveWanted, id == nil {
            Self.log.warning("WebUITable: typed handlers require a stable `id:` for routing; rendering controls statically.")
        }
        // `me` is the ref the typed handlers receive; the table root carries
        // the caller's stable `id`, so `me.update(...)` patches the table in
        // place and re-emitted fragments carry identical routing ids.
        let me = ElementRef.stable(base)
        let wired = interactiveWanted && id != nil

        let sortArrow = "<svg class=\"sort__arrow\" viewBox=\"0 0 10 10\" width=\"10\" height=\"10\" fill=\"none\" aria-hidden=\"true\"><path d=\"M2 6.5L5 3.5l3 3\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"
        let expandIcon = "<svg class=\"table__expand-icon\" viewBox=\"0 0 10 10\" width=\"10\" height=\"10\" fill=\"none\" aria-hidden=\"true\"><path d=\"M3.5 2.5L6.5 5l-3 2.5\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"

        func alignmentClass(_ index: Int) -> String? {
            guard index < alignments.count else { return nil }
            switch alignments[index] {
            case .leading: return nil
            case .center: return "align-center"
            case .trailing: return "num"
            }
        }

        var tableOpen = "<table"
        if let id { tableOpen += " id=\"\(htmlEscape(id))\"" }
        tableOpen += " class=\"\(classes)\">"

        var html = tableOpen
        if !headers.isEmpty {
            html += "<thead><tr>"
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
                html += "<th class=\"table__select-col align-center\" scope=\"col\"><span class=\"table__select\" id=\"\(htmlEscape(base))-select-all\" role=\"checkbox\" aria-checked=\"\(state)\" aria-label=\"Select all rows\" tabindex=\"0\"\(selectAllAttrs)></span></th>"
            }
            if hasExpand {
                html += "<th class=\"table__expand-col\" aria-hidden=\"true\"></th>"
            }
            for (i, h) in headers.enumerated() {
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
                    html += "<th class=\"\(sortPrefix)\" aria-sort=\"\(aria)\">"
                    html += "<span class=\"sort sort--active\(desc)\" id=\"\(htmlEscape(base))-sort-\(i)\"\(sortAttrs)>\(htmlEscape(h))\(sortArrow)</span>"
                    html += "</th>"
                } else if sortableColumns.contains(i) {
                    html += "<th class=\"\(sortPrefix)\">"
                    html += "<span class=\"sort\" id=\"\(htmlEscape(base))-sort-\(i)\"\(sortAttrs)>\(htmlEscape(h))\(sortArrow)</span>"
                    html += "</th>"
                } else if let a = align {
                    html += "<th class=\"\(a)\">\(htmlEscape(h))</th>"
                } else {
                    html += "<th>\(htmlEscape(h))</th>"
                }
            }
            html += "</tr></thead>"
        }
        html += "<tbody>"
        if rows.isEmpty, let empty = emptyState {
            let colspan = totalColumns > 0 ? totalColumns : 1
            html += "<tr><td colspan=\"\(colspan)\" class=\"table__empty\">"
            html += "<div class=\"table__empty-icon fill-slot\">" + WebUIIcon(empty.icon, size: .slot).render() + "</div>"
            html += "<div class=\"table__empty-title\">\(htmlEscape(empty.title))</div>"
            if !empty.message.isEmpty {
                html += "<div class=\"table__empty-message\">\(htmlEscape(empty.message))</div>"
            }
            html += "</td></tr>"
        } else {
            for (rowIndex, row) in rows.enumerated() {
                let rowId = rowIndex < rowIds.count ? rowIds[rowIndex] : "row-\(rowIndex)"
                let selected = selectedRows.contains(rowId)
                let expanded = expandedRows.contains(rowId)
                let trClass = [
                    selected ? "tr--selected" : nil,
                    expanded ? "tr--expanded" : nil,
                ].compactMap { $0 }.joined(separator: " ")
                let trAttrs = trClass.isEmpty ? "" : " class=\"\(trClass)\""
                html += "<tr\(trAttrs)>"
                if hasSelect {
                    var selectHandler: EventHandler? = nil
                    if let onSelect {
                        let h: TableSelectRowHandler = onSelect
                        selectHandler = { event in await h(me, rowId) }
                    }
                    let selectAttrs = wired
                        ? controlAttributes(id: "\(base)-select-\(rowId)", handler: selectHandler)
                        : ""
                    html += "<td class=\"table__select-col align-center\"><span class=\"table__select\" id=\"\(htmlEscape(base))-select-\(htmlEscape(rowId))\" role=\"checkbox\" aria-checked=\"\(selected)\" aria-label=\"Select row \(htmlEscape(rowId))\" tabindex=\"0\"\(selectAttrs)></span></td>"
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
                        html += "<td class=\"table__expand-col\"><button type=\"button\" class=\"table__expand-btn\" id=\"\(htmlEscape(base))-expand-\(htmlEscape(rowId))\" aria-expanded=\"\(expanded)\"\(expandAttrs)>\(expandIcon)</button></td>"
                    } else {
                        html += "<td class=\"table__expand-col\"><button type=\"button\" class=\"table__expand-btn\" id=\"\(htmlEscape(base))-expand-\(htmlEscape(rowId))\" aria-disabled=\"true\" disabled\(expandAttrs)>\(expandIcon)</button></td>"
                    }
                }
                for (i, cell) in row.enumerated() {
                    var attrs = ""
                    if responsive, i < headers.count {
                        attrs += "data-label=\"\(htmlEscape(headers[i]))\""
                    }
                    if let a = alignmentClass(i) {
                        if attrs.isEmpty {
                            attrs += "class=\"\(a)\""
                        } else {
                            attrs += " class=\"\(a)\""
                        }
                    }
                    let tdAttrs = attrs.isEmpty ? "" : " " + attrs
                    html += "<td\(tdAttrs)>\(cell.render())</td>"
                }
                html += "</tr>"
                if hasExpand, expanded, let detail = rowDetails?[rowId] {
                    html += "<tr class=\"table__detail-row\"><td colspan=\"\(totalColumns)\"><div class=\"table__detail\">\(detail.render())</div></td></tr>"
                }
            }
        }
        html += "</tbody>"
        if let footer {
            html += "<tfoot><tr>"
            for (i, cell) in footer.enumerated() {
                if let a = alignmentClass(i) {
                    html += "<td class=\"\(a)\">\(cell.render())</td>"
                } else {
                    html += "<td>\(cell.render())</td>"
                }
            }
            html += "</tr></tfoot>"
        }
        html += "</table>"
        if wrapped {
            html = "<div class=\"table-wrap\">" + html + "</div>"
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
        let dismissal = makeDismissal(ariaLabel: "Remove")
        var html = "<span class=\"chip \(variant.rawValue)\""
        if let elementID = dismissal.elementID ?? id {
            html += " id=\"\(htmlEscape(elementID))\""
        }
        html += ">"
        html += "<span class=\"chip__label\">\(htmlEscape(text))</span>"
        if removable || onDismiss != nil {
            html += dismissal.buttonHTML
        }
        html += "</span>"
        return html
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
        var html = "<div class=\"empty-state\">"
        html += "<div class=\"empty-state__icon fill-slot\">" + WebUIIcon(icon, size: .slot).render() + "</div>"
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
        var html = "<div class=\"\(size.rawValue)\">"
        html += "<span class=\"stat__label\">\(htmlEscape(label))</span>"
        html += "<span class=\"stat__value\">\(htmlEscape(value))</span>"
        if let trend, let trendDirection {
            let arrowPath = trendDirection == .up ? "M2 6.5L5 3.5l3 3" : "M2 3.5L5 6.5l3-3"
            let arrow = "<svg class=\"stat__trend-arrow\" viewBox=\"0 0 10 10\" width=\"10\" height=\"10\" fill=\"none\" aria-hidden=\"true\"><path d=\"\(arrowPath)\" stroke=\"currentColor\" stroke-width=\"1.5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"
            html += "<span class=\"stat__row\">"
            html += "<span class=\"stat__trend \(trendDirection.rawValue)\">\(arrow)\(htmlEscape(trend))</span>"
            if let compare {
                html += "<span class=\"stat__compare\">\(htmlEscape(compare))</span>"
            }
            html += "</span>"
        } else if let compare {
            html += "<span class=\"stat__compare\">\(htmlEscape(compare))</span>"
        }
        if let spark, spark.count >= 2 {
            html += "<span class=\"stat__spark\">"
            html += sparklineSVG(spark)
            html += "</span>"
        }
        html += "</div>"
        return html
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
            return String(format: "%.1f,%.1f", x, y)
        }
        let line = coords.joined(separator: " ")
        let area = "\(coords.first ?? "0,16") \(line) 100,32 0,32"
        return "<svg viewBox=\"0 0 100 32\" preserveAspectRatio=\"none\" aria-hidden=\"true\">"
            + "<polygon class=\"stat__spark-area\" points=\"\(area)\"/>"
            + "<polyline class=\"stat__spark-line\" points=\"\(line)\"/></svg>"
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

        var html = "<nav class=\"pagination\" aria-label=\"Pagination\">"
        let prevIdAttr = pid("prev").map { " id=\"\($0)\"" } ?? ""
        let prevDisabled = page <= 1 ? " disabled" : ""
        var prevHandler: EventHandler? = nil
        if wired, let onPageChange {
            let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
            prevHandler = { event in await h(me, max(1, page - 1)) }
        }
        let prevRoute = wired
            ? controlAttributes(id: base.map { "\($0)-prev" } ?? "", handler: prevHandler)
            : ""
        html += "<button class=\"pagination__btn\"\(prevIdAttr) type=\"button\" aria-label=\"Previous page\"\(prevDisabled)\(prevRoute)>&#8249;</button>"
        for item in pageWindow(page: page, pages: pages) {
            switch item {
            case .ellipsis:
                html += "<span class=\"pagination__ellipsis\">…</span>"
            case .number(let n):
                let isActive = n == page
                let cls = isActive ? "pagination__btn pagination__btn--active" : "pagination__btn"
                let idAttr = pid("page-\(n)").map { " id=\"\($0)\"" } ?? ""
                let current = isActive ? " aria-current=\"page\"" : ""
                var pageHandler: EventHandler? = nil
                if wired, let onPageChange {
                    let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
                    pageHandler = { event in await h(me, n) }
                }
                let pageRoute = wired
                    ? controlAttributes(id: base.map { "\($0)-page-\(n)" } ?? "", handler: pageHandler)
                    : ""
                html += "<button class=\"\(cls)\"\(idAttr) type=\"button\"\(current)\(pageRoute)>\(n)</button>"
            }
        }
        let nextIdAttr = pid("next").map { " id=\"\($0)\"" } ?? ""
        let nextDisabled = page >= pages ? " disabled" : ""
        var nextHandler: EventHandler? = nil
        if wired, let onPageChange {
            let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onPageChange
            nextHandler = { event in await h(me, min(pages, page + 1)) }
        }
        let nextRoute = wired
            ? controlAttributes(id: base.map { "\($0)-next" } ?? "", handler: nextHandler)
            : ""
        html += "<button class=\"pagination__btn\"\(nextIdAttr) type=\"button\" aria-label=\"Next page\"\(nextDisabled)\(nextRoute)>&#8250;</button>"
        if let rowsPerPage {
            let rowsIdAttr = pid("rows").map { " id=\"\($0)\"" } ?? ""
            var rowsHandler: EventHandler? = nil
            if wired, let onRowsPerPageChange {
                let h: @Sendable (ElementRef, Int) async -> [FragmentUpdate] = onRowsPerPageChange
                rowsHandler = { event in
                    let raw = event.data["value"] ?? ""
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
            html += "<span class=\"pagination__meta\"><label>Rows per page</label><select class=\"select\"\(rowsIdAttr)\(rowsRoute)>"
            for opt in rowsPerPageOptions {
                let selected = opt == rowsPerPage ? " selected" : ""
                html += "<option value=\"\(opt)\"\(selected)>\(opt)</option>"
            }
            html += "</select></span>"
        }
        html += "</nav>"
        return html
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
        var html = "<div class=\"\(orientation.rawValue)\">"
        for event in events {
            let statusCls = event.status == .plain ? "" : " \(event.status.rawValue)"
            html += "<div class=\"timeline__event\(statusCls)\"><span class=\"timeline__dot\"></span>"
            html += "<span class=\"timeline__time\">\(htmlEscape(event.time))</span>"
            html += "<div class=\"timeline__title\">\(htmlEscape(event.title))</div>"
            if let desc = event.desc {
                html += "<div class=\"timeline__desc\">\(htmlEscape(desc))</div>"
            }
            html += "</div>"
        }
        html += "</div>"
        return html
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

    public init(nodes: [Node], id: String? = nil, expanded: Set<String> = [], selected: String? = nil) {
        self.nodes = nodes
        self.id = id
        self.expanded = expanded
        self.selected = selected
    }

    public func render() -> String {
        var html = "<div class=\"tree\">"
        for node in nodes { html += renderNode(node) }
        html += "</div>"
        return html
    }

    private func renderNode(_ node: Node) -> String {
        let hasChildren = !(node.children?.isEmpty ?? true)
        let isOpen = hasChildren && expanded.contains(node.id)
        let nodeCls = isOpen ? "tree__node tree__node--open" : "tree__node"
        let rowCls = selected == node.id ? "tree__row tree__row--selected" : "tree__row"
        let caretCls = hasChildren ? "tree__caret" : "tree__caret tree__caret--leaf"
        let rowIdAttr = id.map { " id=\"\(htmlEscape($0))-node-\(htmlEscape(node.id))\"" } ?? ""

        var html = "<div class=\"\(nodeCls)\">"
        html += "<div class=\"\(rowCls)\"\(rowIdAttr)>"
        html += "<span class=\"\(caretCls)\"></span>"
        if let icon = node.icon {
            html += "<span class=\"tree__icon fill-slot\">" + WebUIIcon(icon, size: .slot).render() + "</span>"
        }
        html += "<span class=\"tree__label\">\(htmlEscape(node.label))</span>"
        html += "</div>"
        if hasChildren {
            html += "<div class=\"tree__children\">"
            for child in node.children! { html += renderNode(child) }
            html += "</div>"
        }
        html += "</div>"
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
        let all = items + [current]
        let sep: String = slash ? "/" : "›"
        let base = id.map { htmlEscape($0) }
        let slashCls = slash ? " breadcrumb--slash" : ""

        // which segments render as links (head), which are collapsed into
        // the ellipsis, which render as the tail
        let collapsed = collapse && all.count > maxItems
        let headCount = collapsed ? 1 : all.count - 1
        let tailCount = collapsed ? 2 : 0

        func itemHTML(_ item: Item, index: Int, isCurrent: Bool) -> String {
            let idAttr = isCurrent ? "" : base.map { " id=\"\($0)-item-\(index)\"" } ?? ""
            if isCurrent {
                return "<span class=\"breadcrumb__item breadcrumb__item--current\" aria-current=\"page\">\(htmlEscape(item.label))</span>"
            }
            if let href = item.href {
                // canonical URL policy: a blocked scheme degrades to plain
                // text (never an href) — mirrors the Link/Image primitives.
                guard let safe = sanitizeURL(href) else {
                    return "<span class=\"breadcrumb__item\"\(idAttr)>\(htmlEscape(item.label))</span>"
                }
                return "<a class=\"breadcrumb__item\"\(idAttr) href=\"\(htmlEscape(safe))\">\(htmlEscape(item.label))</a>"
            }
            return "<span class=\"breadcrumb__item\"\(idAttr)>\(htmlEscape(item.label))</span>"
        }
        func sepHTML() -> String {
            "<span class=\"breadcrumb__separator\" aria-hidden=\"true\">\(htmlEscape(sep))</span>"
        }

        var html = "<nav class=\"breadcrumb\(slashCls)\" aria-label=\"Breadcrumb\">"
        // head (links)
        for i in 0..<headCount {
            html += itemHTML(all[i], index: i, isCurrent: false)
            html += sepHTML()
        }
        // collapsed middle
        if collapsed {
            let ellipsisId = base.map { " id=\"\($0)-ellipsis\"" } ?? ""
            html += "<button type=\"button\" class=\"breadcrumb__ellipsis\"\(ellipsisId) aria-label=\"Show omitted items\">…</button>"
            html += sepHTML()
        }
        // tail (last N−1 as links, final as current)
        let tailStart = all.count - tailCount
        for i in 0..<tailCount {
            let idx = tailStart + i
            let isCurrent = idx == all.count - 1
            html += itemHTML(all[idx], index: idx, isCurrent: isCurrent)
            if !isCurrent { html += sepHTML() }
        }
        html += "</nav>"
        return html
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
        var html = "<dl class=\"list--desc\">"
        for item in items {
            html += "<dt>\(htmlEscape(item.term))</dt>"
            html += "<dd>\(htmlEscape(item.detail))</dd>"
        }
        html += "</dl>"
        return html
    }
}
