import WebUICore

// ============================================================================
// MARK: - Navigation & chrome extras
// ============================================================================

// MARK: WebUI Navbar
/// a top application bar: brand, nav links, and trailing actions.
public struct WebUINavbar: View {
    public struct Link: Sendable {
        public let label: String
        public let href: String
        public let active: Bool
        public init(_ label: String, href: String, active: Bool = false) {
            self.label = label; self.href = href; self.active = active
        }
    }
    /// the navbar's search slot: a field plus an optional key hint.
    public struct Search: Sendable {
        public let placeholder: String
        /// key hint rendered in the trailing kbd, e.g. "Ctrl K".
        public let shortcut: String?
        public let id: String?
        public init(placeholder: String = "Search", shortcut: String? = nil, id: String? = nil) {
            self.placeholder = placeholder
            self.shortcut = shortcut
            self.id = id
        }
    }
    public let brand: String?
    public let links: [Link]
    public let actions: [any View]
    public let sticky: Bool
    /// search slot; `nil` renders no field.
    public let search: Search?
    /// hamburger for the narrow breakpoint (the sheet hides it above it).
    public let mobileMenu: Bool
    /// accessible name for the hamburger.
    public let mobileMenuLabel: String
    /// stable container id; when set with `onNavigate` each link self-wires
    /// (`targetId == "<id>-link-<index>"`).
    public let id: String?
    public let onNavigate: EventHandler?
    public init(brand: String? = nil, links: [Link] = [], sticky: Bool = false,
                search: Search? = nil, mobileMenu: Bool = false,
                mobileMenuLabel: String = "Menu",
                id: String? = nil, onNavigate: EventHandler? = nil,
                @ViewBuilder actions: () -> [any View]) {
        self.brand = brand; self.links = links; self.sticky = sticky
        self.search = search; self.mobileMenu = mobileMenu
        self.mobileMenuLabel = mobileMenuLabel
        self.id = id; self.onNavigate = onNavigate; self.actions = actions()
    }

    public func render() -> String {
        let attrs: String
        if let id, let onNavigate {
            attrs = controlAttributes(id: id, event: .click, handler: onNavigate)
        } else {
            attrs = ""
        }
        var html = Tag.begin("nav", Tag.classes(["navbar", sticky ? " navbar--sticky" : ""]), attrs)
        if let brand {
            html += Tag.begin("a", Tag.classes(["navbar__brand"]), Tag.attr("href", "/"))
            html += Tag.element("span", [Tag.classes(["navbar__brand-mark"])], "")
            html += htmlEscape(brand)
            html += Tag.end("a")
        }
        if let search {
            html += Tag.begin("label", Tag.classes(["navbar__search"]), Tag.attr("role", "search"))
            html += Tag.void(
                "input", Tag.attr("type", "search"),
                search.id.map { Tag.escAttr("id", $0) } ?? "",
                Tag.escAttr("placeholder", search.placeholder),
                Tag.escAttr("aria-label", search.placeholder))
            if let shortcut = search.shortcut { html += Tag.element("kbd", [], htmlEscape(shortcut)) }
            html += Tag.end("label")
        }
        if !links.isEmpty {
            html += Tag.begin("div", Tag.classes(["navbar__links"]))
            for (index, link) in links.enumerated() {
                let linkID = id.map { Tag.escAttr("id", "\($0)-link-\(index)") } ?? ""
                html += Tag.element("a",
                    [Tag.classes(["navbar__link", link.active ? " navbar__link--active" : ""]), linkID,
                     Tag.escAttr("href", link.href)],
                    htmlEscape(link.label))
            }
            html += Tag.end("div")
        }
        if !actions.isEmpty {
            html += Tag.begin("div", Tag.classes(["navbar__actions"]))
            for a in actions { html += a.render() }
            html += Tag.end("div")
        }
        if mobileMenu {
            html += Tag.begin("button", Tag.classes(["navbar__hamburger"]), Tag.attr("type", "button"), Tag.escAttr("aria-label", mobileMenuLabel))
            html += Tag.element("span", [], "") + Tag.element("span", [], "") + Tag.element("span", [], "")
            html += Tag.end("button")
        }
        html += Tag.end("nav")
        return html
    }
}

// MARK: WebUI Bottom Nav
/// mobile bottom navigation bar with icons, labels, and badges.
public struct WebUIBottomNav: View {
    public struct Item: Sendable {
        public let label: String
        public let icon: IconName
        public let badge: String?
        public let active: Bool
        public init(_ label: String, icon: IconName, badge: String? = nil, active: Bool = false) {
            self.label = label; self.icon = icon; self.badge = badge; self.active = active
        }
    }
    public let items: [Item]
    /// stable container id; when set with `onSelect` each item self-wires
    /// (`targetId == "<id>-item-<index>"`).
    public let id: String?
    public let onSelect: EventHandler?
    public init(items: [Item], id: String? = nil, onSelect: EventHandler? = nil) {
        self.items = items; self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("nav", Tag.classes(["bottom-nav"]), attrs, Tag.attr("aria-label", "Primary"))
        for (index, item) in items.enumerated() {
            let itemID = id.map { Tag.escAttr("id", "\($0)-item-\(index)") } ?? ""
            html += Tag.begin("a", Tag.classes(["bottom-nav__item", item.active ? " bottom-nav__item--active" : ""]), itemID, Tag.attr("href", "#"))
            html += Tag.element("span", [Tag.classes(["bottom-nav__icon"])], WebUIIcon(item.icon, size: .medium).render())
            if let badge = item.badge {
                html += Tag.element("span", [Tag.classes(["bottom-nav__badge"])], htmlEscape(badge))
            }
            html += Tag.element("span", [Tag.classes(["bottom-nav__label"])], htmlEscape(item.label))
            html += Tag.end("a")
        }
        html += Tag.end("nav")
        return html
    }
}

