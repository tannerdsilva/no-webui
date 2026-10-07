import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - Render fixture battery (lane R)
//
// byte-exact render fixtures for every public component in the five
// WebUIDesignSystemCore files lane R rewrites. captured at the arc's base
// (before the Tag-helper refactor), frozen as JSON under
// Tests/WebUITests/Fixtures/R-<file>.json, and asserted byte-for-byte after
// each commit. the content pin covers only ~40 of the ~120 components; this
// battery covers the rest — it is the lane's second byte-identity gate.
//
// each entry is `name → rendered html`; `name` is unique per file and stable
// across the refactor, so a diff names the component, not the line.

enum FixtureBattery {

    /// the five source files and their batteries (in lane R's rewrite order).
    static func renders() -> [(file: String, entries: [(String, String)])] {
        [
            ("WebUIExtrasNavOverlay", navOverlay),
            ("WebUIExtrasData", data),
            ("WebUIComponents", components),
            ("WebUIExtrasCommsState", commsState),
            ("WebUIExtrasForm", form),
        ]
    }

    // MARK: - WebUIExtrasNavOverlay

    static let navOverlay: [(String, String)] = [
        ("navbar", WebUINavbar(brand: "App", links: [.init("Home", href: "/", active: true), .init("Docs", href: "/docs")], sticky: true, search: .init(placeholder: "Search…", shortcut: "Ctrl K", id: "nav-search"), mobileMenu: true, id: "nav", onNavigate: { _ in [] }) { WebUIButton("Go") }.render()),
        ("navbar/bare", WebUINavbar { Text("x") }.render()),
        ("bottomNav", WebUIBottomNav(items: [.init("Home", icon: .home, badge: "3", active: true), .init("Feed", icon: .list), .init("Me", icon: .user)], id: "bn", onSelect: { _ in [] }).render()),
        ("fab/secondary/extended", WebUIFab("Add", icon: .plus, variant: .secondary, size: .lg, extended: true, id: "fab1", onTap: { _ in [] }).render()),
        ("fab/plain", WebUIFab(icon: .plus).render()),
        ("speedDial", WebUISpeedDial { WebUIFab("A", icon: .star); WebUIFab("B", icon: .heart) }.render()),
        ("wizard", WebUIWizard(steps: [.init("One", desc: "start", status: .done), .init("Two", status: .current), .init("Three", status: .plain), .init("Four", status: .error)], vertical: true).render()),
        ("transfer", WebUITransfer(title: "Members", options: [.init("A", selected: true), .init("B", moved: true), .init("C")], searchPlaceholder: "Filter…").render()),
        ("buttonGroup", WebUIButtonGroup { WebUIButton("A"); WebUIButton("B") }.render()),
        ("splitButton", WebUISplitButton("Save", caret: true, id: "sb", onSelect: nil).render()),
        ("splitButton/wired", WebUISplitButton("Save", caret: true, id: "sb", onSelect: { _ in [] }).render()),
        ("toc", WebUIToc(title: "Contents", entries: [.init("Intro", href: "#intro", active: true), .init("Syntax", href: "#syntax", depth: 1), .init("Nested", href: "#n", depth: 2)]).render()),
        ("accordion", WebUIAccordion(items: [.init("One", open: true) { Text("body1") }, .init("Two", open: false) { Text("body2") }], variant: .card, id: "acc", onToggle: { _ in [] }).render()),
        ("collapse", WebUICollapse("Details", open: true, id: "col", onToggle: nil) { Text("inner") }.render()),
        ("collapse/wired", WebUICollapse("Details", open: false, id: "col", onToggle: { _ in [] }) { Text("inner") }.render()),
        ("actionSheet", WebUIActionSheet(title: "Choose", sub: "Pick one", actions: [.init("Edit", destructive: true), .init("Share"), .init("Delete")], cancel: "Cancel", id: "as", onSelect: { _ in [] }).render()),
        ("bottomSheet", WebUIBottomSheet(title: "Sheet", variant: .half, id: "bs", onDismiss: nil) { Text("body") } footer: { WebUIButton("OK") }.render()),
        ("drawer", WebUIDrawer(title: "Filters", edge: .right, size: .md, id: "dr", onDismiss: nil) { Text("body") } footer: { WebUIButton("Apply") }.render()),
        ("popover", WebUIPopover(title: "Tip", text: "More info", side: .top) { WebUIButton("Act") }.render()),
        ("hoverCard", WebUIHoverCard(name: "Ada", handle: "@ada", bio: "Runs", meta: [("Work", "ML"), ("City", "NYC")], domain: "example.com") { WebUIButton("Follow") }.render()),
        ("linkPreview", WebUILinkPreview(url: "https://example.com/a", title: "The Page", desc: "A description.", image: "https://example.com/i.png").render()),
        ("lightbox", WebUILightbox(image: "https://example.com/p.png", caption: "Sunset", count: "2 / 5", id: "lb", onNavigate: { _ in [] }).render()),
        ("menu", WebUIMenu(items: [
            .init("New", shortcut: "⌘N", icon: .plus),
            .init("Rename", avatar: "AB", hint: "Inline", active: true),
            .init("Delete", destructive: true, danger: true, dividerBefore: true),
            .init("More", submenu: true),
        ], id: "menu", onSelect: { _ in [] }, header: "Actions", search: "Find…", panel: true).render()),
        ("menu/plain", WebUIMenu(items: [.init("Cut"), .init("Copy")]).render()),
        ("contextMenu", WebUIContextMenu(items: [.init("Open"), .init("Pin")], id: "cm", onSelect: nil).render()),
        ("dropdown", WebUIDropdown("Menu", id: "dd", onSelect: nil) { WebUIMenu(items: [.init("A")]) }.render()),
        ("comboBox", WebUIComboBox(placeholder: "Pick", options: [.init("One", value: "1", selected: true), .init("Two")], emptyMessage: "None", id: "cb", onChange: { _ in [] }).render()),
        ("comboBox/empty", WebUIComboBox(options: []).render()),
        ("commandPalette", WebUICommandPalette(commands: [.init("Go to file", group: "Navigation", shortcut: "⌘P"), .init("Run", group: "Actions"), .init("New file", group: "Navigation")], placeholder: "Type…", footer: "↑↓ to move", id: "cp", onSelect: { _ in [] }).render()),
        ("separator/vertical", WebUISeparator(orientation: .vertical).render()),
        ("separator/icon", WebUISeparator("or", icon: .star, strong: true).render()),
        ("separator/label", WebUISeparator("or").render()),
        ("separator/plain", WebUISeparator(strong: true).render()),
        ("kbd/single", WebUIKbd("K").render()),
        ("kbd/combo", WebUIKbd(["⌘", "K"], size: .large, separator: "+").render()),
        ("scrollTop", WebUIScrollTop(progress: 0.42, icon: .arrowUp, label: "Top", id: "st", onTap: { _ in [] }).render()),
        ("scrollTop/plain", WebUIScrollTop().render()),
    ]

