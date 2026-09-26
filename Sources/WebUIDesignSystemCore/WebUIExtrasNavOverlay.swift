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
        var html = "<nav class=\"navbar\(sticky ? " navbar--sticky" : "")\"\(attrs)>"
        if let brand {
            html += "<a class=\"navbar__brand\" href=\"/\"><span class=\"navbar__brand-mark\"></span>\(htmlEscape(brand))</a>"
        }
        if let search {
            html += "<label class=\"navbar__search\" role=\"search\">"
            html += "<input type=\"search\""
            if let sid = search.id { html += " id=\"\(htmlEscape(sid))\"" }
            html += " placeholder=\"\(htmlEscape(search.placeholder))\" aria-label=\"\(htmlEscape(search.placeholder))\">"
            if let shortcut = search.shortcut { html += "<kbd>\(htmlEscape(shortcut))</kbd>" }
            html += "</label>"
        }
        if !links.isEmpty {
            html += "<div class=\"navbar__links\">"
            for (index, link) in links.enumerated() {
                let linkID = id.map { " id=\"\(htmlEscape("\($0)-link-\(index)"))\"" } ?? ""
                html += "<a class=\"navbar__link\(link.active ? " navbar__link--active" : "")\"\(linkID) href=\"\(htmlEscape(link.href))\">\(htmlEscape(link.label))</a>"
            }
            html += "</div>"
        }
        if !actions.isEmpty {
            html += "<div class=\"navbar__actions\">"
            for a in actions { html += a.render() }
            html += "</div>"
        }
        if mobileMenu {
            html += "<button class=\"navbar__hamburger\" type=\"button\" aria-label=\"\(htmlEscape(mobileMenuLabel))\">"
            html += "<span></span><span></span><span></span>"
            html += "</button>"
        }
        html += "</nav>"
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
        var html = "<nav class=\"bottom-nav\"\(attrs) aria-label=\"Primary\">"
        for (index, item) in items.enumerated() {
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<a class=\"bottom-nav__item\(item.active ? " bottom-nav__item--active" : "")\"\(itemID) href=\"#\">"
            html += "<span class=\"bottom-nav__icon\">\(WebUIIcon(item.icon, size: .medium).render())</span>"
            if let badge = item.badge {
                html += "<span class=\"bottom-nav__badge\">\(htmlEscape(badge))</span>"
            }
            html += "<span class=\"bottom-nav__label\">\(htmlEscape(item.label))</span></a>"
        }
        html += "</nav>"
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
        var classes = "fab\(variant.rawValue)\(size.rawValue)"
        if extended { classes += " fab--extended" }
        let tapAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = "<button class=\"\(classes)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += "\(tapAttrs)"
        html += " aria-label=\"\(htmlEscape(label ?? ""))\">"
        html += "<span class=\"fab__icon\">\(WebUIIcon(icon, size: .medium).render())</span>"
        if let label {
            html += "<span class=\"fab__label\">\(htmlEscape(label))</span>"
        }
        html += "</button>"
        return html
    }
}

// MARK: WebUI Speed Dial
/// a container that lays out its child fabs in a speed-dial stack.
public struct WebUISpeedDial: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = "<div class=\"fab-stage fab-stage--dial\">"
        for c in children { html += c.render() }
        html += "</div>"
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
        var html = "<ol class=\"wizard\(vertical ? " wizard--vertical" : "")\">"
        for step in steps {
            html += "<li class=\"wizard__step\(step.status.rawValue)\">"
            html += "<span class=\"wizard__dot\"></span>"
            html += "<span class=\"wizard__label\">\(htmlEscape(step.label))</span>"
            if let desc = step.desc {
                html += "<span class=\"wizard__desc\">\(htmlEscape(desc))</span>"
            }
            html += "</li>"
        }
        html += "</ol>"
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
        var html = "<div class=\"transfer\">"
        html += "<div class=\"transfer__head\"><span class=\"transfer__title\">\(htmlEscape(title))</span><span class=\"transfer__count\">\(options.count)</span></div>"
        html += "<div class=\"transfer__search\"><input type=\"search\" placeholder=\"\(htmlEscape(searchPlaceholder))\"></div>"
        html += "<div class=\"transfer__list\">"
        for option in options {
            let cls = "transfer__item\(option.selected ? " transfer__item--selected" : "")\(option.moved ? " transfer__row--moved" : "")"
            html += "<div class=\"\(cls)\"><span class=\"transfer__row-label\">\(htmlEscape(option.label))</span>"
            if option.moved {
                html += "<button class=\"transfer__remove\" aria-label=\"Remove\">×</button>"
            }
            html += "</div>"
        }
        html += "</div>"
        html += "<div class=\"transfer__controls\"><button class=\"transfer__btn\" aria-label=\"Add\">→</button><button class=\"transfer__btn\" aria-label=\"Remove\">←</button></div>"
        html += "</div>"
        return html
    }
}

