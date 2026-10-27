import WebUICore

// ============================================================================
// MARK: - Navigation & chrome extras
// ============================================================================

// MARK: WebUI Navbar
/// a top application bar: brand, nav links, and trailing actions.
public struct WebUINavbar<Actions: View>: View {
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
        public init(placeholder: String = WebUIStrings.english.search, shortcut: String? = nil, id: String? = nil) {
            self.placeholder = placeholder
            self.shortcut = shortcut
            self.id = id
        }
    }
    public let brand: String?
    public let links: [Link]
    public let actions: Actions
    /// whether the caller supplied any trailing action. the wrapper is emitted
    /// only when there is one — the same branch `!actions.isEmpty` made over the
    /// erased array, now decided once at init from the block's own arity.
    public let hasActions: Bool
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
                mobileMenuLabel: String = WebUIStrings.english.menu,
                id: String? = nil, onNavigate: EventHandler? = nil,
                @ElementBuilder actions: () -> Actions) {
        let built = actions()
        self.brand = brand; self.links = links; self.sticky = sticky
        self.search = search; self.mobileMenu = mobileMenu
        self.mobileMenuLabel = mobileMenuLabel
        self.id = id; self.onNavigate = onNavigate
        self.actions = built
        self.hasActions = !blockIsEmpty(built)
    }

    /// no trailing actions: `Actions` is the phantom `EmptyView`, and the
    /// wrapper is absent — the bytes a call site that omitted the block rendered.
    public init(brand: String? = nil, links: [Link] = [], sticky: Bool = false,
                search: Search? = nil, mobileMenu: Bool = false,
                mobileMenuLabel: String = WebUIStrings.english.menu,
                id: String? = nil, onNavigate: EventHandler? = nil) where Actions == EmptyView {
        self.brand = brand; self.links = links; self.sticky = sticky
        self.search = search; self.mobileMenu = mobileMenu
        self.mobileMenuLabel = mobileMenuLabel
        self.id = id; self.onNavigate = onNavigate
        self.actions = EmptyView()
        self.hasActions = false
    }

    public func render(into buffer: inout HTMLBuffer) {
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
            html += "<label class=\"navbar__search\"" + AriaRole.search.render() + ">"
            html += "<input type=\"search\""
            if let sid = search.id { html += " id=\"\(htmlEscape(sid))\"" }
            html += " placeholder=\"\(htmlEscape(search.placeholder))\"" + Aria.label(search.placeholder).render() + ">"
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
        if hasActions {
            html += "<div class=\"navbar__actions\">"
        }
        // the actions are a typed block: they render straight into the buffer
        // between the prefix and the tail instead of being concatenated into one
        // string. the bytes are the concatenation's.
        buffer.append(html)
        if hasActions {
            actions.render(into: &buffer)
            buffer.append("</div>")
        }
        html = ""
        if mobileMenu {
            html += "<button class=\"navbar__hamburger\" type=\"button\"" + Aria.label(mobileMenuLabel).render() + ">"
            html += "<span></span><span></span><span></span>"
            html += "</button>"
        }
        html += "</nav>"
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = "<nav class=\"bottom-nav\"\(attrs)" + Aria.label(RenderContext.currentStrings.primary).render() + ">"
        for (index, item) in items.enumerated() {
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<a class=\"bottom-nav__item\(item.active ? " bottom-nav__item--active" : "")\"\(itemID) href=\"#\">"
            html += "<span class=\"bottom-nav__icon\">\(WebUIIcon(item.icon, size: .medium).markup.html)</span>"
            if let badge = item.badge {
                html += "<span class=\"bottom-nav__badge\">\(htmlEscape(badge))</span>"
            }
            html += "<span class=\"bottom-nav__label\">\(htmlEscape(item.label))</span></a>"
        }
        html += "</nav>"
        buffer.append(html)
    }
}

// MARK: WebUI Fab
/// a floating action button.
public struct WebUIFab: View {    @available(*, deprecated, renamed: "Tone")
    public typealias Variant = Tone

    /// this component's own class for a shared tone. a tone this component
    /// never offered forwards the same pattern (`" fab--neutral"`) rather than
    /// silently rendering the default — the class stays an extension point.
    private static func classFor(_ tone: Tone) -> String {
        switch tone {
            case .neutral: return " fab--neutral"
            case .primary: return ""
            case .secondary: return " fab--secondary"
            case .info: return " fab--info"
            case .success: return " fab--success"
            case .warning: return " fab--warning"
            case .danger: return " fab--danger"
        }
    }
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize
    public let label: String?
    public let icon: IconName
    public let tone: Tone
    public let size: ControlSize
    public let extended: Bool
    public let id: String?
    public let onTap: EventHandler?
    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " fab--sm"
            case .md: return ""
            case .lg: return " fab--lg"
            case .xl: return " fab--xl"
        }
    }
    @available(*, deprecated, message: "use tone: — Tone is the shared vocabulary")

    public init(_ label: String? = nil, icon: IconName, variant: Tone,
                size: ControlSize = .md, extended: Bool = false, id: String? = nil, onTap: EventHandler? = nil) {
        self.label = label; self.icon = icon; self.tone = variant
        self.size = size; self.extended = extended; self.id = id; self.onTap = onTap
    }


    public init(_ label: String? = nil, icon: IconName, tone: Variant = .primary,
                size: ControlSize = .md, extended: Bool = false, id: String? = nil, onTap: EventHandler? = nil) {
        self.label = label; self.icon = icon; self.tone = tone
        self.size = size; self.extended = extended; self.id = id; self.onTap = onTap
    }

    public func render(into buffer: inout HTMLBuffer) {
        var classes = "fab\(Self.classFor(tone))\(Self.classFor(size))"
        if extended { classes += " fab--extended" }
        let tapAttrs = id.map { controlAttributes(id: $0, event: .click, handler: onTap) } ?? ""
        var html = "<button class=\"\(classes)\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += "\(tapAttrs)"
        html += Aria.label(label ?? "").render() + ">"
        html += "<span class=\"fab__icon\">\(WebUIIcon(icon, size: .medium).markup.html)</span>"
        if let label {
            html += "<span class=\"fab__label\">\(htmlEscape(label))</span>"
        }
        html += "</button>"
        buffer.append(html)
    }
}