    // MARK: - WebUIExtrasData

    static let data: [(String, String)] = [
        ("calendar", WebUICalendar(month: "Oct 2026", days: [
            .init(1, muted: true), .init(2, today: true), .init(3, selected: true), .init(4, inRange: true, events: 3),
        ], id: "cal", onChange: { _ in [] }).render()),
        ("calendar/static", WebUICalendar(month: "Oct", days: [.init(5, events: 1)]).render()),
        ("datePicker", WebUIDatePicker(month: "Nov", days: [
            .init(1, disabled: true), .init(2, selected: true), .init(3, today: true, rangeStart: true), .init(4, rangeEnd: true, inRange: true),
        ], id: "dp", onChange: { _ in [] }).render()),
        ("timeZonePicker", WebUITimeZonePicker(entries: [.init("New York", offset: "UTC-4", selected: true), .init("Tokyo", offset: "UTC+9")], id: "tz", onSelect: { _ in [] }).render()),
        ("countryPicker", WebUICountryPicker(entries: [.init(flag: "🇺🇸", name: "United States", code: "US", offset: "+1"), .init(flag: "🇫🇷", name: "France", code: "FR", offset: "+33")], id: "cp", onSelect: { _ in [] }).render()),
        ("gantt", WebUIGantt(rows: [.init("Build", bars: [.init("Setup", start: 0, span: 100, state: ""), .init("Done", start: 1, span: 50, state: "done")])]).render()),
        ("kanban", WebUIKanban(columns: [.init("To do", cards: [.init("Task A", meta: "high", tags: ["bug", "ui"], wip: true), .init("Task B")])]).render()),
        ("dataSheet", WebUIDataSheet(cells: [.init("A1", "10", num: true, selected: true), .init("A2", "hello")]).render()),
        ("jsonTree", WebUIJsonTree(nodes: [
            .init("user", value: "", type: "obj", open: true, children: [
                .init("name", value: "ada"), .init("tags", value: "", type: "arr", open: true, children: [.init("0", value: "a")]),
            ]),
        ]).render()),
        ("jsonTree/leaf", WebUIJsonTree(nodes: [.init("k", value: "v")]).render()),
        ("diff", WebUIDiff(file: "a.swift", stats: "+2 −1", lines: [
            .init("hunk", num: 1, text: "@@ -1,3 +1,4 @@"), .init("add", num: 2, text: "+let x = 1"), .init("del", num: 3, text: "-var y = 2"), .init("ctx", num: 4, text: "print(x)"),
        ]).render()),
        ("terminal", WebUITerminal(title: "build", lines: [.init("ok", text: "✅ done"), .init("warn", text: "warning"), .init("err", text: "error"), .init("info", text: "plain")]).render()),
        ("codeBlock", WebUICodeBlock("let a = 1", language: "swift").render()),
        ("barChart", WebUIBarChart(series: [.init("A", value: 10, accent: true), .init("B", value: 5)]).render()),
        ("lineChart", WebUILineChart(points: [.init(0, 0, label: "a"), .init(1, 2), .init(2, 1)]).render()),
        ("lineChart/empty", WebUILineChart(points: [.init(0, 0)]).render()),
        ("donut", WebUIDonut(slices: [.init("a", value: 2, color: "#f00"), .init("b", value: 1, color: "#0f0")], centerValue: "66%", centerLabel: "of total").render()),
        ("masonry", WebUIMasonry(items: [.init("Card", meta: "sub", accent: true), .init("Two")]).render()),
        ("map", WebUIMap(pins: [.init("HQ", x: 30, y: 40, active: true), .init("Site", x: 70, y: 60)]).render()),
        ("qr", WebUIQr("lane-r", label: "scan").render()),
        ("payCard", WebUIPayCard(number: "4242 4242 4242 4242", holder: "ADA L", brand: .mc).render()),
    ]

