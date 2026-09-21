import Testing
import Foundation
import WebUI
import WebUIDesignSystem

// MARK: - Navigation & chrome extras

@Test("WebUINavbar renders brand, links, and sticky marker")
func navbar() {
    let v = WebUINavbar(brand: "App", links: [.init("Home", href: "/", active: true)], sticky: true) { Text("a") }
    let h = v.render()
    #expect(h.contains("class=\"navbar navbar--sticky\""))
    #expect(h.contains("navbar__brand"))
    #expect(h.contains("navbar__link navbar__link--active"))
}

@Test("WebUIBottomNav renders items with icons and badge")
func bottomNav() {
    let v = WebUIBottomNav(items: [.init("Home", icon: .star, badge: "3", active: true)])
    #expect(v.render().contains("class=\"bottom-nav\""))
    #expect(v.render().contains("bottom-nav__item"))
}

@Test("WebUIFab renders with icon and label")
func fab() {
    let v = WebUIFab("Add", icon: .star, variant: .secondary, extended: true)
    let h = v.render()
    #expect(h.contains("fab fab--secondary fab--extended"))
    #expect(h.contains("fab__label"))
}

@Test("WebUISpeedDial wraps children in a dial stage")
func speedDial() {
    let v = WebUISpeedDial { WebUIFab("A", icon: .star) }
    #expect(v.render().contains("class=\"fab-stage fab-stage--dial\""))
}

@Test("WebUIWizard renders steps and status")
func wizard() {
    let v = WebUIWizard(steps: [.init("One", desc: "d", status: .current), .init("Two", status: .completed)], vertical: true)
    let h = v.render()
    #expect(h.contains("class=\"wizard wizard--vertical\""))
    #expect(h.contains("wizard__step--current"))
    #expect(h.contains("wizard__step--completed"))
}

@Test("WebUITransfer renders dual list")
func transfer() {
    let v = WebUITransfer(title: "Members", options: [.init("A"), .init("B", selected: true, moved: true)])
    #expect(v.render().contains("class=\"transfer\""))
    #expect(v.render().contains("transfer__item--selected"))
}

@Test("WebUIButtonGroup joins buttons")
func buttonGroup() {
    let v = WebUIButtonGroup { WebUIButton("A"); WebUIButton("B") }
    #expect(v.render().contains("class=\"button-group\""))
}

@Test("WebUISplitButton renders main + caret")
func splitButton() {
    let v = WebUISplitButton("Save")
    let h = v.render()
    #expect(h.contains("class=\"split-button\""))
    #expect(h.contains("button--caret"))
}

@Test("WebUIToc renders table of contents")
func toc() {
    let v = WebUIToc(entries: [.init("Intro", href: "#intro", active: true), .init("Details", href: "#d", depth: 1)])
    let h = v.render()
    #expect(h.contains("class=\"toc-rail\""))
    #expect(h.contains("toc-rail__item--active"))
}

// MARK: - Overlays & surfaces extras

@Test("WebUIAccordion renders items")
func accordion() {
    let v = WebUIAccordion(items: [.init("One", open: true) { Text("body") }], variant: .card)
    let h = v.render()
    #expect(h.contains("class=\"accordion accordion--card\""))
    #expect(h.contains("accordion__item--open"))
}

@Test("WebUICollapse renders header and content")
func collapse() {
    let v = WebUICollapse("Head", open: true) { Text("body") }
    #expect(v.render().contains("class=\"collapse collapse--open\""))
}

@Test("WebUIActionSheet renders actions and cancel")
func actionSheet() {
    let v = WebUIActionSheet(title: "Actions", actions: [.init("Delete", destructive: true)])
    let h = v.render()
    #expect(h.contains("class=\"action-sheet\""))
    #expect(h.contains("action-sheet__item--destructive"))
}

@Test("WebUIBottomSheet renders dialog")
func bottomSheet() {
    let v = WebUIBottomSheet(title: "Sheet", variant: .half) { Text("body") } footer: { WebUIButton("Done") }
    let h = v.render()
    #expect(h.contains("class=\"bottom-sheet bottom-sheet--half\""))
    #expect(h.contains("bottom-sheet__footer"))
}

@Test("WebUIDrawer renders edged surface")
func drawer() {
    let v = WebUIDrawer(title: "Drawer", edge: .right, size: .lg) { Text("body") }
    let h = v.render()
    #expect(h.contains("class=\"drawer drawer--right drawer--lg\""))
    #expect(h.contains("drawer__panel"))
}