// MARK: WebUI Speed Dial
/// a container that lays out its child fabs in a speed-dial stack.
public struct WebUISpeedDial<Content: View>: View {
    public let children: Content
    public init(@ElementBuilder content: () -> Content) { self.children = content() }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.append("<div class=\"fab-stage fab-stage--dial\">")
        children.render(into: &buffer)
        buffer.append("</div>")
    }
}

// MARK: WebUI Wizard
/// progress wizard with completed / current / error steps.
public struct WebUIWizard: View {
    @available(*, deprecated, renamed: "StepStatus")
    public typealias Status = StepStatus

    public struct Step: Sendable {
        public let label: String
        public let desc: String?
        public let status: StepStatus
        public init(_ label: String, desc: String? = nil, status: StepStatus = .pending) {
            self.label = label; self.desc = desc; self.status = status
        }
    }
    public let steps: [Step]
    public let vertical: Bool
    public init(steps: [Step], vertical: Bool = false) { self.steps = steps; self.vertical = vertical }

    /// this component's own class for a shared step status — every 1.x case keeps
    /// its exact bytes, `.completed` included (the sheet ships it as a peer of
    /// `--done`, which is why `StepStatus` carries both).
    private static func classFor(_ status: StepStatus) -> String {
        switch status {
            case .pending: return ""
            case .current: return " wizard__step--current"
            case .completed: return " wizard__step--completed"
            case .done: return " wizard__step--done"
            case .error: return " wizard__step--error"
        }
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<ol class=\"wizard\(vertical ? " wizard--vertical" : "")\">"
        for step in steps {
            html += "<li class=\"wizard__step\(Self.classFor(step.status))\">"
            html += "<span class=\"wizard__dot\"></span>"
            html += "<span class=\"wizard__label\">\(htmlEscape(step.label))</span>"
            if let desc = step.desc {
                html += "<span class=\"wizard__desc\">\(htmlEscape(desc))</span>"
            }
            html += "</li>"
        }
        html += "</ol>"
        buffer.append(html)
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
    public init(title: String = "", options: [Option], searchPlaceholder: String = WebUIStrings.english.filter) {
        self.title = title; self.options = options; self.searchPlaceholder = searchPlaceholder
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"transfer\">"
        html += "<div class=\"transfer__head\"><span class=\"transfer__title\">\(htmlEscape(title))</span><span class=\"transfer__count\">\(options.count)</span></div>"
        html += "<div class=\"transfer__search\"><input type=\"search\" placeholder=\"\(htmlEscape(searchPlaceholder))\"></div>"
        html += "<div class=\"transfer__list\">"
        for option in options {
            let cls = "transfer__item\(option.selected ? " transfer__item--selected" : "")\(option.moved ? " transfer__row--moved" : "")"
            html += "<div class=\"\(cls)\"><span class=\"transfer__row-label\">\(htmlEscape(option.label))</span>"
            if option.moved {
                html += "<button class=\"transfer__remove\"" + Aria.label(RenderContext.currentStrings.remove).render() + ">×</button>"
            }
            html += "</div>"
        }
        html += "</div>"
        html += "<div class=\"transfer__controls\"><button class=\"transfer__btn\"" + Aria.label(RenderContext.currentStrings.add).render() + ">→</button><button class=\"transfer__btn\"" + Aria.label(RenderContext.currentStrings.remove).render() + ">←</button></div>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Button Group
/// a joined group of buttons.
public struct WebUIButtonGroup<Content: View>: View {
    public let children: Content
    public init(@ElementBuilder content: () -> Content) { self.children = content() }

    public func render(into buffer: inout HTMLBuffer) {
        buffer.append("<div class=\"button-group\"" + AriaRole.group.render() + ">")
        children.render(into: &buffer)
        buffer.append("</div>")
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

    public func render(into buffer: inout HTMLBuffer) {
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
            html += "<button class=\"button button--primary button--caret\"\(caretID)" + Aria.label(RenderContext.currentStrings.options).render() + ">▾</button>"
        }
        html += "</div>"
        buffer.append(html)
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
    public init(title: String = WebUIStrings.english.onThisPage, entries: [Entry]) { self.title = title; self.entries = entries }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<nav class=\"toc-rail\"" + Aria.label(RenderContext.currentStrings.tableOfContents).render() + ">"
        html += "<div class=\"toc-rail__title\">\(htmlEscape(title))</div>"
        for entry in entries {
            var cls = "toc-rail__item"
            if entry.depth > 0 { cls += entry.depth > 1 ? " toc__link--nested-2" : " toc__link--nested" }
            if entry.active { cls += " toc-rail__item--active" }
            html += "<a class=\"\(cls)\" href=\"\(htmlEscape(entry.href))\">\(htmlEscape(entry.label))</a>"
        }
        html += "</nav>"
        buffer.append(html)
    }
}

// ============================================================================
// MARK: - Overlays & surfaces extras
// ============================================================================

// MARK: WebUI Accordion
/// stacked expandable sections.
public struct WebUIAccordion: View {
    /// the accordion's ONE appearance axis — two discrete surface treatments
    /// (`.accordion--card`/`.accordion--ghost`) that share no axis with any
    /// shared vocabulary type, so they stay component-local. renamed from
    /// `Variant`.
    public enum Appearance: String, Sendable { case default_ = "", card = " accordion--card", ghost = " accordion--ghost" }

    @available(*, deprecated, renamed: "Appearance")
    public typealias Variant = Appearance
    public struct Item: Sendable {
        public let title: String
        public let open: Bool
        public let children: String
        /// the item stores rendered markup (`children: String`), because an
        /// `Item` is a `Sendable` value held in an array and a generic item would
        /// make `[Item]` heterogeneous. the block is typed, so its type reaches
        /// this init — the flattening happens once, here, and never per render.
        public init<Content: View>(_ title: String, open: Bool = false, @ElementBuilder content: () -> Content) {
            self.title = title; self.open = open; self.children = content().markup.html
        }
    }
    public let items: [Item]
    public let appearance: Appearance
    /// stable container id. when set alongside `onToggle`, the accordion
    /// self-wires its item headers (dispatch on `event.targetID`).
    public let id: String?
    /// handler for item toggles; each header carries `id + "-item-<index>"`.
    public let onToggle: EventHandler?
    public init(items: [Item], appearance: Appearance = .default_, id: String? = nil, onToggle: EventHandler? = nil) {
        self.items = items; self.appearance = appearance; self.id = id; self.onToggle = onToggle
    }

    /// the 1.x initializer. required (no default) so it discriminates from the
    /// `appearance:` one; forwards so a 1.x call site keeps compiling byte-identically.
    @available(*, deprecated, message: "use appearance: — the members are the accordion's one appearance axis")
    public init(items: [Item], variant: Appearance, id: String? = nil, onToggle: EventHandler? = nil) {
        self.init(items: items, appearance: variant, id: id, onToggle: onToggle)
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var html = "<div class=\"accordion\(appearance.rawValue)\"\(attrs)>"
        for (index, item) in items.enumerated() {
            html += "<div class=\"accordion__item\(item.open ? " accordion__item--open" : "")\">"
            let headerID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"accordion__header\"\(headerID)" + Aria.expanded(item.open ? .yes : .no).render() + "><span class=\"accordion__chevron\"></span>\(htmlEscape(item.title))</button>"
            html += "<div class=\"accordion__body\">\(item.children)</div>"
            html += "</div>"
        }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Collapse
/// a single collapsible region.
public struct WebUICollapse<Content: View>: View {
    public let header: String
    public let open: Bool
    public let children: Content
    /// stable container id. when set alongside `onToggle`, the collapse
    /// self-wires its header toggle.
    public let id: String?
    public let onToggle: EventHandler?
    public init(_ header: String, open: Bool = false, id: String? = nil, onToggle: EventHandler? = nil,
                @ElementBuilder content: () -> Content) {
        self.header = header; self.open = open; self.id = id; self.onToggle = onToggle; self.children = content()
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onToggle {
            attrs = controlAttributes(id: id, event: .click, handler: onToggle)
        } else {
            attrs = ""
        }
        var html = "<div class=\"collapse\(open ? " collapse--open" : "")\"\(attrs)>"
        let headerID = id.map { " id=\"\(htmlEscape($0))\"" } ?? ""
        html += "<button class=\"collapse__header\"\(headerID)" + Aria.expanded(open ? .yes : .no).render() + "><span class=\"collapse__chevron\"></span>\(htmlEscape(header))</button>"
        html += "<div class=\"collapse__content\"><div class=\"collapse__inner\">"
        buffer.append(html)
        children.render(into: &buffer)
        buffer.append("</div></div></div>")
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
    public init(title: String? = nil, sub: String? = nil, actions: [Action], cancel: String = WebUIStrings.english.cancel,
                id: String? = nil, onSelect: EventHandler? = nil) {
        self.title = title; self.sub = sub; self.actions = actions; self.cancel = cancel
        self.id = id; self.onSelect = onSelect
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = "<div class=\"action-sheet\"\(attrs)" + AriaRole.menu.render() + ">"
        if let title { html += "<div class=\"action-sheet__header\"><div class=\"action-sheet__title\">\(htmlEscape(title))</div>" }
        if let sub { html += "<div class=\"action-sheet__sub\">\(htmlEscape(sub))</div>" }
        if title != nil { html += "</div>" }
        for (index, action) in actions.enumerated() {
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"action-sheet__item\(action.destructive ? " action-sheet__item--destructive" : "")\"\(itemID)" + AriaRole.menuitem.render() + ">\(htmlEscape(action.label))</button>"
        }
        html += "<div class=\"action-sheet__divider\"></div>"
        let cancelID = id.map { " id=\"\(htmlEscape("\($0)-cancel"))\"" } ?? ""
        html += "<button class=\"action-sheet__cancel\"\(cancelID)>\(htmlEscape(cancel))</button>"
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Bottom Sheet
/// bottom-anchored modal surface.
public struct WebUIBottomSheet<Content: View, Footer: View>: View {
    @available(*, deprecated, renamed: "SlidePosition")
    public typealias Variant = SlidePosition
    public let title: String?
    public let children: Content
    public let footer: Footer
    /// whether the footer block has content. the footer wrapper exists only when
    /// it does — the branch `!footer.isEmpty` made over the erased array, decided
    /// once at init.
    public let hasFooter: Bool
    public let position: SlidePosition
    /// stable container id; when set with `onDismiss` the close button
    /// self-wires (`targetId == "<id>-close"`).
    public let id: String?
    public let onDismiss: EventHandler?

    /// this component's own class for a shared shape — same three values, same
    /// bytes, including the leading space the 1.x raw values carried.
    private static func classFor(_ position: SlidePosition) -> String {
        switch position {
            case .peek: return " bottom-sheet--peek"
            case .half: return " bottom-sheet--half"
            case .full: return " bottom-sheet--full"
        }
    }

    public init(title: String? = nil, position: SlidePosition = .half, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content, @ElementBuilder footer: () -> Footer) {
        let builtFooter = footer()
        self.title = title; self.position = position; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = builtFooter
        self.hasFooter = !blockIsEmpty(builtFooter)
    }

    /// no footer: `Footer` is the phantom `EmptyView` and the wrapper is absent.
    public init(title: String? = nil, position: SlidePosition = .half, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content) where Footer == EmptyView {
        self.title = title; self.position = position; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = EmptyView()
        self.hasFooter = false
    }

    /// the 1.x initializer, kept so `variant:` call sites still compile.
    @available(*, deprecated, message: "use position: — SlidePosition is the shared vocabulary")
    public init(title: String? = nil, variant: SlidePosition, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content, @ElementBuilder footer: () -> Footer) {
        self.init(title: title, position: variant, id: id, onDismiss: onDismiss, content: content, footer: footer)
    }

    /// the 1.x initializer without a footer.
    @available(*, deprecated, message: "use position: — SlidePosition is the shared vocabulary")
    public init(title: String? = nil, variant: SlidePosition, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content) where Footer == EmptyView {
        self.init(title: title, position: variant, id: id, onDismiss: onDismiss, content: content)
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onDismiss {
            attrs = controlAttributes(id: id, event: .click, handler: onDismiss)
        } else {
            attrs = ""
        }
        var html = "<div class=\"bottom-sheet\(Self.classFor(position))\"\(attrs)" + Aria.attributes([.modal(.yes)], role: .dialog) + ">"
        html += "<div class=\"bottom-sheet__handle\"></div>"
        if let title {
            let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
            html += "<div class=\"bottom-sheet__header\"><div class=\"bottom-sheet__title\">\(htmlEscape(title))</div><button class=\"bottom-sheet__close\"\(closeID)" + Aria.label(RenderContext.currentStrings.close).render() + ">×</button></div>"
        }
        html += "<div class=\"bottom-sheet__body\">"
        buffer.append(html)
        children.render(into: &buffer)
        buffer.append("</div>")
        if hasFooter {
            buffer.append("<div class=\"bottom-sheet__footer\">")
            footer.render(into: &buffer)
            buffer.append("</div>")
        }
        buffer.append("</div>")
    }
}

// MARK: WebUI Drawer
/// edge-anchored sliding surface.
public struct WebUIDrawer<Content: View, Footer: View>: View {
    @available(*, deprecated, renamed: "DrawerEdge")
    public typealias Edge = DrawerEdge

    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize

    public let title: String?
    public let edge: DrawerEdge
    public let size: ControlSize
    public let children: Content
    public let footer: Footer
    /// whether the footer block has content — see ``WebUIBottomSheet/hasFooter``.
    public let hasFooter: Bool
    /// stable container id; when set with `onDismiss` the close button
    /// self-wires (`targetId == "<id>-close"`).
    public let id: String?
    public let onDismiss: EventHandler?
    /// this component's own class for a shared edge — same four values, same bytes.
    private static func classFor(_ edge: DrawerEdge) -> String {
        switch edge {
            case .left: return " drawer--left"
            case .right: return " drawer--right"
            case .top: return " drawer--top"
            case .bottom: return " drawer--bottom"
        }
    }

    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return " drawer--sm"
            case .md: return ""
            case .lg: return " drawer--lg"
            case .xl: return " drawer--xl"
        }
    }

    public init(title: String? = nil, edge: DrawerEdge = .right, size: ControlSize = .md, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content, @ElementBuilder footer: () -> Footer) {
        let builtFooter = footer()
        self.title = title; self.edge = edge; self.size = size; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = builtFooter
        self.hasFooter = !blockIsEmpty(builtFooter)
    }

    /// no footer: `Footer` is the phantom `EmptyView` and the wrapper is absent.
    public init(title: String? = nil, edge: DrawerEdge = .right, size: ControlSize = .md, id: String? = nil, onDismiss: EventHandler? = nil,
                @ElementBuilder content: () -> Content) where Footer == EmptyView {
        self.title = title; self.edge = edge; self.size = size; self.id = id; self.onDismiss = onDismiss
        self.children = content(); self.footer = EmptyView()
        self.hasFooter = false
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onDismiss {
            attrs = controlAttributes(id: id, event: .click, handler: onDismiss)
        } else {
            attrs = ""
        }
        var html = "<div class=\"drawer\(Self.classFor(edge))\(Self.classFor(size))\"\(attrs)" + Aria.attributes([.modal(.yes)], role: .dialog) + ">"
        html += "<div class=\"drawer__panel\">"
        if let title {
            let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
            html += "<div class=\"drawer__header\"><div class=\"drawer__title\">\(htmlEscape(title))</div><button class=\"drawer__close\"\(closeID)" + Aria.label(RenderContext.currentStrings.close).render() + ">×</button></div>"
        }
        html += "<div class=\"drawer__content\">"
        buffer.append(html)
        children.render(into: &buffer)
        buffer.append("</div>")
        if hasFooter {
            buffer.append("<div class=\"drawer__footer\">")
            footer.render(into: &buffer)
            buffer.append("</div>")
        }
        buffer.append("</div></div>")
    }
}

// MARK: WebUI Popover
/// an anchored floating popover with arrow.
public struct WebUIPopover<Content: View>: View {
    @available(*, deprecated, renamed: "Placement")
    public typealias Side = Placement

    public let title: String?
    public let text: String?
    public let side: Placement
    public let children: Content
    /// whether the content block has content — the `!children.isEmpty` branch,
    /// decided once at init.
    public let hasContent: Bool

    /// this component's own class for a shared placement — the four 1.x anchors
    /// keep their bytes; `leading`/`trailing` forward the pattern.
    private static func classFor(_ side: Placement) -> String {
        switch side {
            case .top: return " popover--top"
            case .bottom: return " popover--bottom"
            case .left: return " popover--left"
            case .right: return " popover--right"
            case .leading: return " popover--leading"
            case .trailing: return " popover--trailing"
        }
    }

    public init(title: String? = nil, text: String? = nil, side: Placement = .bottom,
                @ElementBuilder content: () -> Content) {
        let built = content()
        self.title = title; self.text = text; self.side = side
        self.children = built
        self.hasContent = !blockIsEmpty(built)
    }

    /// no content: `Content` is the phantom `EmptyView` and the actions wrapper
    /// is absent.
    public init(title: String? = nil, text: String? = nil, side: Placement = .bottom) where Content == EmptyView {
        self.title = title; self.text = text; self.side = side
        self.children = EmptyView()
        self.hasContent = false
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"popover\(Self.classFor(side))\">"
        html += "<span class=\"popover__arrow\"></span>"
        if let title { html += "<div class=\"popover__title\">\(htmlEscape(title))</div>" }
        if let text { html += "<div class=\"popover__text\">\(htmlEscape(text))</div>" }
        if hasContent {
            html += "<div class=\"popover__actions\">"
        }
        buffer.append(html)
        if hasContent {
            children.render(into: &buffer)
            buffer.append("</div>")
        }
        buffer.append("</div>")
    }
}

// MARK: WebUI Hover Card
/// a rich card revealed on hover of an anchor.
public struct WebUIHoverCard<Content: View>: View {
    public let name: String
    public let handle: String
    public let bio: String?
    public let meta: [(String, String)]
    public let domain: String
    public let children: Content
    /// whether the content block has content — the `!children.isEmpty` branch,
    /// decided once at init.
    public let hasContent: Bool
    public init(name: String, handle: String, bio: String? = nil, meta: [(String, String)] = [],
                domain: String = "", @ElementBuilder content: () -> Content) {
        let built = content()
        self.name = name; self.handle = handle; self.bio = bio; self.meta = meta
        self.domain = domain; self.children = built
        self.hasContent = !blockIsEmpty(built)
    }

    /// no content: `Content` is the phantom `EmptyView` and the actions wrapper
    /// is absent.
    public init(name: String, handle: String, bio: String? = nil, meta: [(String, String)] = [],
                domain: String = "") where Content == EmptyView {
        self.name = name; self.handle = handle; self.bio = bio; self.meta = meta
        self.domain = domain; self.children = EmptyView()
        self.hasContent = false
    }

    public func render(into buffer: inout HTMLBuffer) {
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
        if hasContent {
            html += "<div class=\"hovercard__actions\">"
        }
        buffer.append(html)
        if hasContent {
            children.render(into: &buffer)
            buffer.append("</div>")
        }
        buffer.append("</div></div>")
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

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<a class=\"link-preview\" href=\"\(htmlEscape(url))\" target=\"_blank\" rel=\"noopener noreferrer\">"
        if let image = image {
            html += "<img class=\"link-preview__img\" src=\"\(htmlEscape(image))\" alt=\"\" loading=\"lazy\">"
        }
        html += "<div class=\"link-preview__body\">"
        html += "<div class=\"link-preview__domain\">\(htmlEscape(domain))</div>"
        if let title { html += "<div class=\"link-preview__title\">\(htmlEscape(title))</div>" }
        if let desc { html += "<div class=\"link-preview__desc\">\(htmlEscape(desc))</div>" }
        html += "<button class=\"link-preview__close\"" + Aria.label(RenderContext.currentStrings.close).render() + ">×</button>"
        html += "</div></a>"
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onNavigate {
            attrs = controlAttributes(id: id, event: .click, handler: onNavigate)
        } else {
            attrs = ""
        }
        var html = "<div class=\"lightbox\"\(attrs)" + Aria.attributes([.modal(.yes)], role: .dialog) + ">"
        html += "<div class=\"lightbox__stage\"><img class=\"lightbox__img\" src=\"\(htmlEscape(image))\" alt=\"\(htmlEscape(caption ?? ""))\"></div>"
        html += "<div class=\"lightbox__toolbar\">"
        if let count { html += "<div class=\"lightbox__counter\">\(htmlEscape(count))</div>" }
        let prevID = id.map { " id=\"\(htmlEscape("\($0)-prev"))\"" } ?? ""
        let nextID = id.map { " id=\"\(htmlEscape("\($0)-next"))\"" } ?? ""
        let closeID = id.map { " id=\"\(htmlEscape("\($0)-close"))\"" } ?? ""
        html += "<button class=\"lightbox__tool\"\(prevID)" + Aria.label(RenderContext.currentStrings.previous).render() + ">‹</button>"
        html += "<button class=\"lightbox__tool\"\(nextID)" + Aria.label(RenderContext.currentStrings.next).render() + ">›</button>"
        html += "<button class=\"lightbox__close\"\(closeID)" + Aria.label(RenderContext.currentStrings.close).render() + ">×</button>"
        html += "</div>"
        if let caption { html += "<div class=\"lightbox__caption\">\(htmlEscape(caption))</div>" }
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Menu
/// a dropdown menu of actions with optional icons, shortcuts, and dividers.
public struct WebUIMenu: View {
    public struct Item: Sendable {
        public let label: String
        public let shortcut: String?
        public let icon: IconName?
        public let disabled: Bool
        /// leading initials chip instead of a glyph.
        public let avatar: String?
        /// muted second line under the label.
        public let hint: String?
        /// marks the item as the current one.
        public let active: Bool
        /// danger treatment.
        public let danger: Bool
        /// opens a submenu; the sheet draws the trailing chevron via `::after`.
        public let submenu: Bool
        /// renders a rule above this item.
        public let dividerBefore: Bool
        /// renders a section label above this item.
        public let section: String?
        /// the older spelling of ``danger``.
        ///
        /// both flags were live at once and the renderer read them separately, so
        /// one item could carry both treatments or neither. this reads through to
        /// `danger`, and exists so a 1.x read keeps compiling.
        @available(*, deprecated, renamed: "danger")
        public var destructive: Bool { danger }

        public init(_ label: String, shortcut: String? = nil, icon: IconName? = nil,
                    disabled: Bool = false,
                    avatar: String? = nil, hint: String? = nil, active: Bool = false,
                    danger: Bool = false, submenu: Bool = false,
                    dividerBefore: Bool = false, section: String? = nil) {
            self.label = label; self.shortcut = shortcut; self.icon = icon
            self.disabled = disabled
            self.avatar = avatar; self.hint = hint; self.active = active
            self.danger = danger; self.submenu = submenu
            self.dividerBefore = dividerBefore; self.section = section
        }

        /// the 1.x initializer, kept so a call site passing `destructive:` still
        /// compiles. it writes through to `danger` — which is what the renderer
        /// reads — so the deprecated spelling keeps its treatment.
        @available(*, deprecated, renamed: "init(_:shortcut:icon:disabled:avatar:hint:active:danger:submenu:dividerBefore:section:)")
        public init(_ label: String, shortcut: String? = nil, icon: IconName? = nil,
                    destructive: Bool, disabled: Bool = false,
                    avatar: String? = nil, hint: String? = nil, active: Bool = false,
                    danger: Bool = false, submenu: Bool = false,
                    dividerBefore: Bool = false, section: String? = nil) {
            self.init(label, shortcut: shortcut, icon: icon, disabled: disabled,
                      avatar: avatar, hint: hint, active: active,
                      danger: danger || destructive, submenu: submenu,
                      dividerBefore: dividerBefore, section: section)
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
    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = "<div class=\"menu\(panel ? " menu__panel" : "")\""
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += "\(attrs)" + AriaRole.menu.render() + ">"
        if let header { html += "<div class=\"menu__header\">\(htmlEscape(header))</div>" }
        if let search {
            html += "<div class=\"menu__search\">"
            html += "<input type=\"search\" placeholder=\"\(htmlEscape(search))\"" + Aria.label(search).render() + ">"
            html += "</div>"
        }
        for (index, item) in items.enumerated() {
            if let section = item.section { html += "<span class=\"menu__section\">\(htmlEscape(section))</span>" }
            if item.dividerBefore { html += "<div class=\"menu__divider\"></div>" }
            var cls = "menu__item"
            // one class for one concept: two flags and two parallel css blocks were
            // the same treatment emitted twice.
            if item.danger { cls += " menu__item--danger" }
            if item.active { cls += " menu__item--active" }
            if item.submenu { cls += " menu__item--has-sub" }
            let itemID = id.map { " id=\"\(htmlEscape("\($0)-item-\(index)"))\"" } ?? ""
            html += "<button class=\"\(cls)\"\(itemID)" + AriaRole.menuitem.render() + "\(item.disabled ? " disabled" : "")>"
            if let avatar = item.avatar {
                html += "<span class=\"menu__avatar\"><span class=\"avatar avatar--initials avatar--sm\">\(htmlEscape(avatar))</span></span>"
            }
            if let icon = item.icon { html += "<span class=\"menu__icon\">\(WebUIIcon(icon, size: .small).markup.html)</span>" }
            html += "<span class=\"menu__label\">\(htmlEscape(item.label))</span>"
            if let hint = item.hint { html += "<span class=\"menu__hint\">\(htmlEscape(hint))</span>" }
            if let shortcut = item.shortcut { html += "<span class=\"menu__shortcut\">\(htmlEscape(shortcut))</span>" }
            html += "</button>"
        }
        html += "</div>"
        buffer.append(html)
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

    public func render(into buffer: inout HTMLBuffer) {
        var html = "<div class=\"context-menu\">"
        let menu = WebUIMenu(items: items, id: id, onSelect: onSelect).markup.html
        html += menu
        html += "</div>"
        buffer.append(html)
    }
}

// MARK: WebUI Dropdown
/// a trigger with an attached options panel.
///
/// the trigger **is** the click boundary. the wrapper is layout only — it
/// carries no routing attributes — so the element the engine resolves as the
/// component (the nearest `data-component-id`) is the same element a caller
/// sees and keys their handler on. putting the boundary on the wrapper while
/// the button carries `id + "-trigger"` instead makes every click report
/// `event.data["targetId"] == "<id>-trigger"`, and a caller keyed on the real
/// id never hears it.
///
/// two ways to supply the trigger:
///
/// - ``init(_:id:onSelect:isOpen:content:)`` renders a text trigger — the
///   label and the chevron — inside the button that is the boundary;
/// - ``init(id:onSelect:isOpen:trigger:panel:)`` takes the trigger as views and
///   renders them **verbatim**: no wrapper button, no injected chevron, no
///   injected attributes, so a caller's own typed control keeps its exact
///   markup, its own `id`, and its own handle. (wrapping a caller's `<button>`
///   in the component's `<button>` would also be invalid html.)
///
/// the panel is open only when ``isOpen`` says so: this framework is
/// server-driven, nothing in the client runtime toggles a dropdown, so opening
/// and closing is a render that flips one bool — not client state, not an
/// animation.
public struct WebUIDropdown<Trigger: View, Panel: View>: View {
    /// the component-rendered trigger's label; `nil` when the caller supplies
    /// ``triggerViews`` instead.
    public let trigger: String?
    /// the caller-rendered trigger, emitted verbatim in place of the button;
    /// the phantom `EmptyView` for the label form.
    public let triggerViews: Trigger
    /// which init built this value: the label form renders the component's own
    /// button, the view form emits the caller's trigger verbatim. this replaces
    /// `triggerViews.isEmpty`, the branch that used to decide it.
    public let hasTriggerViews: Bool
    /// server state: `true` adds `dropdown--open` to the wrapper and
    /// `aria-expanded="true"` to a component-rendered trigger — the pair that
    /// makes `.dropdown--open .dropdown__panel` paint.
    public let isOpen: Bool
    public let children: Panel
    /// stable component id; when set with `onSelect` the trigger carries both
    /// `id="<id>"` and `data-component-id="<id>"` — no `-trigger` suffix, so
    /// the id the engine dispatches to is the id the caller keyed on.
    public let id: String?
    public let onSelect: EventHandler?

    /// a component-rendered text trigger: `trigger` plus the chevron, inside
    /// the button that is the click boundary.
    public init(_ trigger: String, id: String? = nil, onSelect: EventHandler? = nil,
                isOpen: Bool = false,
                @ElementBuilder content: () -> Panel) where Trigger == EmptyView {
        self.trigger = trigger; self.triggerViews = EmptyView()
        self.hasTriggerViews = false
        self.isOpen = isOpen; self.id = id; self.onSelect = onSelect
        self.children = content()
    }

    /// a caller-rendered trigger.
    ///
    /// `trigger`'s views are emitted untouched and are their own boundary:
    /// give them an `id`/`data-component-id`/`aria-*` and the engine dispatches
    /// exactly that id. pass `id:` + `onSelect:` only when the framework should
    /// register the handler too — this form emits no attributes of its own, so
    /// the markup carrying the matching `data-component-id` stays the caller's.
    public init(id: String? = nil, onSelect: EventHandler? = nil, isOpen: Bool = false,
                @ElementBuilder trigger: () -> Trigger,
                @ElementBuilder panel: () -> Panel) {
        let builtTrigger = trigger()
        self.trigger = nil; self.triggerViews = builtTrigger
        self.hasTriggerViews = !blockIsEmpty(builtTrigger)
        self.isOpen = isOpen; self.id = id; self.onSelect = onSelect
        self.children = panel()
        // register-only: the caller owns the attributes, so the canonical
        // routing string is discarded and only the registration is kept.
        if let id, let onSelect, var context = RenderContext.current {
            context.register(handler: onSelect, for: ComponentID(id))
        }
    }

    public func render(into buffer: inout HTMLBuffer) {
        var html = isOpen ? "<div class=\"dropdown dropdown--open\">" : "<div class=\"dropdown\">"
        if !hasTriggerViews {
            var attrs = ""
            if let id {
                attrs += " id=\"\(htmlEscape(id))\""
                attrs += controlAttributes(id: id, event: .click, handler: onSelect)
            }
            // expanded only while open: a closed dropdown keeps the bytes it
            // shipped before this state existed, and its panel is out of the
            // accessibility tree either way (display: none).
            let expanded = isOpen ? Aria.expanded(.yes).render() : ""
            html += "<button class=\"dropdown__trigger\"\(attrs)\(expanded)>"
            html += "\(htmlEscape(trigger ?? ""))<span class=\"dropdown__chevron\">▾</span></button>"
            html += "<div class=\"dropdown__panel\">"
            buffer.append(html)
        } else {
            // the caller's trigger is emitted verbatim, before the panel opens.
            buffer.append(html)
            triggerViews.render(into: &buffer)
            buffer.append("<div class=\"dropdown__panel\">")
        }
        children.render(into: &buffer)
        buffer.append("</div></div>")
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
    public init(placeholder: String = "", options: [Option], emptyMessage: String = WebUIStrings.english.noMatches,
                id: String? = nil, onChange: EventHandler? = nil) {
        self.placeholder = placeholder; self.options = options; self.emptyMessage = emptyMessage
        self.id = id; self.onChange = onChange
    }

    public func render(into buffer: inout HTMLBuffer) {
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
            html += "<div class=\"\(cls)\"\(optID)" + Aria.attributes([.selected(option.selected ? .yes : .no)], role: .option) + ">\(htmlEscape(option.label))</div>"
        }
        html += "</div></div>"
        buffer.append(html)
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
    public init(commands: [Command], placeholder: String = WebUIStrings.english.typeACommand, footer: String? = nil,
                id: String? = nil, onSelect: EventHandler? = nil) {
        self.commands = commands; self.placeholder = placeholder; self.footer = footer
        self.id = id; self.onSelect = onSelect
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onSelect {
            attrs = controlAttributes(id: id, event: .click, handler: onSelect)
        } else {
            attrs = ""
        }
        var html = "<div class=\"command-palette\"\(attrs)" + Aria.attributes([.modal(.yes)], role: .dialog) + ">"
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
        buffer.append(html)
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
    @available(*, deprecated, renamed: "Axis")
    public typealias Orientation = Axis

    public let orientation: Axis
    /// text rendered between two lines. ignored when `icon` is set.
    public let label: String?
    /// glyph rendered on the line. wins over `label`.
    public let icon: IconName?
    public let strong: Bool

    public init(
        _ label: String? = nil,
        orientation: Axis = .horizontal,
        icon: IconName? = nil,
        strong: Bool = false
    ) {
        self.orientation = orientation
        self.label = label
        self.icon = icon
        self.strong = strong
    }

    public func render(into buffer: inout HTMLBuffer) {
            if orientation == .vertical {
                buffer.append("<div class=\"divider divider--vertical\"" + Aria.attributes([.orientation(.vertical)], role: .separator) + "></div>")
                return
            }
            if let icon {
                let glyph = WebUIIcon(icon, size: .slot).markup.html
                buffer.append("<div class=\"divider divider--icon\(strong ? " divider--strong" : "")\"" + AriaRole.separator.render() + "><span class=\"divider__label\">\(glyph)</span></div>")
                return
            }
            if let label {
                buffer.append("<div class=\"divider-divider\"" + AriaRole.separator.render() + "><span class=\"divider-divider__label\">\(htmlEscape(label))</span></div>")
                return
            }
            buffer.append("<div class=\"divider\(strong ? " divider--strong" : "")\"" + AriaRole.separator.render() + "></div>")
    }
}

// MARK: WebUI Kbd
/// a keyboard key or combination. one key renders bare; several render as a
/// combo whose keys sit adjacently (the macOS convention, `⌘K`) or with a
/// separator glyph between them (`separator: "+"`).
public struct WebUIKbd: View {
    @available(*, deprecated, renamed: "ControlSize")
    public typealias Size = ControlSize

    public let keys: [String]
    public let size: ControlSize
    /// glyph placed between keys. `nil` places them adjacently without one.
    public let separator: String?

    /// this component's own class for a shared size — the sheet's bytes are
    /// unchanged for sm/md/lg; xl forwards the same pattern (a theme can honor it).
    private static func classFor(_ size: ControlSize) -> String {
        switch size {
            case .sm: return "kbd--sm"
            case .md: return ""
            case .lg: return "kbd--lg"
            case .xl: return "kbd--xl"
        }
    }

    public init(_ key: String, size: ControlSize = .md) {
        self.keys = [key]
        self.size = size
        self.separator = nil
    }

    public init(_ keys: [String], size: ControlSize = .md, separator: String? = nil) {
        self.keys = keys
        self.size = size
        self.separator = separator
    }

    private func keyHTML(_ key: String) -> String {
        // kbd appends the size class after the base class, so an empty mapping
        // means no trailing space — the shape the 1.x raw values encoded.
        let kbdSize = Self.classFor(size)
        let sizeClass = kbdSize.isEmpty ? "" : " \(kbdSize)"
        return "<kbd class=\"kbd\(sizeClass)\">\(htmlEscape(key))</kbd>"
    }

    public func render(into buffer: inout HTMLBuffer) {
        guard keys.count > 1 else {
            buffer.append(keyHTML(keys.first ?? ""))
            return
        }
        var html = "<span class=\"kbd-combo\">"
        for (index, key) in keys.enumerated() {
            if index > 0, let separator, !separator.isEmpty {
                html += "<span class=\"kbd-sep\">\(htmlEscape(separator))</span>"
            }
            html += keyHTML(key)
        }
        html += "</span>"
        buffer.append(html)
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
        label: String = WebUIStrings.english.backToTop,
        id: String? = nil,
        onTap: EventHandler? = nil
    ) {
        self.progress = progress
        self.icon = icon
        self.label = label
        self.id = id
        self.onTap = onTap
    }

    public func render(into buffer: inout HTMLBuffer) {
        let attrs: String
        if let id, let onTap {
            attrs = controlAttributes(id: id, event: .click, handler: onTap)
        } else {
            attrs = ""
        }
        var html = "<button class=\"scroll-top\(progress != nil ? " scroll-top--ring" : "")\" type=\"button\"" + Aria.label(label).render()
        if let id { html += " id=\"\(htmlEscape(id))\"" }
        html += attrs + ">"
        if let progress {
            let clamped = progress < 0 ? 0 : (progress > 1 ? 1 : progress)
            let offset = webuiFixedPoint((1 - clamped) * 100, places: 1)
            html += "<svg class=\"scroll-top__ring\" viewBox=\"0 0 36 36\"" + Aria.hidden(.yes).render() + ">"
            html += "<circle class=\"ring__track\" cx=\"18\" cy=\"18\" r=\"15.915\"/>"
            html += "<circle class=\"ring__fill\" cx=\"18\" cy=\"18\" r=\"15.915\" stroke-dasharray=\"100\" stroke-dashoffset=\"\(offset)\"/>"
            html += "</svg>"
        }
        html += "<span class=\"scroll-top__icon\">" + WebUIIcon(icon, size: .medium).markup.html + "</span>"
        html += "</button>"
        buffer.append(html)
    }
}