    // MARK: - WebUIComponents

    static let components: [(String, String)] = [
        ("button", WebUIButton("Save", variant: .primary, size: .lg, disabled: false, id: "b1", fullWidth: true, loading: true, onTap: { _ in [] }).render()),
        ("button/static", WebUIButton("Save", variant: .ghost, size: .sm).render()),
        ("input", WebUIInput(placeholder: "Name", state: .error, disabled: false, id: "in", type: .text, label: "Name", helpText: "required").render()),
        ("input/success", WebUIInput(state: .success).render()),
        ("card", WebUICard(variant: .elevated, id: "c1", eyebrow: "EYE", title: "Title", description: "Desc", headerIcon: .star, media: .image, mediaBadge: "New", text: "Body text", footerMeta: "2 min", actions: { WebUIButton("Go") }) { Text("Child") }.render()),
        ("card/plain", WebUICard { Text("x") }.render()),
        ("badge", WebUIBadge("New", variant: .primary, size: .lg, dot: true).render()),
        ("badge/plain", WebUIBadge("Old").render()),
        ("alert", WebUIAlert(variant: .danger, title: "Ouch", message: "It broke", dismissible: true, id: "al").render()),
        ("alert/static", WebUIAlert(variant: .info, message: "Note").render()),
        ("tabs", WebUITabs(tabs: [.init(id: "a", label: "One"), .init(id: "b", label: "Two")], activeTab: "a", id: "tb", onSelect: nil).render()),
        ("avatar", WebUIAvatar(initials: "AL", size: .lg, src: "https://e.com/a.png", status: "online").render()),
        ("avatar/initials", WebUIAvatar(initials: "AL").render()),
        ("progress", WebUIProgress(value: 0.42, variant: .success, showLabel: true, size: .lg).render()),
        ("skeleton", WebUISkeleton(variant: .card, width: "200px", height: "80px", count: 2).render()),
        ("toast", WebUIToast(variant: .success, message: "Saved", id: "t1", dismissible: true).render()),
        ("modal", WebUIModal(title: "Confirm", id: "md") { Text("body") } footer: { WebUIButton("OK") }.render()),
        ("table", WebUITable(headers: ["Name", "Size"], rows: [[Text("a"), Text("1")], [Text("b"), Text("2")]], striped: true, hoverable: true, compact: true, responsive: true, wrapped: true, alignments: [.leading, .trailing], footer: nil, emptyState: nil, id: "tbl", sortableColumns: [0], hiddenColumns: [], sort: (0, .descending), selectable: true, rowIds: ["r1", "r2"], selectedRows: ["r1"], expandedRows: ["r1"], rowDetails: ["r1": Text("detail")]).render()),
        ("table/static", WebUITable(headers: ["A"], rows: [[Text("x")]]).render()),
        ("table/empty", WebUITable(headers: ["A"], rows: [], emptyState: .init(icon: .inbox, title: "Empty", message: "Nothing")).render()),
        ("chip", WebUIChip("Tag", variant: .info, removable: true, id: "ch").render()),
        ("emptyState", WebUIEmptyState(icon: .inbox, title: "No data", message: "Try later", action: ("Retry", "retry-1")).render()),
        ("spinner", WebUISpinner(size: .lg, label: "Loading…").render()),
        ("tooltip", WebUITooltip("Hover me", position: .bottom) { Text("tip") }.render()),
        ("stat", WebUIStat(label: "Requests", value: "1,234", size: .lg, trend: "+4.2%", trendDirection: .up, compare: "vs last week", spark: [1, 2, 3, 4]).render()),
        ("stat/compare", WebUIStat(label: "A", value: "1", compare: "flat").render()),
        ("pagination", WebUIPagination(page: 3, pages: 10, id: "pg", rowsPerPage: 25, rowsPerPageOptions: [10, 25, 50]).render()),
        ("pagination/short", WebUIPagination(page: 1, pages: 3).render()),
        ("timeline", WebUITimeline(events: [
            .init(time: "09:00", title: "Start", status: .completed),
            .init(time: "10:00", title: "Now", status: .current),
            .init(time: "11:00", title: "Oops", status: .error),
            .init(time: "12:00", title: "Later"),
        ], orientation: .horizontal).render()),
        ("tree", WebUITree(nodes: [
            .init(id: "n1", label: "Root", icon: .folder, children: [
                .init(id: "n2", label: "Leaf", icon: .fileText),
            ]),
        ], id: "tree", expanded: ["n1"], selected: "n2", onToggle: { _ in [] }).render()),
        ("breadcrumb", WebUIBreadcrumb(items: [.init("Home", href: "/"), .init("Docs", href: "/docs")], current: .init("Page"), slash: true, id: "bc", collapse: true, maxItems: 5).render()),
        ("breadcrumb/collapsed", WebUIBreadcrumb(items: [.init("A", href: "/a"), .init("B", href: "/b"), .init("C", href: "/c")], current: .init("D")).render()),
        ("descriptionList", WebUIDescriptionList([("Name", "Ada"), ("Role", "Admin")]).render()),
        ("aspectRatio", WebUIAspectRatio(.wide, label: "16 / 9").render()),
        ("circularProgress", WebUICircularProgress(value: 0.7, label: "70", sublabel: "done", tone: .success, size: .large, indeterminate: false, ariaLabel: "progress").render()),
        ("circularProgress/ind", WebUICircularProgress(value: 0.5, indeterminate: true).render()),
    ]