@Test("WebUIPopover renders anchored popover")
func popover() {
    let v = WebUIPopover(title: "Info", text: "tip", side: .top)
    let h = v.render()
    #expect(h.contains("class=\"popover popover--top\""))
    #expect(h.contains("popover__arrow"))
}

@Test("WebUIHoverCard renders rich card")
func hoverCard() {
    let v = WebUIHoverCard(name: "Alice", handle: "@alice", bio: "hi", meta: [("Role", "Admin")], domain: "example.com")
    let h = v.render()
    #expect(h.contains("class=\"hovercard\""))
    #expect(h.contains("hovercard__bio"))
}

@Test("WebUILinkPreview renders url preview")
func linkPreview() {
    let v = WebUILinkPreview(url: "https://example.com", title: "Title", desc: "Desc")
    let h = v.render()
    #expect(h.contains("class=\"link-preview\""))
    #expect(h.contains("link-preview__domain"))
}

@Test("WebUILightbox renders viewer")
func lightbox() {
    let v = WebUILightbox(image: "/img.png", caption: "cap", count: "1/3")
    let h = v.render()
    #expect(h.contains("class=\"lightbox\""))
    #expect(h.contains("lightbox__caption"))
}

@Test("WebUIMenu renders items with shortcuts")
func menu() {
    let v = WebUIMenu(items: [.init("Copy", shortcut: "⌘C", icon: .copy, destructive: false)])
    let h = v.render()
    #expect(h.contains("class=\"menu\" role=\"menu\""))
    #expect(h.contains("menu__shortcut"))
}

@Test("WebUIContextMenu renders context menu")
func contextMenu() {
    let v = WebUIContextMenu(items: [.init("Open")])
    #expect(v.render().contains("class=\"context-menu\""))
}

@Test("WebUIDropdown renders trigger + panel")
func dropdown() {
    let v = WebUIDropdown("Options") { Text("item") }
    let h = v.render()
    #expect(h.contains("class=\"dropdown\""))
    #expect(h.contains("dropdown__trigger"))
}

@Test("WebUIComboBox renders options panel")
func combo() {
    let v = WebUIComboBox(placeholder: "Search", options: [.init("One", selected: true)], emptyMessage: "none")
    let h = v.render()
    #expect(h.contains("class=\"combo\""))
    #expect(h.contains("combo__option--selected"))
}

@Test("WebUICommandPalette renders grouped commands")
func commandPalette() {
    let v = WebUICommandPalette(commands: [.init("New File", group: "File"), .init("New Folder", group: "File")], footer: "navigator")
    let h = v.render()
    #expect(h.contains("class=\"command-palette\""))
    #expect(h.contains("command-palette__group-label"))
}

// MARK: - Data & rich display extras

@Test("WebUICalendar renders month grid")
func calendar() {
    let v = WebUICalendar(month: "January", days: [.init(1, today: true), .init(2, selected: true, events: 2)])
    let h = v.render()
    #expect(h.contains("class=\"calendar\""))
    #expect(h.contains("calendar__day--today"))
    #expect(h.contains("calendar__event-dot"))
}

@Test("WebUIDatePicker renders day grid")
func datePicker() {
    let v = WebUIDatePicker(month: "Jan", days: [.init(1, today: true), .init(2, rangeStart: true), .init(3, inRange: true)])
    let h = v.render()
    #expect(h.contains("class=\"date-picker\""))
    #expect(h.contains("date-picker__day--range-start"))
}

@Test("WebUITimeZonePicker renders list")
func tzPicker() {
    let v = WebUITimeZonePicker(entries: [.init("UTC", offset: "+0", selected: true)])
    #expect(v.render().contains("class=\"tz-picker\""))
}

@Test("WebUICountryPicker renders rows")
func countryPicker() {
    let v = WebUICountryPicker(entries: [.init(flag: "US", name: "United States", code: "+1", offset: "EST")])
    let h = v.render()
    #expect(h.contains("class=\"country-picker\""))
    #expect(h.contains("country-picker__flag"))
}

@Test("WebUIGantt renders rows and bars")
func gantt() {
    let v = WebUIGantt(rows: [.init("Build", bars: [.init("compile", start: 0, span: 5, state: "gantt__bar--done")])])
    let h = v.render()
    #expect(h.contains("class=\"gantt\""))
    #expect(h.contains("gantt__bar"))
}

@Test("WebUIKanban renders columns")
func kanban() {
    let v = WebUIKanban(columns: [.init("Todo", cards: [.init("Task", meta: "m", tags: ["ui", "urgent"], wip: true)])])
    let h = v.render()
    #expect(h.contains("class=\"kanban\""))
    #expect(h.contains("kanban__card--wip"))
}