// MARK: WebUI Fab
/// a floating action button.
public struct WebUIFab: View {
    public enum Variant: String, Sendable {
        case primary = "", secondary = " fab--secondary", danger = " fab--danger"
    }
    public enum Size: String, Sendable {
        case sm = " fab--sm", md = "", lg = " fab--lg"
    }
    public let label: String?
    public let icon: IconName
    public let variant: Variant
    public let size: Size
    public let extended: Bool
    public let id: String?
    public let onTap: EventHandler?
    public init(_ label: String? = nil, icon: IconName, variant: Variant = .primary,
                size: Size = .md, extended: Bool = false, id: String? = nil, onTap: EventHandler? = nil) {
        self.label = label; self.icon = icon; self.variant = variant
        self.size = size; self.extended = extended; self.id = id; self.onTap = onTap
    }

    public func render() -> String {
        let tapAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = Tag.begin(
            "button",
            Tag.classes(["fab", variant.rawValue, size.rawValue, extended ? " fab--extended" : ""]),
            id.map { Tag.escAttr("id", $0) } ?? "",
            tapAttrs,
            Tag.escAttr("aria-label", label ?? ""))
        html += Tag.element("span", [Tag.classes(["fab__icon"])], WebUIIcon(icon, size: .medium).render())
        if let label {
            html += Tag.element("span", [Tag.classes(["fab__label"])], htmlEscape(label))
        }
        html += Tag.end("button")
        return html
    }
}

// MARK: WebUI Speed Dial
/// a container that lays out its child fabs in a speed-dial stack.
public struct WebUISpeedDial: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["fab-stage fab-stage--dial"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Wizard
/// progress wizard with completed / current / error steps.
public struct WebUIWizard: View {
    public enum Status: String, Sendable {
        case plain = "", completed = " wizard__step--completed",
             current = " wizard__step--current", done = " wizard__step--done",
             error = " wizard__step--error"
    }
    public struct Step: Sendable {
        public let label: String
        public let desc: String?
        public let status: Status
        public init(_ label: String, desc: String? = nil, status: Status = .plain) {
            self.label = label; self.desc = desc; self.status = status
        }
    }
    public let steps: [Step]
    public let vertical: Bool
    public init(steps: [Step], vertical: Bool = false) { self.steps = steps; self.vertical = vertical }

    public func render() -> String {
        var html = Tag.begin("ol", Tag.classes(["wizard", vertical ? " wizard--vertical" : ""]))
        for step in steps {
            html += Tag.begin("li", Tag.classes(["wizard__step", step.status.rawValue]))
            html += Tag.element("span", [Tag.classes(["wizard__dot"])], "")
            html += Tag.element("span", [Tag.classes(["wizard__label"])], htmlEscape(step.label))
            if let desc = step.desc {
                html += Tag.element("span", [Tag.classes(["wizard__desc"])], htmlEscape(desc))
            }
            html += Tag.end("li")
        }
        html += Tag.end("ol")
        return html
    }
}

// MARK: WebUI Transfer
/// dual-list transfer control (available <-> selected).
public struct WebUITransfer: View {
    public struct Option: Sendable {
        public let label: String
        public let selected: Bool
        public let moved: Bool
        public init(_ label: String, selected: Bool = false, moved: Bool = false) {
            self.label = label; self.selected = selected; self.moved = moved
        }
    }
    public let title: String
    public let options: [Option]
    public let searchPlaceholder: String
    public init(title: String = "", options: [Option], searchPlaceholder: String = "Filter…") {
        self.title = title; self.options = options; self.searchPlaceholder = searchPlaceholder
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["transfer"]))
        html += Tag.begin("div", Tag.classes(["transfer__head"]))
        html += Tag.element("span", [Tag.classes(["transfer__title"])], htmlEscape(title))
        html += Tag.element("span", [Tag.classes(["transfer__count"])], "\(options.count)")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["transfer__search"]))
        html += Tag.void("input", Tag.attr("type", "search"), Tag.escAttr("placeholder", searchPlaceholder))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["transfer__list"]))
        for option in options {
            html += Tag.begin("div", Tag.classes([
                "transfer__item",
                option.selected ? " transfer__item--selected" : "",
                option.moved ? " transfer__row--moved" : "",
            ]))
            html += Tag.element("span", [Tag.classes(["transfer__row-label"])], htmlEscape(option.label))
            if option.moved {
                html += Tag.element("button", [Tag.classes(["transfer__remove"]), Tag.attr("aria-label", "Remove")], "×")
            }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["transfer__controls"]))
        html += Tag.element("button", [Tag.classes(["transfer__btn"]), Tag.attr("aria-label", "Add")], "→")
        html += Tag.element("button", [Tag.classes(["transfer__btn"]), Tag.attr("aria-label", "Remove")], "←")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Button Group
/// a joined group of buttons.
public struct WebUIButtonGroup: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["button-group"]), Tag.attr("role", "group"))
        for c in children { html += c.render() }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Split Button