    // MARK: - WebUIExtrasCommsState

    static let commsState: [(String, String)] = [
        ("mention", WebUIMention(text: "ada").render()),
        ("mention/dropdown", WebUIMention(text: "a", options: [.init("Ada", handle: "@ada", active: true), .init("Bob", handle: "@bob")], id: "mn", onSelect: { _ in [] }).render()),
        ("reactions", WebUIReactions(reactions: [.init("👍", count: 3, active: true), .init("❤️", count: 1)], id: "rx", onChange: { _ in [] }).render()),
        ("typingIndicator", WebUITypingIndicator(inline: true).render()),
        ("notification", WebUINotification(title: "Update", text: "New version", time: "2h", read: false, icon: .info, id: "nt", onTap: { _ in [] }).render()),
        ("notification/read", WebUINotification(text: "hi", read: true).render()),
        ("toastStack", WebUIToastStack { WebUIToast(variant: .info, message: "one"); WebUIToast(variant: .danger, message: "two") }.render()),
        ("bell", WebUIBell(count: 3, icon: .bell, id: "bl", onTap: { _ in [] }).render()),
        ("statCard", WebUIStatCard("Uptime", value: "99.9%", delta: "+0.1%", trend: "up", accent: true).render()),
        ("delta", WebUIDelta("+12%", direction: .down).render()),
        ("celebrate", WebUICelebrate(emoji: "🎉", title: "Done", text: "All passed").render()),
        ("confetti", WebUIConfetti(round: false).render()),
        ("countdown", WebUICountdown(label: "Until launch", units: [.init(2, label: "d"), .init(3, label: "h")], urgent: true).render()),
        ("cookieConsent", WebUICookieConsent(title: "Cookies", text: "We use them.") { WebUIButton("OK") }.render()),
        ("pullRefresh", WebUIPullRefresh(state: .active, text: "Refreshing…", id: "pr", onRefresh: { _ in [] }).render()),
        ("skeletonCard", WebUISkeletonCard(withMedia: true).render()),
        ("appletCard", WebUIAppletCard(title: "GitHub", value: "12").render()),
        ("avatarStack", WebUIAvatarStack(initials: ["AL", "BO"], more: 3).render()),
        ("badgeStatus", WebUIBadgeStatus("Online", status: .online).render()),
        ("badgeCount", WebUIBadgeCount(count: 5, icon: .bell).render()),
        ("radioGroup", WebUIRadioGroup(options: [.init("A", value: "a"), .init("B", value: "b")], selected: "a", inline: true).render()),
        ("checkboxGroup", WebUICheckboxGroup(options: [.init("A", checked: true), .init("B")], inline: false).render()),
        ("banner", WebUIBanner(variant: .warning, title: "Heads up", message: "Careful", dismissible: true, id: "bn").render()),
        ("activityFeed", WebUIActivityFeed([.init("Today", items: [.init(icon: .star, text: "Loved a post", time: "2h"), .init(icon: .user, text: "Joined")]), .init("Earlier", items: [.init(icon: .check, text: "Done")])]).render()),
        ("messageScroller", WebUIMessageScroller(height: "20rem", id: "ms", fade: true, ariaLabel: "Chat") { Text("old"); Text("new") }.render()),
        ("marker", WebUIMarker("Tuesday", icon: .calendar, sticky: true, spread: false).render()),
        ("attachment", WebUIAttachment(name: "photo.png", meta: "2 MB", icon: .fileText, state: .uploading, removable: true, id: "at").render()),
        ("attachment/readme", WebUIAttachment(name: "a.txt").render()),
        ("chatBubble", WebUIChatBubble("hi there", side: .sent, time: "09:41", receipt: .read, reactions: [.init(label: "👍", count: 1, active: true)], id: "cb").render()),
        ("chatBubble/in", WebUIChatBubble("yo").render()),
        ("message", WebUIMessage(name: "Ada", text: "hello\nworld", time: "09:42", own: true, reactions: [.init(label: "❤️", count: 2)]).render()),
    ]