@Test("WebUIDataSheet renders grid")
func dataSheet() {
    let v = WebUIDataSheet(cells: [.init("A1", "hello", num: true), .init("A2", "42", selected: true)])
    let h = v.render()
    #expect(h.contains("class=\"sheet\""))
    #expect(h.contains("sheet__cell--selected"))
}

@Test("WebUIJsonTree renders nested nodes")
func jsonTree() {
    let v = WebUIJsonTree(nodes: [.init("user", value: "", type: "num", open: true, children: [.init("name", value: "a", type: "str")])])
    let h = v.render()
    #expect(h.contains("class=\"json-tree\""))
    #expect(h.contains("json-tree__children"))
}

@Test("WebUIDiff renders unified diff")
func diff() {
    let v = WebUIDiff(file: "a.swift", stats: "+2 −1", lines: [.init("add", num: 1, text: "x"), .init("del", num: 2, text: "y"), .init("hunk", num: 3, text: "@@")])
    let h = v.render()
    #expect(h.contains("class=\"diff\""))
    #expect(h.contains("diff__line--add"))
}

@Test("WebUITerminal renders shell window")
func terminal() {
    let v = WebUITerminal(title: "build", lines: [.init("ok", text: "done"), .init("err", text: "boom")])
    let h = v.render()
    #expect(h.contains("class=\"terminal\""))
    #expect(h.contains("terminal__line--err"))
}

@Test("WebUICodeBlock renders code")
func codeBlock() {
    let v = WebUICodeBlock("let x = 1", language: "swift")
    let h = v.render()
    #expect(h.contains("class=\"codeblock\""))
    #expect(h.contains("codeblock__lang"))
}

@Test("WebUIBarChart renders bars")
func barChart() {
    let v = WebUIBarChart(series: [.init("A", value: 3), .init("B", value: 8, accent: true)])
    let h = v.render()
    #expect(h.contains("class=\"bar-chart\""))
    #expect(h.contains("bar-chart__bar--accent"))
}

@Test("WebUILineChart renders svg line")
func lineChart() {
    let v = WebUILineChart(points: [.init(0, 1), .init(1, 3), .init(2, 2)])
    let h = v.render()
    #expect(h.contains("class=\"line-chart\""))
    #expect(h.contains("line-chart__line"))
}

@Test("WebUIDonut renders with center value")
func donut() {
    let v = WebUIDonut(slices: [.init("iOS", value: 44, color: "#6366f1")], centerValue: "10", centerLabel: "total")
    let h = v.render()
    #expect(h.contains("class=\"donut\""))
    #expect(h.contains("donut__center-value"))
}

@Test("WebUIMasonry renders items")
func masonry() {
    let v = WebUIMasonry(items: [.init("a", meta: "m", accent: true)])
    let h = v.render()
    #expect(h.contains("class=\"masonry\""))
    #expect(h.contains("masonry__item--accent"))
}

@Test("WebUIMap renders pins")
func map() {
    let v = WebUIMap(pins: [.init("HQ", x: 40, y: 60, active: true)])
    let h = v.render()
    #expect(h.contains("class=\"map\""))
    #expect(h.contains("map__pin--active"))
    #expect(h.contains("map__popup"))
}

@Test("WebUIQr renders matrix")
func qr() {
    let v = WebUIQr("hello", label: "scan")
    let h = v.render()
    #expect(h.contains("class=\"qr\""))
    #expect(h.contains("qr__cell"))
}

@Test("WebUIPayCard renders preview")
func payCard() {
    let v = WebUIPayCard(number: "4111 1111 1111 1111", holder: "J Doe", brand: .visa)
    let h = v.render()
    #expect(h.contains("class=\"paycard\""))
    #expect(h.contains("paycard__number"))
}

// MARK: - Forms & input extras

@Test("WebUISlider renders track, fill, thumb")
func slider() {
    let v = WebUISlider(50, min: 0, max: 100, size: .lg, showLabels: true)
    let h = v.render()
    #expect(h.contains("class=\"slider slider--lg\""))
    #expect(h.contains("slider__fill"))
    #expect(h.contains("slider__thumb"))
}

@Test("WebUIToggle renders switch")
func toggle() {
    let v = WebUIToggle("Enabled", checked: true, size: .lg)
    let h = v.render()
    #expect(h.contains("class=\"toggle toggle--lg\""))
    #expect(h.contains("toggle__track"))
    #expect(h.contains("checked"))
}

@Test("WebUIStepper renders +/− controls")
func stepper() {
    let v = WebUIStepper(3, size: .sm)
    let h = v.render()
    #expect(h.contains("class=\"stepper stepper--sm\""))
    #expect(h.contains("stepper__btn"))
}

