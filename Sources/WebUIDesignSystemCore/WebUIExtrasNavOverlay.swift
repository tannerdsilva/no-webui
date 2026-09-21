import Foundation
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
    public let brand: String?
    public let links: [Link]
    public let actions: [any View]
    public let sticky: Bool

    public init(brand: String? = nil, links: [Link] = [], sticky: Bool = false,
                @ViewBuilder actions: () -> [any View] = { [] }) {
        self.brand = brand; self.links = links; self.sticky = sticky; self.actions = actions()
    }

    public func render() -> String {
        var html = "<nav class=\"navbar\(sticky ? " navbar--sticky" : "")\">"
        if let brand {
            html += "<a class=\"navbar__brand\" href=\"/\"><span class=\"navbar__brand-mark\"></span>\(htmlEscape(brand))</a>"
        }
        if !links.isEmpty {
            html += "<div class=\"navbar__links\">"
            for link in links {
                html += "<a class=\"navbar__link\(link.active ? " navbar__link--active" : "")\" href=\"\(htmlEscape(link.href))\">\(htmlEscape(link.label))</a>"
            }
            html += "</div>"
        }
        if !actions.isEmpty {
            html += "<div class=\"navbar__actions\">"
            for a in actions { html += a.render() }
            html += "</div>"
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
    public init(items: [Item]) { self.items = items }

    public func render() -> String {
        var html = "<nav class=\"bottom-nav\" aria-label=\"Primary\">"
        for item in items {
            html += "<a class=\"bottom-nav__item\(item.active ? " bottom-nav__item--active" : "")\" href=\"#\">"
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

    public init(_ label: String? = nil, icon: IconName, variant: Variant = .primary,
                size: Size = .md, extended: Bool = false, id: String? = nil) {
        self.label = label; self.icon = icon; self.variant = variant
        self.size = size; self.extended = extended; self.id = id
    }

    public func render() -> String {
        var classes = "fab\(variant.rawValue)\(size.rawValue)"
        if extended { classes += " fab--extended" }
        var html = "<button class=\"\(classes)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
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
    public init(_ label: String, caret: Bool = true, id: String? = nil) {
        self.label = label; self.caret = caret; self.id = id
    }

    public func render() -> String {
        var html = "<div class=\"split-button\">"
        html += "<button class=\"button button--primary\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += ">\(htmlEscape(label))</button>"
        if caret {
            html += "<button class=\"button button--primary button--caret\" aria-label=\"Options\">▾</button>"
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
    public init(items: [Item], variant: Variant = .default_) { self.items = items; self.variant = variant }

    public func render() -> String {
        var html = "<div class=\"accordion\(variant.rawValue)\">"
        for item in items {
            html += "<div class=\"accordion__item\(item.open ? " accordion__item--open" : "")\">"
            html += "<button class=\"accordion__header\" aria-expanded=\"\(item.open)\"><span class=\"accordion__chevron\"></span>\(htmlEscape(item.title))</button>"
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
    public init(_ header: String, open: Bool = false, @ViewBuilder content: () -> [any View]) {
        self.header = header; self.open = open; self.children = content()
    }

    public func render() -> String {
        var html = "<div class=\"collapse\(open ? " collapse--open" : "")\">"
        html += "<button class=\"collapse__header\" aria-expanded=\"\(open)\"><span class=\"collapse__chevron\"></span>\(htmlEscape(header))</button>"
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
    public init(title: String? = nil, sub: String? = nil, actions: [Action], cancel: String = "Cancel") {
        self.title = title; self.sub = sub; self.actions = actions; self.cancel = cancel
    }

    public func render() -> String {
        var html = "<div class=\"action-sheet\" role=\"menu\">"
        if let title { html += "<div class=\"action-sheet__header\"><div class=\"action-sheet__title\">\(htmlEscape(title))</div>" }
        if let sub { html += "<div class=\"action-sheet__sub\">\(htmlEscape(sub))</div>" }
        if title != nil { html += "</div>" }
        for action in actions {
            html += "<button class=\"action-sheet__item\(action.destructive ? " action-sheet__item--destructive" : "")\" role=\"menuitem\">\(htmlEscape(action.label))</button>"
        }
        html += "<div class=\"action-sheet__divider\"></div>"
        html += "<button class=\"action-sheet__cancel\">\(htmlEscape(cancel))</button>"
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
    public init(title: String? = nil, variant: Variant = .half,
                @ViewBuilder content: () -> [any View], @ViewBuilder footer: () -> [any View] = { [] }) {
        self.title = title; self.variant = variant; self.children = content(); self.footer = footer()
    }

    public func render() -> String {
        var html = "<div class=\"bottom-sheet\(variant.rawValue)\" role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"bottom-sheet__handle\"></div>"
        if let title {
            html += "<div class=\"bottom-sheet__header\"><div class=\"bottom-sheet__title\">\(htmlEscape(title))</div><button class=\"bottom-sheet__close\" aria-label=\"Close\">×</button></div>"
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
    public init(title: String? = nil, edge: Edge = .right, size: Size = .md,
                @ViewBuilder content: () -> [any View], @ViewBuilder footer: () -> [any View] = { [] }) {
        self.title = title; self.edge = edge; self.size = size; self.children = content(); self.footer = footer()
    }

    public func render() -> String {
        var html = "<div class=\"drawer\(edge.rawValue)\(size.rawValue)\" role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"drawer__panel\">"
        if let title {
            html += "<div class=\"drawer__header\"><div class=\"drawer__title\">\(htmlEscape(title))</div><button class=\"drawer__close\" aria-label=\"Close\">×</button></div>"
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
    public init(image: String, caption: String? = nil, count: String? = nil) {
        self.image = image; self.caption = caption; self.count = count
    }

    public func render() -> String {
        var html = "<div class=\"lightbox\" role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"lightbox__stage\"><img class=\"lightbox__img\" src=\"\(htmlEscape(image))\" alt=\"\(htmlEscape(caption ?? ""))\"></div>"
        html += "<div class=\"lightbox__toolbar\">"
        if let count { html += "<div class=\"lightbox__counter\">\(htmlEscape(count))</div>" }
        html += "<button class=\"lightbox__tool\" aria-label=\"Previous\">‹</button>"
        html += "<button class=\"lightbox__tool\" aria-label=\"Next\">›</button>"
        html += "<button class=\"lightbox__close\" aria-label=\"Close\">×</button>"
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
        public init(_ label: String, shortcut: String? = nil, icon: IconName? = nil,
                    destructive: Bool = false, disabled: Bool = false) {
            self.label = label; self.shortcut = shortcut; self.icon = icon
            self.destructive = destructive; self.disabled = disabled
        }
    }
    public let items: [Item]
    public init(items: [Item]) { self.items = items }

    public func render() -> String {
        var html = "<div class=\"menu\" role=\"menu\">"
        for item in items {
            var cls = "menu__item"
            if item.destructive { cls += " menu__item--destructive" }
            html += "<button class=\"\(cls)\" role=\"menuitem\"\(item.disabled ? " disabled" : "")>"
            if let icon = item.icon { html += "<span class=\"menu__icon\">\(WebUIIcon(icon, size: .small).render())</span>" }
            html += "<span class=\"menu__label\">\(htmlEscape(item.label))</span>"
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
    public init(items: [WebUIMenu.Item]) { self.items = items }

    public func render() -> String {
        var html = "<div class=\"context-menu\">"
        let menu = WebUIMenu(items: items).render()
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
    public init(_ trigger: String, @ViewBuilder content: () -> [any View] = { [] }) {
        self.trigger = trigger; self.children = content()
    }

    public func render() -> String {
        var html = "<div class=\"dropdown\">"
        html += "<button class=\"dropdown__trigger\">\(htmlEscape(trigger))<span class=\"dropdown__chevron\">▾</span></button>"
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
    public init(placeholder: String = "", options: [Option], emptyMessage: String = "No matches") {
        self.placeholder = placeholder; self.options = options; self.emptyMessage = emptyMessage
    }

    public func render() -> String {
        var html = "<div class=\"combo\">"
        html += "<div class=\"combo__input\"><input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\"><span class=\"dropdown__chevron\">▾</span></div>"
        html += "<div class=\"combo__panel\">"
        if options.isEmpty {
            html += "<div class=\"combo__empty\">\(htmlEscape(emptyMessage))</div>"
        }
        for option in options {
            var cls = "combo__option"
            if option.selected { cls += " combo__option--selected" }
            html += "<div class=\"\(cls)\" role=\"option\" aria-selected=\"\(option.selected)\">\(htmlEscape(option.label))</div>"
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
    public init(commands: [Command], placeholder: String = "Type a command…", footer: String? = nil) {
        self.commands = commands; self.placeholder = placeholder; self.footer = footer
    }

    public func render() -> String {
        var html = "<div class=\"command-palette\" role=\"dialog\" aria-modal=\"true\">"
        html += "<div class=\"command-palette__input\"><input type=\"text\" placeholder=\"\(htmlEscape(placeholder))\"></div>"
        html += "<div class=\"command-palette__results\">"
        let groupsOrdered = commands.map(\.group).filter { !$0.isEmpty }.uniquePreservingOrder
        for group in groupsOrdered {
            html += "<div class=\"command-palette__group\"><div class=\"command-palette__group-label\">\(htmlEscape(group))</div>"
            for c in commands where c.group == group {
                html += "<div class=\"command-palette__item\">"
                html += "<span class=\"command-palette__item-label\">\(htmlEscape(c.label))</span>"
                if let sc = c.shortcut { html += "<kbd>\(htmlEscape(sc))</kbd>" }
                html += "</div>"
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