// MARK: WebUI Button Group
/// a joined group of buttons.
public struct WebUIButtonGroup: View {
    public let children: [any View]
    public init(@ViewBuilder content: () -> [any View]) { self.children = content() }

    public func render() -> String {
        var html = "<div class=\"button-group\" role=\"group\">"
        for c in children { html += c.render() }
        html += "</div>"
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
        var html = "<div class=\"split-button\"\(attrs)>"
        let mainID = id.map { " id=\"\(htmlEscape("\($0)-main"))\"" } ?? ""
        html += "<button class=\"button button--primary\"\(mainID)>\(htmlEscape(label))</button>"
        if caret {
            let caretID = id.map { " id=\"\(htmlEscape("\($0)-caret"))\"" } ?? ""
            html += "<button class=\"button button--primary button--caret\"\(caretID) aria-label=\"Options\">▾</button>"
        }
        html += "</div>"
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
        var html = "<nav class=\"toc-rail\" aria-label=\"Table of contents\">"
        html += "<div class=\"toc-rail__title\">\(htmlEscape(title))</div>"
        for entry in entries {
            var cls = "toc-rail__item"
            if entry.depth > 0 { cls += entry.depth > 1 ? " toc__link--nested-2" : " toc__link--nested" }
            if entry.active { cls += " toc-rail__item--active" }
            html += "<a class=\"\(cls)\" href=\"\(htmlEscape(entry.href))\">\(htmlEscape(entry.label))</a>"
        }
        html += "</nav>"
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
        var html = "<div class=\"accordion\(variant.rawValue)\"\(attrs)>"
        for (index, item) in items.enumerated() {
            html += "<div class=\"accordion__item\(item.open ? " accordion__item--open" : "")\">"
            let headerID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"accordion__header\"\(headerID) aria-expanded=\"\(item.open)\"><span class=\"accordion__chevron\"></span>\(htmlEscape(item.title))</button>"
            html += "<div class=\"accordion__body\">\(item.children)</div>"
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"collapse\(open ? " collapse--open" : "")\"\(attrs)>"
        let headerID = id.map { " id=\"\(htmlEscape($0))\"" } ?? ""
        html += "<button class=\"collapse__header\"\(headerID) aria-expanded=\"\(open)\"><span class=\"collapse__chevron\"></span>\(htmlEscape(header))</button>"
        html += "<div class=\"collapse__content\"><div class=\"collapse__inner\">"
        for c in children { html += c.render() }
        html += "</div></div></div>"
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
        var html = "<div class=\"action-sheet\"\(attrs) role=\"menu\">"
        if let title { html += "<div class=\"action-sheet__header\"><div class=\"action-sheet__title\">\(htmlEscape(title))</div>" }
        if let sub { html += "<div class=\"action-sheet__sub\">\(htmlEscape(sub))</div>" }
        if title != nil { html += "</div>" }
        for (index, action) in actions.enumerated() {
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"action-sheet__item\(action.destructive ? " action-sheet__item--destructive" : "")\"\(itemID) role=\"menuitem\">\(htmlEscape(action.label))</button>"
        }
        html += "<div class=\"action-sheet__divider\"></div>"
        let cancelID = id.map { " id=\"\(htmlEscape("\($0)-cancel"))\"" } ?? ""
        html += "<button class=\"action-sheet__cancel\"\(cancelID)>\(htmlEscape(cancel))</button>"
        html += "</div>"
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
        var html = "<div class=\"bottom-sheet\(variant.rawValue)\"\(attrs) role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"bottom-sheet__handle\"></div>"
        if let title {
            let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
            html += "<div class=\"bottom-sheet__header\"><div class=\"bottom-sheet__title\">\(htmlEscape(title))</div><button class=\"bottom-sheet__close\"\(closeID) aria-label=\"Close\">×</button></div>"
        }
        html += "<div class=\"bottom-sheet__body\">"
        for c in children { html += c.render() }
        html += "</div>"
        if !footer.isEmpty {
            html += "<div class=\"bottom-sheet__footer\">"
            for f in footer { html += f.render() }
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"drawer\(edge.rawValue)\(size.rawValue)\"\(attrs) role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"drawer__panel\">"
        if let title {
            let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
            html += "<div class=\"drawer__header\"><div class=\"drawer__title\">\(htmlEscape(title))</div><button class=\"drawer__close\"\(closeID) aria-label=\"Close\">×</button></div>"
        }
        html += "<div class=\"drawer__content\">"
        for c in children { html += c.render() }
        html += "</div>"
        if !footer.isEmpty {
            html += "<div class=\"drawer__footer\">"
            for f in footer { html += f.render() }
            html += "</div>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"popover\(side.rawValue)\">"
        html += "<span class=\"popover__arrow\"></span>"
        if let title { html += "<div class=\"popover__title\">\(htmlEscape(title))</div>" }
        if let text { html += "<div class=\"popover__text\">\(htmlEscape(text))</div>" }
        if !children.isEmpty {
            html += "<div class=\"popover__actions\">"
            for c in children { html += c.render() }
            html += "</div>"
        }
        html += "</div>"
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
        var html = "<div class=\"hovercard\"><div class=\"hovercard__body\">"
        html += "<div class=\"hovercard__name\">\(htmlEscape(name))</div>"
        html += "<div class=\"hovercard__handle\">\(htmlEscape(handle))</div>"
        if let bio { html += "<div class=\"hovercard__bio\">\(htmlEscape(bio))</div>" }
        if !meta.isEmpty {
            html += "<div class=\"hovercard__meta\">"
            for (k, v) in meta { html += "<span>\(htmlEscape(k)): <strong>\(htmlEscape(v))</strong></span>" }
            html += "</div>"
        }
        if !domain.isEmpty { html += "<div class=\"hovercard__domain\">\(htmlEscape(domain))</div>" }
        if !children.isEmpty {
            html += "<div class=\"hovercard__actions\">"
            for c in children { html += c.render() }
            html += "</div>"
        }
        html += "</div></div>"
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
        var html = "<a class=\"link-preview\" href=\"\(htmlEscape(url))\" target=\"_blank\" rel=\"noopener noreferrer\">"
        if let image = image {
            html += "<img class=\"link-preview__img\" src=\"\(htmlEscape(image))\" alt=\"\" loading=\"lazy\">"
        }
        html += "<div class=\"link-preview__body\">"
        html += "<div class=\"link-preview__domain\">\(htmlEscape(domain))</div>"
        if let title { html += "<div class=\"link-preview__title\">\(htmlEscape(title))</div>" }
        if let desc { html += "<div class=\"link-preview__desc\">\(htmlEscape(desc))</div>" }
        html += "<button class=\"link-preview__close\" aria-label=\"Close\">×</button>"
        html += "</div></a>"
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
        var html = "<div class=\"lightbox\"\(attrs) role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"lightbox__stage\"><img class=\"lightbox__img\" src=\"\(htmlEscape(image))\" alt=\"\(htmlEscape(caption ?? ""))\"></div>"
        html += "<div class=\"lightbox__toolbar\">"
        if let count { html += "<div class=\"lightbox__counter\">\(htmlEscape(count))</div>" }
        let prevID = id.map { " id=\"\(htmlEscape("\($0)-prev"))\"" } ?? ""
        let nextID = id.map { " id=\"\(htmlEscape("\($0)-next"))\"" } ?? ""
        let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
        html += "<button class=\"lightbox__tool\"\(prevID) aria-label=\"Previous\">‹</button>"
        html += "<button class=\"lightbox__tool\"\(nextID) aria-label=\"Next\">›</button>"
        html += "<button class=\"lightbox__close\"\(closeID) aria-label=\"Close\">×</button>"
        html += "</div>"
        if let caption { html += "<div class=\"lightbox__caption\">\(htmlEscape(caption))</div>" }
        html += "</div>"
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
        var html = "<div class=\"menu\(panel ? " menu__panel" : "")\"\(attrs) role=\"menu\">"
        if let header { html += "<div class=\"menu__header\">\(htmlEscape(header))</div>" }
        if let search {
            html += "<div class=\"menu__search\">"
            html += "<input type=\"search\" placeholder=\"\(htmlEscape(search))\" aria-label=\"\(htmlEscape(search))\">"
            html += "</div>"
        }
        for (index, item) in items.enumerated() {
            if let section = item.section { html += "<span class=\"menu__section\">\(htmlEscape(section))</span>" }
            if item.dividerBefore { html += "<div class=\"menu__divider\"></div>" }
            var cls = "menu__item"
            if item.destructive { cls += " menu__item--destructive" }
            if item.danger { cls += " menu__item--danger" }
            if item.active { cls += " menu__item--active" }
            if item.submenu { cls += " menu__item--has-sub" }
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"\(cls)\"\(itemID) role=\"menuitem\"\(item.disabled ? " disabled" : "")>"
            if let avatar = item.avatar { html += "<span class=\"menu__avatar\">\(htmlEscape(avatar))</span>" }
            if let icon = item.icon { html += "<span class=\"menu__icon\">\(WebUIIcon(icon, size: .small).render())</span>" }
            html += "<span class=\"menu__label\">\(htmlEscape(item.label))</span>"
            if let hint = item.hint { html += "<span class=\"menu__hint\">\(htmlEscape(hint))</span>" }
            if let shortcut = item.shortcut { html += "<span class=\"menu__shortcut\">\(htmlEscape(shortcut))</span>" }
            html += "</button>"
        }
        html += "</div>"
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
        var html = "<div class=\"context-menu\">"
        let menu = WebUIMenu(items: items, id: id, onSelect: onSelect).render()
        html += menu
        html += "</div>"
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
        var html = "<div class=\"dropdown\"\(attrs)>"
        let triggerID = id.map { " id=\"\(htmlEscape("\($0)-trigger"))\"" } ?? ""
        html += "<button class=\"dropdown__trigger\"\(triggerID)>\(htmlEscape(trigger))<span class=\"dropdown__chevron\">▾</span></button>"
        html += "<div class=\"dropdown__panel\">"
        for c in children { html += c.render() }
        html += "</div></div>"
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
        var html = "<div class=\"combo\"\(attrs)>"
        html += "<div class=\"combo__input\"><input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\"><span class=\"dropdown__chevron\">▾</span></div>"
        html += "<div class=\"combo__panel\">"
        if options.isEmpty {
            html += "<div class=\"combo__empty\">\(htmlEscape(emptyMessage))</div>"
        }
        for (index, option) in options.enumerated() {
            var cls = "combo__option"
            if option.selected { cls += " combo__option--selected" }
            let optID = id.map { " id=\"\(htmlEscape("\($0)-opt-\(index)"))\"" } ?? ""
            html += "<div class=\"\(cls)\"\(optID) role=\"option\" aria-selected=\"\(option.selected)\">\(htmlEscape(option.label))</div>"
        }
        html += "</div></div>"
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
        var html = "<div class=\"command-palette\"\(attrs) role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"command-palette__input\"><input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\"></div>"
        html += "<div class=\"command-palette__results\">"
        let groupsOrdered = commands.map(\.group).filter { !$0.isEmpty }.uniquePreservingOrder
        var cmdIndex = 0
        for group in groupsOrdered {
            html += "<div class=\"command-palette__group\"><div class=\"command-palette__group-label\">\(htmlEscape(group))</div>"
            for c in commands where c.group == group {
                let cmdID = id.map { " id=\"\(htmlEscape("\($0)-cmd-\(cmdIndex)"))\"" } ?? ""
                html += "<div class=\"command-palette__item\"\(cmdID)>"
                html += "<span class=\"command-palette__item-label\">\(htmlEscape(c.label))</span>"
                if let sc = c.shortcut { html += "<kbd>\(htmlEscape(sc))</kbd>" }
                html += "</div>"
                cmdIndex += 1
            }
            html += "</div>"
        }
        html += "</div>"
        if let footer { html += "<div class=\"command-palette__footer\">\(htmlEscape(footer))</div>" }
        html += "</div>"
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
            return "<div class=\"divider divider--vertical\" role=\"separator\" aria-orientation=\"vertical\"></div>"
        }
        if let icon {
            let glyph = WebUIIcon(icon, size: .slot).render()
            return "<div class=\"divider divider--icon\(strong ? " divider--strong" : "")\" role=\"separator\"><span class=\"divider__label\">\(glyph)</span></div>"
        }
        if let label {
            return "<div class=\"divider-divider\" role=\"separator\"><span class=\"divider-divider__label\">\(htmlEscape(label))</span></div>"
        }
        return "<div class=\"divider\(strong ? " divider--strong" : "")\" role=\"separator\"></div>"
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
        return "<kbd class=\"kbd\(sizeClass)\">\(htmlEscape(key))</kbd>"
    }

    public func render() -> String {
        guard keys.count > 1 else { return keyHTML(keys.first ?? "") }
        var html = "<span class=\"kbd-combo\">"
        for (index, key) in keys.enumerated() {
            if index > 0, let separator, !separator.isEmpty {
                html += "<span class=\"kbd-sep\">\(htmlEscape(separator))</span>"
            }
            html += keyHTML(key)
        }
        html += "</span>"
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
        var html = "<button class=\"scroll-top\(progress != nil ? " scroll-top--ring" : "")\" type=\"button\" aria-label=\"\(htmlEscape(label))\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += attrs + ">"
        if let progress {
            let clamped = progress < 0 ? 0 : (progress > 1 ? 1 : progress)
            let offset = webuiFixedPoint((1 - clamped) * 100, places: 1)
            html += "<svg class=\"scroll-top__ring\" viewBox=\"0 0 36 36\" aria-hidden=\"true\">"
            html += "<circle class=\"ring__track\" cx=\"18\" cy=\"18\" r=\"15.915\"/>"
            html += "<circle class=\"ring__fill\" cx=\"18\" cy=\"18\" r=\"15.915\" stroke-dasharray=\"100\" stroke-dashoffset=\"\(offset)\"/>"
            html += "</svg>"
        }
        html += "<span class=\"scroll-top__icon\">" + WebUIIcon(icon, size: .medium).render() + "</span>"
        html += "</button>"
        return html
    }
}