    // MARK: - WebUIExtrasForm

    static let form: [(String, String)] = [
        ("slider", WebUISlider(42, min: 0, max: 100, size: .lg, vertical: true, showLabels: true, minLabel: "0", maxLabel: "100", id: "sl", onChange: { _ in [] }).render()),
        ("slider/plain", WebUISlider(5, max: 10).render()),
        ("toggle", WebUIToggle("Enabled", checked: true, size: .lg, labelLeft: true, loading: true, disabled: false, id: "tg", onChange: { _ in [] }).render()),
        ("toggle/plain", WebUIToggle("Off").render()),
        ("stepper", WebUIStepper(3, size: .sm, id: "st", onChange: { _ in [] }).render()),
        ("otp", WebUIOTP(length: 4, value: [1, 2], size: .lg, error: true, id: "ot", onChange: { _ in [] }).render()),
        ("mfa", WebUIMFA(recoveryCodes: [.init("AAAA-1111"), .init("BBBB-2222")]).render()),
        ("mfa/none", WebUIMFA().render()),
        ("recurrence", WebUIRecurrence(options: [.init("Daily", active: true), .init("Weekly")], days: ["M", "T", "W"], id: "rc", onChange: { _ in [] }).render()),
        ("multiSelect", WebUIMultiSelect(options: [.init("Red", selected: true), .init("Green", selected: true), .init("Blue")], placeholder: "Pick…", id: "ms", onChange: { _ in [] }).render()),
        ("validation", WebUIValidation("Must be unique", state: .success).render()),
        ("dropZone", WebUIDropZone("Drop files", hint: "or click", hover: true).render()),
        ("signature", WebUISignature("Sign here").render()),
        ("inlineEdit", WebUIInlineEdit("Hello", state: .editing, error: true, id: "ie", onSave: { _ in [] }).render()),
        ("inlineEdit/idle", WebUIInlineEdit("Hello").render()),
        ("masked", WebUIMasked("secret", prefix: "$", masked: true).render()),
        ("rating", WebUIRating(3.5, max: 5, size: .lg, heart: true, showValue: true, id: "rt", onChange: { _ in [] }).render()),
        ("rating/plain", WebUIRating(2, max: 5).render()),
        ("tag", WebUITag("Swift", variant: .success, removable: true, clickable: true, count: 2, icon: .star, id: "tg2", onRemove: { _ in [] }).render()),
        ("chipInput", WebUIChipInput(chips: ["a", "b"], placeholder: "Add…", id: "ci", onChange: { _ in [] }).render()),
        ("cardInput", WebUICardInput(number: "4242", holder: "Ada", brand: .amex).render()),
        ("inputGroup", WebUIInputGroup(placeholder: "Amount", prefix: "$", icon: .dollarSign, suffix: "USD", type: .text, state: .error, name: "amt", id: "ig", value: "12", disabled: false).render()),
        ("inputGroup/plain", WebUIInputGroup().render()),
        ("field", WebUIField(label: "Email", controlID: "em", required: true, note: "Required", noteKind: .error, count: "4 / 10", helper: "Enter it", helperIsError: true) { WebUIInput(placeholder: "you@x.com", id: "em") }.render()),
        ("field/bare", WebUIField { WebUIInput() }.render()),
        ("toggleGroup", WebUIToggleGroup(options: [.init("a", "All", selected: true), .init("b", "Mine")], id: "tgg", onToggle: { _ in [] }).render()),
    ]