@Test("WebUIOTP renders digit cells")
func otp() {
    let v = WebUIOTP(length: 6, value: [1, 2], error: true)
    let h = v.render()
    #expect(h.contains("class=\"otp otp--error\""))
    #expect(h.contains("otp__cell--filled"))
}

@Test("WebUIMFA renders qr and steps")
func mfa() {
    let v = WebUIMFA(recoveryCodes: [.init("AAAA-BBBB")])
    let h = v.render()
    #expect(h.contains("class=\"mfa\""))
    #expect(h.contains("mfa__recovery-item"))
}

@Test("WebUIRecurrence renders options and days")
func recurrence() {
    let v = WebUIRecurrence(options: [.init("Daily", active: true), .init("Weekly")])
    let h = v.render()
    #expect(h.contains("class=\"recurrence\""))
    #expect(h.contains("recurrence__chip--active"))
}

@Test("WebUIMultiSelect renders selected chips")
func multiSelect() {
    let v = WebUIMultiSelect(options: [.init("One", selected: true), .init("Two")], placeholder: "Pick")
    let h = v.render()
    #expect(h.contains("class=\"multiselect\""))
    #expect(h.contains("multiselect__trigger"))
    #expect(h.contains("multiselect__option--selected"))
}

@Test("WebUIValidation renders message")
func validation() {
    let v = WebUIValidation("too long", state: .warning)
    let h = v.render()
    #expect(h.contains("class=\"validation validation--warning\""))
    #expect(h.contains("validation__text"))
}

@Test("WebUIDropZone renders drop target")
func dropZone() {
    let v = WebUIDropZone("Drop files", hint: "or click", hover: true)
    let h = v.render()
    #expect(h.contains("class=\"dropzone dropzone--hover\""))
}

@Test("WebUISignature renders pad")
func signature() {
    let v = WebUISignature("Sign here")
    #expect(v.render().contains("class=\"sigpad\""))
}

@Test("WebUIInlineEdit renders states")
func inlineEdit() {
    let v = WebUIInlineEdit("name", state: .editing, error: true)
    let h = v.render()
    #expect(h.contains("inline-edit--editing"))
    #expect(h.contains("inline-edit--error"))
    #expect(h.contains("inline-edit__input--error"))
}

@Test("WebUIMasked renders masked value")
func masked() {
    let v = WebUIMasked("1234", prefix: "$", masked: true)
    let h = v.render()
    #expect(h.contains("class=\"masked\""))
    #expect(h.contains("masked__prefix"))
}

@Test("WebUIRating renders stars")
func rating() {
    let v = WebUIRating(4, max: 5, showValue: true)
    let h = v.render()
    #expect(h.contains("class=\"rating rating--filled\""))
    #expect(h.contains("rating__star"))
    #expect(h.contains("rating__value"))
}

@Test("WebUITag renders variants")
func tag() {
    let v = WebUITag("beta", variant: .primary, removable: true, count: 3)
    let h = v.render()
    #expect(h.contains("class=\"tag tag--primary\""))
    #expect(h.contains("tag__remove"))
}

@Test("WebUIChipInput renders chips and input")
func chipInput() {
    let v = WebUIChipInput(chips: ["a", "b"], placeholder: "add")
    let h = v.render()
    #expect(h.contains("class=\"chip-input\""))
    #expect(h.contains("chip__remove"))
}

@Test("WebUICardInput renders card fields")
func cardInput() {
    let v = WebUICardInput(number: "4111", holder: "J", brand: .visa)
    let h = v.render()
    #expect(h.contains("class=\"card-input\""))
    #expect(h.contains("card-input__brand-icon--visa"))
}

// MARK: - Comms & social extras

@Test("WebUIMention renders inline mention")
func mention() {
    let v = WebUIMention(text: "alice")
    #expect(v.render().contains("class=\"mention\""))
}

@Test("WebUIMention renders suggestion dropdown")
func mentionDropdown() {
    let v = WebUIMention(options: [.init("Alice", handle: "@alice", active: true)])
    let h = v.render()
    #expect(h.contains("class=\"mention-dropdown\""))
    #expect(h.contains("mention-option--active"))
}

@Test("WebUIReactions renders emoji counts")
func reactions() {
    let v = WebUIReactions(reactions: [.init("👍", count: 3, active: true)])
    let h = v.render()
    #expect(h.contains("class=\"reactions\""))
    #expect(h.contains("reactions__emoji--active"))
}

@Test("WebUITypingIndicator renders dots")
func typing() {
    let v = WebUITypingIndicator(inline: true)
    #expect(v.render().contains("class=\"typing typing--inline\""))
}