/// a main action button with an attached caret/options segment.
public struct WebUISplitButton: View {
    public let label: String
    public let caret: Bool
    public let id: String?
    /// handler for main/caret clicks; the main button carries `id + "-main"`,
    /// the caret carries `id + "-caret"` (`event.data["targetId"]`).
    public let onSelect: EventHandler?
    public init(_ label: String, caret: Bool = true, id: String? = nil, onSelect: EventHandler? = nil) {
        self.label = label; self.caret = caret; self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["split-button"]), attrs)
        let mainID = id.map { Tag.escAttr("id", "\($0)-main") } ?? ""
        html += Tag.element("button", [Tag.classes(["button button--primary"]), mainID], htmlEscape(label))
        if caret {
            let caretID = id.map { Tag.escAttr("id", "\($0)-caret") } ?? ""
            html += Tag.element("button", [Tag.classes(["button button--primary button--caret"]), caretID, Tag.attr("aria-label", "Options")], "▾")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Toc
/// a table-of-contents rail.
public struct WebUIToc: View {
    public struct Entry: Sendable {
        public let label: String
        public let href: String
        public let depth: Int
        public let active: Bool
        public init(_ label: String, href: String, depth: Int = 0, active: Bool = false) {
            self.label = label; self.href = href; self.depth = depth; self.active = active
        }
    }
    public let entries: [Entry]
    public let title: String
    public init(title: String = "On this page", entries: [Entry]) { self.title = title; self.entries = entries }

    public func render() -> String {
        var html = Tag.begin("nav", Tag.classes(["toc-rail"]), Tag.attr("aria-label", "Table of contents"))
        html += Tag.element("div", [Tag.classes(["toc-rail__title"])], htmlEscape(title))
        for entry in entries {
            html += Tag.element("a",
                [Tag.classes([
                    "toc-rail__item",
                    entry.depth > 0 ? (entry.depth > 1 ? " toc__link--nested-2" : " toc__link--nested") : "",
                    entry.active ? " toc-rail__item--active" : "",
                ]),
                 Tag.escAttr("href", entry.href)],
                htmlEscape(entry.label))
        }
        html += Tag.end("nav")
        return html
    }
}

// ============================================================================
// MARK: - Overlays & surfaces extras
// ============================================================================

// MARK: WebUI Accordion
/// stacked expandable sections.
public struct WebUIAccordion: View {
    public enum Variant: String, Sendable { case default_ = "", card = " accordion--card", ghost = " accordion--ghost" }
    public struct Item: Sendable {
        public let title: String
        public let open: Bool
        public let children: String
        public init(_ title: String, open: Bool = false, @ViewBuilder content: () -> [any View]) {
            self.title = title; self.open = open; self.children = content().map { $0.render() }.joined()
        }
    }
    public let items: [Item]
    public let variant: Variant
    /// stable container id. when set alongside `onToggle`, the accordion
    /// self-wires its item headers (dispatch on `event.string("targetId")`).
    public let id: String?
    /// handler for item toggles; each header carries `id + "-item-<index>"`.
    public let onToggle: EventHandler?
    public init(items: [Item], variant: Variant = .default_, id: String? = nil, onToggle: EventHandler? = nil) {
        self.items = items; self.variant = variant; self.id = id; self.onToggle = onToggle
    }

    public func render() -> String {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["accordion", variant.rawValue]), attrs)
        for (index, item) in items.enumerated() {
            html += Tag.begin("div", Tag.classes(["accordion__item", item.open ? " accordion__item--open" : ""]))
            let headerID = id.map { Tag.escAttr("id", "\($0)-item-\(index)") } ?? ""
            html += Tag.begin("button", Tag.classes(["accordion__header"]), headerID, Tag.attr("aria-expanded", "\(item.open)"))
            html += Tag.element("span", [Tag.classes(["accordion__chevron"])], "")
            html += htmlEscape(item.title)
            html += Tag.end("button")
            html += Tag.element("div", [Tag.classes(["accordion__body"])], item.children)
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Collapse
/// a single collapsible region.
public struct WebUICollapse: View {
    public let header: String
    public let open: Bool
    public let children: [any View]
    /// stable container id. when set alongside `onToggle`, the collapse
    /// self-wires its header toggle.
    public let id: String?
    public let onToggle: EventHandler?
    public init(_ header: String, open: Bool = false, id: String? = nil, onToggle: EventHandler? = nil,
                @ViewBuilder content: () -> [any View]) {
        self.header = header; self.open = open; self.id = id; self.onToggle = onToggle; self.children = content()
    }

    public func render() -> String {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["collapse", open ? " collapse--open" : ""]), attrs)
        let headerID = id.map { Tag.escAttr("id", $0) } ?? ""
        html += Tag.begin("button", Tag.classes(["collapse__header"]), headerID, Tag.attr("aria-expanded", "\(open)"))
        html += Tag.element("span", [Tag.classes(["collapse__chevron"])], "")
        html += htmlEscape(header)
        html += Tag.end("button")
        html += Tag.begin("div", Tag.classes(["collapse__content"]))
        html += Tag.begin("div", Tag.classes(["collapse__inner"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Action Sheet
/// a contextual action list with an optional title/sub and cancel row.
public struct WebUIActionSheet: View {
    public struct Action: Sendable {
        public let label: String
        public let destructive: Bool
        public init(_ label: String, destructive: Bool = false) { self.label = label; self.destructive = destructive }
    }
    public let title: String?
    public let sub: String?
    public let actions: [Action]
    public let cancel: String
    /// stable container id; when set with `onSelect` the root self-wires and
    /// each action carries `id + "-item-<index>"`, the cancel row `id + "-cancel"`.
    public let id: String?
    public let onSelect: EventHandler?
    public init(title: String? = nil, sub: String? = nil, actions: [Action], cancel: String = "Cancel",
                id: String? = nil, onSelect: EventHandler? = nil) {
        self.title = title; self.sub = sub; self.actions = actions; self.cancel = cancel
        self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["action-sheet"]), attrs, Tag.attr("role", "menu"))
        if let title {
            html += Tag.begin("div", Tag.classes(["action-sheet__header"]))
            html += Tag.element("div", [Tag.classes(["action-sheet__title"])], htmlEscape(title))
        }
        if let sub { html += Tag.element("div", [Tag.classes(["action-sheet__sub"])], htmlEscape(sub)) }
        if title != nil { html += Tag.end("div") }
        for (index, action) in actions.enumerated() {
            let itemID = id.map { Tag.escAttr("id", "\($0)-item-\(index)") } ?? ""
            html += Tag.element("button",
                [Tag.classes(["action-sheet__item", action.destructive ? " action-sheet__item--destructive" : ""]),
                 itemID, Tag.attr("role", "menuitem")],
                htmlEscape(action.label))
        }
        html += Tag.element("div", [Tag.classes(["action-sheet__divider"])], "")
        let cancelID = id.map { Tag.escAttr("id", "\($0)-cancel") } ?? ""
        html += Tag.element("button", [Tag.classes(["action-sheet__cancel"]), cancelID], htmlEscape(cancel))
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Bottom Sheet
/// bottom-anchored modal surface.
public struct WebUIBottomSheet: View {
    public enum Variant: String, Sendable { case peek = " bottom-sheet--peek", half = " bottom-sheet--half", full = " bottom-sheet--full" }
    public let title: String?
    public let children: [any View]
    public let footer: [any View]
    public let variant: Variant
    /// stable container id; when set with `onDismiss` the close button
    /// self-wires (`targetId == "<id>-close"`).
    public let id: String?
    public let onDismiss: EventHandler?
    public init(title: String? = nil, variant: Variant = .half, id: String? = nil, onDismiss: EventHandler? = nil,
                @ViewBuilder content: () -> [any View], @ViewBuilder footer: () -> [any View] = { [] }) {
        self.title = title; self.variant = variant; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = footer()
    }

    public func render() -> String {
        let attrs: String
        if let id, let onDismiss {
            attrs = controlAttributes(id: id, event: .click, handler: onDismiss)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["bottom-sheet", variant.rawValue]), attrs, Tag.attr("role", "dialog"), Tag.attr("aria-modal", "true"))
        html += Tag.element("div", [Tag.classes(["bottom-sheet__handle"])], "")
        if let title {
            let closeID = id.map { Tag.escAttr("id", "\($0)-close") } ?? ""
            html += Tag.begin("div", Tag.classes(["bottom-sheet__header"]))
            html += Tag.element("div", [Tag.classes(["bottom-sheet__title"])], htmlEscape(title))
            html += Tag.element("button", [Tag.classes(["bottom-sheet__close"]), closeID, Tag.attr("aria-label", "Close")], "×")
            html += Tag.end("div")
        }
        html += Tag.begin("div", Tag.classes(["bottom-sheet__body"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        if !footer.isEmpty {
            html += Tag.begin("div", Tag.classes(["bottom-sheet__footer"]))
            for f in footer { html += f.render() }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Drawer
/// edge-anchored sliding surface.
public struct WebUIDrawer: View {
    public enum Edge: String, Sendable { case left = " drawer--left", right = " drawer--right", top = " drawer--top", bottom = " drawer--bottom" }
    public enum Size: String, Sendable { case sm = " drawer--sm", md = "", lg = " drawer--lg" }
    public let title: String?
    public let edge: Edge
    public let size: Size
    public let children: [any View]
    public let footer: [any View]
    /// stable container id; when set with `onDismiss` the close button
    /// self-wires (`targetId == "<id>-close"`).
    public let id: String?
    public let onDismiss: EventHandler?
    public init(title: String? = nil, edge: Edge = .right, size: Size = .md, id: String? = nil, onDismiss: EventHandler? = nil,
                @ViewBuilder content: () -> [any View], @ViewBuilder footer: () -> [any View] = { [] }) {
        self.title = title; self.edge = edge; self.size = size; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = footer()
    }

    public func render() -> String {
        let attrs: String
        if let id, let onDismiss {
            attrs = controlAttributes(id: id, event: .click, handler: onDismiss)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["drawer", edge.rawValue, size.rawValue]), attrs, Tag.attr("role", "dialog"), Tag.attr("aria-modal", "true"))
        html += Tag.begin("div", Tag.classes(["drawer__panel"]))
        if let title {
            let closeID = id.map { Tag.escAttr("id", "\($0)-close") } ?? ""
            html += Tag.begin("div", Tag.classes(["drawer__header"]))
            html += Tag.element("div", [Tag.classes(["drawer__title"])], htmlEscape(title))
            html += Tag.element("button", [Tag.classes(["drawer__close"]), closeID, Tag.attr("aria-label", "Close")], "×")
            html += Tag.end("div")
        }
        html += Tag.begin("div", Tag.classes(["drawer__content"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        if !footer.isEmpty {
            html += Tag.begin("div", Tag.classes(["drawer__footer"]))
            for f in footer { html += f.render() }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Popover
/// an anchored floating popover with arrow.
public struct WebUIPopover: View {
    public enum Side: String, Sendable { case top = " popover--top", bottom = " popover--bottom", left = " popover--left", right = " popover--right" }
    public let title: String?
    public let text: String?
    public let side: Side
    public let children: [any View]
    public init(title: String? = nil, text: String? = nil, side: Side = .bottom,
                @ViewBuilder content: () -> [any View] = { [] }) {
        self.title = title; self.text = text; self.side = side; self.children = content()
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["popover", side.rawValue]))
        html += Tag.element("span", [Tag.classes(["popover__arrow"])], "")
        if let title { html += Tag.element("div", [Tag.classes(["popover__title"])], htmlEscape(title)) }
        if let text { html += Tag.element("div", [Tag.classes(["popover__text"])], htmlEscape(text)) }
        if !children.isEmpty {
            html += Tag.begin("div", Tag.classes(["popover__actions"]))
            for c in children { html += c.render() }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Hover Card
/// a rich card revealed on hover of an anchor.
public struct WebUIHoverCard: View {
    public let name: String
    public let handle: String
    public let bio: String?
    public let meta: [(String, String)]
    public let domain: String
    public let children: [any View]
    public init(name: String, handle: String, bio: String? = nil, meta: [(String, String)] = [],
                domain: String = "", @ViewBuilder content: () -> [any View] = { [] }) {
        self.name = name; self.handle = handle; self.bio = bio; self.meta = meta
        self.domain = domain; self.children = content()
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["hovercard"]))
        html += Tag.begin("div", Tag.classes(["hovercard__body"]))
        html += Tag.element("div", [Tag.classes(["hovercard__name"])], htmlEscape(name))
        html += Tag.element("div", [Tag.classes(["hovercard__handle"])], htmlEscape(handle))
        if let bio { html += Tag.element("div", [Tag.classes(["hovercard__bio"])], htmlEscape(bio)) }
        if !meta.isEmpty {
            html += Tag.begin("div", Tag.classes(["hovercard__meta"]))
            for (k, v) in meta {
                html += Tag.begin("span")
                html += htmlEscape(k)
                html += ": "
                html += Tag.begin("strong")
                html += htmlEscape(v)
                html += Tag.end("strong")
                html += Tag.end("span")
            }
            html += Tag.end("div")
        }
        if !domain.isEmpty { html += Tag.element("div", [Tag.classes(["hovercard__domain"])], htmlEscape(domain)) }
        if !children.isEmpty {
            html += Tag.begin("div", Tag.classes(["hovercard__actions"]))
            for c in children { html += c.render() }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Link Preview
/// rich URL preview card.
public struct WebUILinkPreview: View {
    public let url: String
    public let domain: String
    public let title: String?
    public let desc: String?
    public let image: String?
    public init(url: String, domain: String? = nil, title: String? = nil, desc: String? = nil, image: String? = nil) {
        self.url = url; self.domain = domain ?? url; self.title = title; self.desc = desc; self.image = image
    }

    public func render() -> String {
        var html = Tag.begin("a",
            Tag.classes(["link-preview"]),
            Tag.escAttr("href", url),
            Tag.attr("target", "_blank"),
            Tag.attr("rel", "noopener noreferrer"))
        if let image = image {
            html += Tag.void("img", Tag.classes(["link-preview__img"]), Tag.escAttr("src", image), Tag.attr("alt", ""), Tag.attr("loading", "lazy"))
        }
        html += Tag.begin("div", Tag.classes(["link-preview__body"]))
        html += Tag.element("div", [Tag.classes(["link-preview__domain"])], htmlEscape(domain))
        if let title { html += Tag.element("div", [Tag.classes(["link-preview__title"])], htmlEscape(title)) }
        if let desc { html += Tag.element("div", [Tag.classes(["link-preview__desc"])], htmlEscape(desc)) }
        html += Tag.element("button", [Tag.classes(["link-preview__close"]), Tag.attr("aria-label", "Close")], "×")
        html += Tag.end("div")
        html += Tag.end("a")
        return html
    }
}

// MARK: WebUI Lightbox
/// full-screen image viewer.
public struct WebUILightbox: View {
    public let image: String
    public let caption: String?
    public let count: String?
    /// stable container id; when set with `onNavigate` the prev/next/close
    /// tools self-wire (`"<id>-prev"`, `"<id>-next"`, `"<id>-close"`).
    public let id: String?
    public let onNavigate: EventHandler?
    public init(image: String, caption: String? = nil, count: String? = nil,
                id: String? = nil, onNavigate: EventHandler? = nil) {
        self.image = image; self.caption = caption; self.count = count
        self.id = id; self.onNavigate = onNavigate
    }

    public func render() -> String {
        let attrs: String
        if let id, let onNavigate {
            attrs = controlAttributes(id: id, event: .click, handler: onNavigate)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["lightbox"]), attrs, Tag.attr("role", "dialog"), Tag.attr("aria-modal", "true"))
        html += Tag.begin("div", Tag.classes(["lightbox__stage"]))
        html += Tag.void("img", Tag.classes(["lightbox__img"]), Tag.escAttr("src", image), Tag.escAttr("alt", caption ?? ""))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["lightbox__toolbar"]))
        if let count { html += Tag.element("div", [Tag.classes(["lightbox__counter"])], htmlEscape(count)) }
        let prevID = id.map { Tag.escAttr("id", "\($0)-prev") } ?? ""
        let nextID = id.map { Tag.escAttr("id", "\($0)-next") } ?? ""
        let closeID = id.map { Tag.escAttr("id", "\($0)-close") } ?? ""
        html += Tag.element("button", [Tag.classes(["lightbox__tool"]), prevID, Tag.attr("aria-label", "Previous")], "‹")
        html += Tag.element("button", [Tag.classes(["lightbox__tool"]), nextID, Tag.attr("aria-label", "Next")], "›")
        html += Tag.element("button", [Tag.classes(["lightbox__close"]), closeID, Tag.attr("aria-label", "Close")], "×")
        html += Tag.end("div")
        if let caption { html += Tag.element("div", [Tag.classes(["lightbox__caption"])], htmlEscape(caption)) }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Menu
/// a dropdown menu of actions with optional icons, shortcuts, and dividers.
public struct WebUIMenu: View {
    public struct Item: Sendable {
        public let label: String
        public let shortcut: String?
        public let icon: IconName?
        public let destructive: Bool
        public let disabled: Bool
        /// leading initials chip instead of a glyph.
        public let avatar: String?
        /// muted second line under the label.
        public let hint: String?
        /// marks the item as the current one.
        public let active: Bool
        /// danger treatment (the newer spelling of `destructive`).
        public let danger: Bool
        /// opens a submenu; the sheet draws the trailing chevron via `::after`.
        public let submenu: Bool
        /// renders a rule above this item.
        public let dividerBefore: Bool
        /// renders a section label above this item.
        public let section: String?
        public init(_ label: String, shortcut: String? = nil, icon: IconName? = nil,
                    destructive: Bool = false, disabled: Bool = false,
                    avatar: String? = nil, hint: String? = nil, active: Bool = false,
                    danger: Bool = false, submenu: Bool = false,
                    dividerBefore: Bool = false, section: String? = nil) {
            self.label = label; self.shortcut = shortcut; self.icon = icon
            self.destructive = destructive; self.disabled = disabled
            self.avatar = avatar; self.hint = hint; self.active = active
            self.danger = danger; self.submenu = submenu
            self.dividerBefore = dividerBefore; self.section = section
        }
    }
    public let items: [Item]
    /// heading above the items.
    public let header: String?
    /// search placeholder; renders a `menu__search` row above the items.
    public let search: String?
    /// panelled treatment (`menu__panel`) for a floating menu.
    public let panel: Bool
    /// stable container id; when set with `onSelect` each item self-wires
    /// (`targetId == "<id>-item-<index>"`).
    public let id: String?
    public let onSelect: EventHandler?
    public init(items: [Item], id: String? = nil, onSelect: EventHandler? = nil,
                header: String? = nil, search: String? = nil, panel: Bool = false) {
        self.items = items; self.id = id; self.onSelect = onSelect
        self.header = header; self.search = search; self.panel = panel
    }
    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div",
            Tag.classes(["menu", panel ? " menu__panel" : ""]),
            id.map { Tag.escAttr("id", $0) } ?? "",
            attrs, Tag.attr("role", "menu"))
        if let header { html += Tag.element("div", [Tag.classes(["menu__header"])], htmlEscape(header)) }
        if let search {
            html += Tag.begin("div", Tag.classes(["menu__search"]))
            html += Tag.void("input", Tag.attr("type", "search"), Tag.escAttr("placeholder", search), Tag.escAttr("aria-label", search))
            html += Tag.end("div")
        }
        for (index, item) in items.enumerated() {
            if let section = item.section { html += Tag.element("span", [Tag.classes(["menu__section"])], htmlEscape(section)) }
            if item.dividerBefore { html += Tag.element("div", [Tag.classes(["menu__divider"])], "") }
            let itemID = id.map { Tag.escAttr("id", "\($0)-item-\(index)") } ?? ""
            html += Tag.begin("button",
                Tag.classes([
                    "menu__item",
                    item.destructive ? " menu__item--destructive" : "",
                    item.danger ? " menu__item--danger" : "",
                    item.active ? " menu__item--active" : "",
                    item.submenu ? " menu__item--has-sub" : "",
                ]),
                itemID, Tag.attr("role", "menuitem"),
                item.disabled ? Tag.flag("disabled") : "")
            if let avatar = item.avatar {
                html += Tag.begin("span", Tag.classes(["menu__avatar"]))
                html += Tag.element("span", [Tag.classes(["avatar avatar--initials avatar--sm"])], htmlEscape(avatar))
                html += Tag.end("span")
            }
            if let icon = item.icon { html += Tag.element("span", [Tag.classes(["menu__icon"])], WebUIIcon(icon, size: .small).render()) }
            html += Tag.element("span", [Tag.classes(["menu__label"])], htmlEscape(item.label))
            if let hint = item.hint { html += Tag.element("span", [Tag.classes(["menu__hint"])], htmlEscape(hint)) }
            if let shortcut = item.shortcut { html += Tag.element("span", [Tag.classes(["menu__shortcut"])], htmlEscape(shortcut)) }
            html += Tag.end("button")
        }
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Context Menu
/// a right-click context menu (a .menu with the context modifier).
public struct WebUIContextMenu: View {
    public let items: [WebUIMenu.Item]
    /// stable container id; when set with `onSelect` the inner menu self-wires
    /// each item (`targetId == "<id>-item-<index>"`).
    public let id: String?
    public let onSelect: EventHandler?
    public init(items: [WebUIMenu.Item], id: String? = nil, onSelect: EventHandler? = nil) {
        self.items = items; self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        var html = Tag.begin("div", Tag.classes(["context-menu"]))
        let menu = WebUIMenu(items: items, id: id, onSelect: onSelect).render()
        html += menu
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Dropdown
/// a trigger with an attached options panel.
public struct WebUIDropdown: View {
    public let trigger: String
    public let children: [any View]
    /// stable container id; when set with `onSelect` the root self-wires and
    /// the trigger button carries `id + "-trigger"`.
    public let id: String?
    public let onSelect: EventHandler?
    public init(_ trigger: String, id: String? = nil, onSelect: EventHandler? = nil,
                @ViewBuilder content: () -> [any View]) {
        self.trigger = trigger; self.id = id; self.onSelect = onSelect; self.children = content()
    }

    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["dropdown"]), attrs)
        let triggerID = id.map { Tag.escAttr("id", "\($0)-trigger") } ?? ""
        html += Tag.begin("button", Tag.classes(["dropdown__trigger"]), triggerID)
        html += htmlEscape(trigger)
        html += Tag.element("span", [Tag.classes(["dropdown__chevron"])], "▾")
        html += Tag.end("button")
        html += Tag.begin("div", Tag.classes(["dropdown__panel"]))
        for c in children { html += c.render() }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI ComboBox
/// an autocomplete input with an options panel.
public struct WebUIComboBox: View {
    public struct Option: Sendable {
        public let label: String
        public let value: String
        public let selected: Bool
        public init(_ label: String, value: String? = nil, selected: Bool = false) {
            self.label = label; self.value = value ?? label; self.selected = selected
        }
    }
    public let placeholder: String
    public let options: [Option]
    public let emptyMessage: String
    /// stable container id; when set with `onChange` each option self-wires
    /// (`targetId == "<id>-opt-<index>"`).
    public let id: String?
    public let onChange: EventHandler?
    public init(placeholder: String = "", options: [Option], emptyMessage: String = "No matches",
                id: String? = nil, onChange: EventHandler? = nil) {
        self.placeholder = placeholder; self.options = options; self.emptyMessage = emptyMessage
        self.id = id; self.onChange = onChange
    }

    public func render() -> String {
        let attrs: String
        if let id, let onChange {
            attrs = controlAttributes(id: id, event: .click, handler: onChange)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["combo"]), attrs)
        html += Tag.begin("div", Tag.classes(["combo__input"]))
        html += Tag.void("input", Tag.attr("type", "text"), Tag.escAttr("placeholder", placeholder))
        html += Tag.element("span", [Tag.classes(["dropdown__chevron"])], "▾")
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["combo__panel"]))
        if options.isEmpty {
            html += Tag.element("div", [Tag.classes(["combo__empty"])], htmlEscape(emptyMessage))
        }
        for (index, option) in options.enumerated() {
            let optID = id.map { Tag.escAttr("id", "\($0)-opt-\(index)") } ?? ""
            html += Tag.element("div",
                [Tag.classes(["combo__option", option.selected ? " combo__option--selected" : ""]),
                 optID, Tag.attr("role", "option"), Tag.attr("aria-selected", "\(option.selected)")],
                htmlEscape(option.label))
        }
        html += Tag.end("div")
        html += Tag.end("div")
        return html
    }
}

// MARK: WebUI Command Palette
/// a searchable command palette.
public struct WebUICommandPalette: View {
    public struct Command: Sendable {
        public let label: String
        public let group: String
        public let shortcut: String?
        public init(_ label: String, group: String = "", shortcut: String? = nil) {
            self.label = label; self.group = group; self.shortcut = shortcut
        }
    }
    public let commands: [Command]
    public let placeholder: String
    public let footer: String?
    /// stable container id; when set with `onSelect` each command self-wires
    /// (`targetId == "<id>-cmd-<index>"`).
    public let id: String?
    public let onSelect: EventHandler?
    public init(commands: [Command], placeholder: String = "Type a command…", footer: String? = nil,
                id: String? = nil, onSelect: EventHandler? = nil) {
        self.commands = commands; self.placeholder = placeholder; self.footer = footer
        self.id = id; self.onSelect = onSelect
    }

    public func render() -> String {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = Tag.begin("div", Tag.classes(["command-palette"]), attrs, Tag.attr("role", "dialog"), Tag.attr("aria-modal", "true"))
        html += Tag.begin("div", Tag.classes(["command-palette__input"]))
        html += Tag.void("input", Tag.attr("type", "text"), Tag.escAttr("placeholder", placeholder))
        html += Tag.end("div")
        html += Tag.begin("div", Tag.classes(["command-palette__results"]))
        let groupsOrdered = commands.map(\.group).filter { !$0.isEmpty }.uniquePreservingOrder
        var cmdIndex = 0
        for group in groupsOrdered {
            html += Tag.begin("div", Tag.classes(["command-palette__group"]))
            html += Tag.element("div", [Tag.classes(["command-palette__group-label"])], htmlEscape(group))
            for c in commands where c.group == group {
                let cmdID = id.map { Tag.escAttr("id", "\($0)-cmd-\(cmdIndex)") } ?? ""
                html += Tag.begin("div", Tag.classes(["command-palette__item"]), cmdID)
                html += Tag.element("span", [Tag.classes(["command-palette__item-label"])], htmlEscape(c.label))
                if let sc = c.shortcut { html += Tag.element("kbd", [], htmlEscape(sc)) }
                html += Tag.end("div")
                cmdIndex += 1
            }
            html += Tag.end("div")
        }
        html += Tag.end("div")
        if let footer { html += Tag.element("div", [Tag.classes(["command-palette__footer"])], htmlEscape(footer)) }
        html += Tag.end("div")
        return html
    }
}

private extension Array where Element: Hashable {
    var uniquePreservingOrder: [Element] {
        var seen = Set<Element>(); var out: [Element] = []
        for e in self where seen.insert(e).inserted { out.append(e) }
        return out
    }
}

// MARK: WebUI Separator
/// a rule between or across content. the sheet's divider family carries four
/// shapes: plain, strong, vertical, and a labelled rule. the label form is the
/// two-line pair (text between the lines, e.g. "or"); the glyph form puts an
/// icon badge on the line itself.
public struct WebUISeparator: View {
    public enum Orientation: Sendable { case horizontal, vertical }

    public let orientation: Orientation
    /// text rendered between two lines. ignored when `icon` is set.
    public let label: String?
    /// glyph rendered on the line. wins over `label`.
    public let icon: IconName?
    public let strong: Bool

    public init(
        _ label: String? = nil,
        orientation: Orientation = .horizontal,
        icon: IconName? = nil,
        strong: Bool = false
    ) {
        self.orientation = orientation
        self.label = label
        self.icon = icon
        self.strong = strong
    }

    public func render() -> String {
        if orientation == .vertical {
            return Tag.element("div", [Tag.classes(["divider divider--vertical"]), Tag.attr("role", "separator"), Tag.attr("aria-orientation", "vertical")], "")
        }
        if let icon {
            let glyph = WebUIIcon(icon, size: .slot).render()
            var html = Tag.begin("div", Tag.classes(["divider divider--icon", strong ? " divider--strong" : ""]), Tag.attr("role", "separator"))
            html += Tag.element("span", [Tag.classes(["divider__label"])], glyph)
            html += Tag.end("div")
            return html
        }
        if let label {
            return Tag.element("div", [Tag.classes(["divider-divider"]), Tag.attr("role", "separator")], Tag.element("span", [Tag.classes(["divider-divider__label"])], htmlEscape(label)))
        }
        return Tag.element("div", [Tag.classes(["divider", strong ? " divider--strong" : ""]), Tag.attr("role", "separator")], "")
    }
}

// MARK: WebUI Kbd
/// a keyboard key or combination. one key renders bare; several render as a
/// combo whose keys sit adjacently (the macOS convention, `⌘K`) or with a
/// separator glyph between them (`separator: "+"`).
public struct WebUIKbd: View {
    public enum Size: String, Sendable {
        case small = "kbd--sm"
        case medium = ""
        case large = "kbd--lg"
    }

    public let keys: [String]
    public let size: Size
    /// glyph placed between keys. `nil` places them adjacently without one.
    public let separator: String?

    public init(_ key: String, size: Size = .medium) {
        self.keys = [key]
        self.size = size
        self.separator = nil
    }

    public init(_ keys: [String], size: Size = .medium, separator: String? = nil) {
        self.keys = keys
        self.size = size
        self.separator = separator
    }

    private func keyHTML(_ key: String) -> String {
        let sizeClass = size.rawValue.isEmpty ? "" : " \(size.rawValue)"
        return Tag.element("kbd", [Tag.classes(["kbd", sizeClass])], htmlEscape(key))
    }

    public func render() -> String {
        guard keys.count > 1 else { return keyHTML(keys.first ?? "") }
        var html = Tag.begin("span", Tag.classes(["kbd-combo"]))
        for (index, key) in keys.enumerated() {
            if index > 0, let separator, !separator.isEmpty {
                html += Tag.element("span", [Tag.classes(["kbd-sep"])], htmlEscape(separator))
            }
            html += keyHTML(key)
        }
        html += Tag.end("span")
        return html
    }
}


// MARK: WebUI Scroll Top
/// a floating back-to-top affordance. `progress` (0...1) adds the ring around
/// it, reusing the circular-progress classes the sheet already styles for
/// `scroll-top--ring`. position it against a `position: relative` ancestor.
public struct WebUIScrollTop: View {
    /// 0...1 scroll progress; `nil` renders the icon-only button.
    public let progress: Double?
    public let icon: IconName
    public let label: String
    public let id: String?
    public let onTap: EventHandler?

    public init(
        progress: Double? = nil,
        icon: IconName = .arrowUp,
        label: String = "Back to top",
        id: String? = nil,
        onTap: EventHandler? = nil
    ) {
        self.progress = progress
        self.icon = icon
        self.label = label
        self.id = id
        self.onTap = onTap
    }

    public func render() -> String {
        let attrs: String
        if let id, let onTap {
            attrs = controlAttributes(id: id, event: .click, handler: onTap)
        } else {
            attrs = ""
        }
        var html = Tag.begin("button",
            Tag.classes(["scroll-top", progress != nil ? " scroll-top--ring" : ""]),
            Tag.attr("type", "button"),
            Tag.escAttr("aria-label", label),
            id.map { Tag.escAttr("id", $0) } ?? "",
            attrs)
        if let progress {
            let clamped = progress < 0 ? 0 : (progress > 1 ? 1 : progress)
            let offset = webuiFixedPoint((1 - clamped) * 100, places: 1)
            html += Tag.begin("svg", Tag.classes(["scroll-top__ring"]), Tag.attr("viewBox", "0 0 36 36"), Tag.attr("aria-hidden", "true"))
            html += Tag.selfClose("circle", Tag.classes(["ring__track"]), Tag.attr("cx", "18"), Tag.attr("cy", "18"), Tag.attr("r", "15.915"))
            html += Tag.selfClose("circle", Tag.classes(["ring__fill"]), Tag.attr("cx", "18"), Tag.attr("cy", "18"), Tag.attr("r", "15.915"), Tag.attr("stroke-dasharray", "100"), Tag.attr("stroke-dashoffset", offset))
            html += Tag.end("svg")
        }
        html += Tag.element("span", [Tag.classes(["scroll-top__icon"])], WebUIIcon(icon, size: .medium).render())
        html += Tag.end("button")
        return html
    }
}