    // MARK: - fixture I/O (lane R)

    /// the fixtures directory, derived from this file's own path so the tests
    /// run from any working directory.
    static var fixturesDir: String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        return testsDir + "/Fixtures"
    }

    static func fixturePath(for file: String) -> String {
        fixturesDir + "/R-" + file + ".json"
    }

    static func encode(_ entries: [(String, String)]) throws -> Data {
        let pairs = entries.map { [String($0.0), $0.1] }
        return try JSONSerialization.data(withJSONObject: pairs, options: [.prettyPrinted, .sortedKeys])
    }

    static func decode(_ data: Data) throws -> [String: String] {
        let pairs = try JSONSerialization.jsonObject(with: data) as? [[String]] ?? []
        var out: [String: String] = [:]
        for p in pairs where p.count == 2 { out[p[0]] = p[1] }
        return out
    }

    static func battery(for file: String) -> [(String, String)] {
        renders().first { $0.file == file }?.entries ?? []
    }
}

// MARK: - byte-identity assertions

private func assertByteIdentity(file: String) throws {
    struct Mismatch: Error, CustomStringConvertible {
        let name: String
        let expected: String
        let actual: String
        var description: String {
            "byte mismatch in \(name):\n--- expected ---\n\(expected)\n--- actual ---\n\(actual)"
        }
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: FixtureBattery.fixturePath(for: file)))
    let fixture = try FixtureBattery.decode(data)
    var checked = 0
    for (name, html) in FixtureBattery.battery(for: file) {
        let expected = fixture[name]
        #expect(expected != nil, "no fixture captured for \(name) in \(file)")
        guard let expected else { continue }
        checked += 1
        if expected != html {
            throw Mismatch(name: name, expected: expected, actual: html)
        }
    }
    #expect(checked == fixture.count, "battery (\(checked)) and fixture (\(fixture.count)) entry counts differed in \(file)")
}

@Test("R: WebUIExtrasNavOverlay renders byte-identical to the base capture")
func renderNavOverlayBytes() throws { try assertByteIdentity(file: "WebUIExtrasNavOverlay") }

@Test("R: WebUIExtrasData renders byte-identical to the base capture")
func renderDataBytes() throws { try assertByteIdentity(file: "WebUIExtrasData") }

@Test("R: WebUIComponents renders byte-identical to the base capture")
func renderComponentsBytes() throws { try assertByteIdentity(file: "WebUIComponents") }

@Test("R: WebUIExtrasCommsState renders byte-identical to the base capture")
func renderCommsStateBytes() throws { try assertByteIdentity(file: "WebUIExtrasCommsState") }

@Test("R: WebUIExtrasForm renders byte-identical to the base capture")
func renderFormBytes() throws { try assertByteIdentity(file: "WebUIExtrasForm") }