@Test("WebUINotification renders notification")
func notification() {
    let v = WebUINotification(title: "Hi", text: "msg", time: "1m", read: false, icon: nil)
    let h = v.render()
    #expect(h.contains("class=\"notification\""))
    #expect(h.contains("notification__unread"))
}

@Test("WebUIToastStack wraps toasts")
func toastStack() {
    let v = WebUIToastStack { WebUIToast(variant: .success, message: "saved") }
    #expect(v.render().contains("class=\"toast-stack\""))
}

@Test("WebUIBell renders badge")
func bell() {
    let v = WebUIBell(count: 3)
    let h = v.render()
    #expect(h.contains("class=\"bell\""))
    #expect(h.contains("bell__badge"))
}

// MARK: - Feedback & state extras

@Test("WebUIStatCard renders metric")
func statCard() {
    let v = WebUIStatCard("Requests", value: "12M", delta: "+8%", trend: "up", accent: true)
    let h = v.render()
    #expect(h.contains("class=\"stat-card stat-card--accent\""))
    #expect(h.contains("stat-card__delta"))
}

@Test("WebUIDelta renders trend")
func delta() {
    let v = WebUIDelta("+1%", direction: .down)
    #expect(v.render().contains("class=\"delta delta--down\""))
}

@Test("WebUICelebrate renders celebration")
func celebrate() {
    let v = WebUICelebrate(emoji: "🎉", title: "Done", text: "nice")
    let h = v.render()
    #expect(h.contains("class=\"celebrate\""))
    #expect(h.contains("celebrate__emoji"))
}

@Test("WebUIConfetti renders burst")
func confetti() {
    let v = WebUIConfetti()
    #expect(v.render().contains("class=\"confetti confetti--round\""))
}

@Test("WebUICountdown renders units")
func countdown() {
    let v = WebUICountdown(label: "Launch", units: [.init(5, label: "m"), .init(3, label: "s")], urgent: true)
    let h = v.render()
    #expect(h.contains("class=\"countdown countdown--urgent\""))
    #expect(h.contains("countdown__unit"))
}

@Test("WebUICookieConsent renders banner")
func cookieConsent() {
    let v = WebUICookieConsent(title: "Cookies", text: "we use cookies") { WebUIButton("Accept") }
    let h = v.render()
    #expect(h.contains("class=\"cookie-consent\""))
    #expect(h.contains("cookie-consent__actions"))
}

@Test("WebUIPullRefresh renders indicator")
func pullRefresh() {
    let v = WebUIPullRefresh(state: .active, text: "refreshing")
    #expect(v.render().contains("class=\"pull-refresh pull-refresh--active\""))
}

@Test("WebUISkeletonCard renders placeholder")
func skeletonCard() {
    let v = WebUISkeletonCard(withMedia: true)
    #expect(v.render().contains("class=\"skeleton-card\""))
}

@Test("WebUIAppletCard renders tile")
func appletCard() {
    let v = WebUIAppletCard(title: "instances", value: "8")
    let h = v.render()
    #expect(h.contains("class=\"applet-card\""))
    #expect(h.contains("applet-card__value"))
}

@Test("WebUIAvatarStack renders overlapping avatars")
func avatarStack() {
    let v = WebUIAvatarStack(initials: ["TS", "JD"], more: 2)
    let h = v.render()
    #expect(h.contains("class=\"avatar-stack\""))
    #expect(h.contains("avatar--more"))
}

@Test("WebUIBadgeStatus renders status")
func badgeStatus() {
    let v = WebUIBadgeStatus("online", status: .busy)
    #expect(v.render().contains("class=\"badge-status\""))
}

@Test("WebUIBadgeCount renders icon count")
func badgeCount() {
    let v = WebUIBadgeCount(count: 5, icon: .bell)
    let h = v.render()
    #expect(h.contains("class=\"badge-count\""))
    #expect(h.contains("badge-count__num"))
}

@Test("WebUIRadioGroup renders options")
func radioGroup() {
    let v = WebUIRadioGroup(options: [.init("A", value: "a"), .init("B", value: "b")], selected: "a", inline: true)
    let h = v.render()
    #expect(h.contains("class=\"radio-group radio-group--inline\""))
    #expect(h.contains("checked"))
}

@Test("WebUICheckboxGroup renders options")
func checkboxGroup() {
    let v = WebUICheckboxGroup(options: [.init("A", checked: true), .init("B", checked: false)])
    let h = v.render()
    #expect(h.contains("class=\"checkbox-group\""))
    #expect(h.contains("checkbox__box"))
    #expect(h.contains("checked"))
}
