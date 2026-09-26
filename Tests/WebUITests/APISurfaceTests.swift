import Testing
import Foundation
import WebUI
import WebUIDesignSystem
import WebUIAuth

// MARK: - Public API surface pins
//
// this suite is the enforcement arm of `Documentation/STABILITY.md`: every
// consumer-facing initializer is referenced here at compile time, and every
// component's render contract (class / role / escaping markers) is asserted.
// if a public API member changes shape or a component stops emitting its
// documented markup, this suite fails to compile or to pass — the "years of
// stability" promise is checked in-repo, not merely promised.
//
// (the `WebUIChart` product is pinned by its own `ChartTests`.)

private func rendered(_ view: some View) -> String {
	view.render()
}

// MARK: - Core primitives

@Test("primitive views pin their markup contracts")
func primitiveSurfacePins() {
	#expect(rendered(Text("<b>x</b>")) == "&lt;b&gt;x&lt;/b&gt;")
	#expect(rendered(Raw("<b>x</b>")) == "<b>x</b>")
	let div = rendered(Div(id: "d", class: "c") { Text("in") })
	#expect(div.contains("<div id=\"d\" class=\"c\">"))
	#expect(div.contains("in"))
	#expect(div.contains("</div>"))
	let span = rendered(Span(class: "s") { Text("x") })
	#expect(span.contains("<span class=\"s\">"))
	let button = rendered(Button("Go", id: "go", class: "btn", type: .button, disabled: true))
	#expect(button.contains("<button id=\"go\" class=\"btn\" type=\"button\" disabled>"))
	let input = rendered(Input(id: "i", name: "n", placeholder: "ph", type: .email, required: true))
	#expect(input.contains("id=\"i\""))
	#expect(input.contains("type=\"email\""))
	#expect(input.contains("required"))
	let textarea = rendered(TextArea(id: "t", name: "ta", placeholder: "p", rows: 4))
	#expect(textarea.contains("<textarea"))
	#expect(textarea.contains("rows=\"4\""))
	let img = rendered(Image(src: "/p.png", alt: "pic", loading: .lazy))
	#expect(img.contains("src=\"/p.png\""))
	#expect(img.contains("alt=\"pic\""))
	#expect(img.contains("loading=\"lazy\""))
	let form = rendered(Form(action: "/go", method: "post", csrfToken: "tok") { Text("x") })
	#expect(form.contains("action=\"/go\""))
	#expect(form.contains("method=\"post\""))
	#expect(form.contains("name=\"_csrf\""))
	let label = rendered(Label("Name", for: "nm"))
	#expect(label.contains("for=\"nm\""))
	let heading = rendered(Heading("Hi", level: .h2))
	#expect(heading.contains("<h2>"))
	let link = rendered(Link("Docs", href: "/docs", target: .blank))
	#expect(link.contains("href=\"/docs\""))
	let paragraph = rendered(Paragraph("text"))
	#expect(paragraph.contains("<p>text</p>"))
	#expect(rendered(EmptyView()) == "")
}

@Test("layout primitives pin their container classes")
func layoutSurfacePins() {
	let v = rendered(VStack(alignment: .center, spacing: 4) { Text("a") })
	#expect(v.contains("vstack"))
	#expect(v.contains("spacing-4"))
	#expect(v.contains("align-center"))
	let h = rendered(HStack(alignment: .top, spacing: 8) { Text("b") })
	#expect(h.contains("hstack"))
	let scroll = rendered(ScrollView { Text("c") })
	#expect(scroll.contains("scrollview"))
	let grid = rendered(Grid(columns: .autoFit(220), spacing: 12) { Text("g") })
	#expect(grid.contains("grid"))
	let spacer = rendered(Spacer(minSize: 0))
	#expect(spacer.contains("spacer"))
	let list = rendered(UnorderedList { Text("li") })
	#expect(list.contains("<ul"))
	let ordered = rendered(OrderedList { Text("li") })
	#expect(ordered.contains("<ol"))
	let section = rendered(Section(class: "sec") { Text("s") })
	#expect(section.contains("<section"))
	let nav = rendered(Navigation { Text("n") })
	#expect(nav.contains("<nav"))
	let header = rendered(Header { Text("h") })
	#expect(header.contains("<header"))
	let main = rendered(Main { Text("m") })
	#expect(main.contains("<main"))
	let footer = rendered(Footer { Text("f") })
	#expect(footer.contains("<footer"))
}

@Test("modifier surface pins token values and layout helpers")
func modifierSurfacePins() {
	let padded = rendered(Text("x").padding(SpaceToken.four))
	#expect(padded.contains("var(--space-4)"))
	let px = rendered(Text("x").padding(12))
	#expect(px.contains("padding: 12px"))
	let margin = rendered(Text("x").margin(8))
	#expect(margin.contains("margin: 8px"))
	let family = rendered(Text("x").fontFamily("var(--font-mono)"))
	#expect(family.contains("font-family: var(--font-mono)"))
	let minWidth = rendered(Text("x").minWidth("0"))
	#expect(minWidth.contains("min-width: 0"))
	let height = rendered(Text("x").height("100vh"))
	#expect(height.contains("height: 100vh"))
	let styled = rendered(
		Text("x")
			.cornerRadius("var(--radius-xl)")
			.backgroundColor("var(--color-bg-raised)")
			.foregroundColor(ColorToken.text)
			.maxWidth("24rem")
			.width("100%")
	)
	#expect(styled.contains("border-radius: var(--radius-xl)"))
	#expect(styled.contains("background-color: var(--color-bg-raised)"))
	#expect(styled.contains("color: var(--color-text)"))
	let filled = rendered(Text("x").fill())
	#expect(filled.contains("flex: 1 1 0%"))
	let stretched = rendered(Text("x").stretch())
	#expect(stretched.contains("align-self: stretch"))
	let hidden = rendered(Text("x").showIf(false))
	#expect(hidden.contains("display: none"))
	let shown = rendered(Text("x").showIf(true))
	#expect(!shown.contains("display: none"))
}

@Test("every event modifier renders its routed attribute")
func eventModifierSurfacePins() {
	// controlAttributes is the routing seam; the modifiers below must compile
	// against the documented shape even where their render path is inert
	// outside a live session.
	let handler: EventHandler = { _ in [] }
	_ = Text("x").onClick(perform: handler)
	_ = Text("x").onSubmit(perform: handler)
	_ = Text("x").onInput(perform: handler)
	_ = Text("x").onChange(perform: handler)
	_ = Text("x").onFocus(perform: handler)
	_ = Text("x").onBlur(perform: handler)
	_ = Text("x").onKeyDown(perform: handler)
	_ = Text("x").onKeyUp(perform: handler)
	_ = Text("x").onKeyPress(perform: handler)
	_ = Text("x").onMouseDown(perform: handler)
	_ = Text("x").onMouseUp(perform: handler)
	_ = Text("x").onMouseOver(perform: handler)
	_ = Text("x").onMouseOut(perform: handler)
	_ = Text("x").onFocusIn(perform: handler)
	_ = Text("x").onFocusOut(perform: handler)
	_ = Text("x").onOptimisticClick(predict: { [] }, perform: handler)
	let attrs = controlAttributes(id: "evt-click", event: .click, handler: handler)
	let injected = injectAttributes(into: Text("x").render(), attrs)
	#expect(injected.contains("data-component-id=\"evt-click\""))
	#expect(injected.contains("data-event=\"click\""))
}

// MARK: - Design system components

@Test("every design-system component pins its class/role contract")
func componentSurfacePins() {
	let button = rendered(WebUIButton("Save", variant: .primary, size: .md, disabled: false, id: "b1", fullWidth: true, loading: true))
	#expect(button.contains("button button--primary button--md button--full button--loading"))
	#expect(button.contains("aria-busy=\"true\""))
	#expect(button.contains("button__label"))

	let input = rendered(WebUIInput(placeholder: "p", state: .error, disabled: false, id: "i1", type: .password, label: "Pass", helpText: "hint"))
	#expect(input.contains("input--error"))
	#expect(input.contains("input__label"))
	#expect(input.contains("input__help input__help--error"))

	let badge = rendered(WebUIBadge("New", variant: .success, size: .sm, dot: true))
	#expect(badge.contains("badge badge--success badge--sm badge--dot"))

	let avatar = rendered(WebUIAvatar(initials: "JD", size: .md, src: nil, status: "online"))
	#expect(avatar.contains("avatar avatar--md"))
	#expect(avatar.contains("avatar__status"))
	#expect(avatar.contains("data-status=\"online\""))

	let card = rendered(WebUICard(variant: .elevated, id: "c1") { Text("in") })
	#expect(card.contains("card card--elevated"))
	#expect(card.contains("card__body"))

	let tabs = rendered(WebUITabs(tabs: [TabItem(id: "a", label: "A"), TabItem(id: "b", label: "B")], activeTab: "a"))
	#expect(tabs.contains("role=\"tablist\""))
	#expect(tabs.contains("aria-selected=\"true\""))

	// wired tabs: each tab carries a derived routing id (stable control id +
	// DOM id) so a server handler can switch on `me`/tabID.
	let tabsWired = rendered(WebUITabs(
		tabs: [TabItem(id: "a", label: "A")], activeTab: "a", id: "t1",
		onSelect: { _, _ in [] }
	))
	#expect(tabsWired.contains("id=\"t1-a\""))
	#expect(tabsWired.contains("data-component-id=\"t1-a\""))
	#expect(tabsWired.contains("data-event=\"click\""))

	let alert = rendered(WebUIAlert(variant: .danger, title: "Error", message: "boom", dismissible: true))
	#expect(alert.contains("alert alert--danger"))
	#expect(alert.contains("role=\"alert\""))

	let progress = rendered(WebUIProgress(value: 0.5, variant: .warning, showLabel: true, size: .md))
	#expect(progress.contains("progress progress--warning"))
	#expect(progress.contains("aria-valuenow"))

	let skeleton = rendered(WebUISkeleton(variant: .card, count: 2))
	#expect(skeleton.contains("skeleton skeleton--card"))
	#expect(skeleton.contains("aria-hidden=\"true\""))

	let toast = rendered(WebUIToast(variant: .info, message: "saved", id: "t1", dismissible: false))
	#expect(toast.contains("toast toast--info"))
	#expect(toast.contains("toast__message"))

	let modal = rendered(WebUIModal(title: "Confirm", id: "m1") { Text("sure?") })
	#expect(modal.contains("role=\"dialog\""))
	#expect(modal.contains("aria-modal=\"true\""))

	let spinner = rendered(WebUISpinner(size: .sm))
	#expect(spinner.contains("spinner"))

	let icon = rendered(WebUIIcon(.bot, size: .small, title: "bot"))
	#expect(icon.contains("role=\"img\""))
	#expect(icon.contains("aria-label=\"bot\""))

	let customIcon = rendered(WebUIIconCustom(name: "x", body: "<path d=\"M0 0h1\"/>"))
	#expect(customIcon.contains("data-icon=\"x\""))

	let emptyState = rendered(WebUIEmptyState(icon: .inbox, title: "Empty", message: "Nothing", action: nil))
	#expect(emptyState.contains("empty-state"))
	#expect(emptyState.contains("Empty"))

	let chip = rendered(WebUIChip("tag", variant: .neutral, removable: true))
	#expect(chip.contains("chip"))
// p1 reachable-API sweep: components whose css shipped before their api did.
	let separator = rendered(WebUISeparator("or"))
	#expect(separator.contains("divider-divider"))
	#expect(separator.contains("divider-divider__label"))
	let verticalSeparator = rendered(WebUISeparator(orientation: .vertical))
	#expect(verticalSeparator.contains("divider divider--vertical"))
	#expect(verticalSeparator.contains("aria-orientation=\"vertical\""))
	let glyphSeparator = rendered(WebUISeparator(icon: .chevronDown))
	#expect(glyphSeparator.contains("divider divider--icon"))
	#expect(glyphSeparator.contains("divider__label"))
	let strongSeparator = rendered(WebUISeparator(strong: true))
	#expect(strongSeparator.contains("divider divider--strong"))
	let escapedSeparator = rendered(WebUISeparator("<b>or</b>"))
	#expect(escapedSeparator.contains("&lt;b&gt;or&lt;/b&gt;"))

	let kbd = rendered(WebUIKbd("K"))
	#expect(kbd.contains("<kbd class=\"kbd\">K</kbd>"))
	let combo = rendered(WebUIKbd(["Ctrl", "K"]))
	#expect(combo.contains("kbd-combo"))
	#expect(combo.contains("<kbd class=\"kbd\">Ctrl</kbd><kbd class=\"kbd\">K</kbd>"))
	let sizedKbd = rendered(WebUIKbd(["Ctrl", "K"], size: .small, separator: "+"))
	#expect(sizedKbd.contains("kbd kbd--sm"))
	#expect(sizedKbd.contains("kbd-sep"))
	let largeKbd = rendered(WebUIKbd("Esc", size: .large))
	#expect(largeKbd.contains("kbd--lg"))

	let aspect = rendered(WebUIAspectRatio(.square, label: "1 / 1"))
	#expect(aspect.contains("aspect aspect--1-1"))
	#expect(aspect.contains("aspect__label"))
	#expect(rendered(WebUIAspectRatio(.wide)).contains("aspect--21-9"))
	#expect(rendered(WebUIAspectRatio(.standard)).contains("aspect--16-9"))
	#expect(rendered(WebUIAspectRatio(.photo)).contains("aspect--4-3"))
	#expect(rendered(WebUIAspectRatio(.portrait)).contains("aspect--3x4"))
	#expect(rendered(WebUIAspectRatio(.tall)).contains("aspect--9x16"))

	let ring = rendered(WebUICircularProgress(value: 0.25, label: "25", sublabel: "%", ariaLabel: "Used"))
	#expect(ring.contains("role=\"progressbar\""))
	#expect(ring.contains("aria-valuenow=\"25\""))
	#expect(ring.contains("stroke-dashoffset=\"75.0\""))
	#expect(ring.contains("ring__track"))
	#expect(ring.contains("ring__fill"))
	#expect(ring.contains("ring__label"))
	#expect(ring.contains("ring__label-sub"))
	let smallRing = rendered(WebUICircularProgress(value: 0.5, tone: .success, size: .small))
	#expect(smallRing.contains("ring ring--sm ring--success"))
	#expect(rendered(WebUICircularProgress(value: 0.5, tone: .warning, size: .large)).contains("ring--lg"))
	#expect(rendered(WebUICircularProgress(value: 0.5, tone: .danger)).contains("ring--danger"))
	let busyRing = rendered(WebUICircularProgress(value: 0, indeterminate: true))
	#expect(busyRing.contains("ring--indeterminate"))
	#expect(!busyRing.contains("aria-valuenow"))
	let clampedRing = rendered(WebUICircularProgress(value: 5))
	#expect(clampedRing.contains("aria-valuenow=\"100\""))

	let group = rendered(WebUIInputGroup(placeholder: "0.00", prefix: "$", icon: .dollarSign, suffix: "USD", type: .number, name: "amt"))
	#expect(group.contains("input input--with-affix"))
	#expect(group.contains("input__affix input__affix--left"))
	#expect(group.contains("input__prefix"))
	#expect(group.contains("input__suffix"))
	#expect(group.contains("input__el"))
	#expect(group.contains("name=\"amt\""))
	let errorGroup = rendered(WebUIInputGroup(placeholder: "x", suffix: "bad", state: .error))
	#expect(errorGroup.contains("input--error"))
	#expect(errorGroup.contains("input__suffix input__suffix--error"))
	#expect(errorGroup.contains("aria-invalid=\"true\""))

	let banner = rendered(WebUIBanner(variant: .warning, title: "Heads up", message: "Watch out", dismissible: true, id: "bn"))
	#expect(banner.contains("banner banner--warning"))
	#expect(banner.contains("role=\"status\""))
	#expect(banner.contains("banner__icon"))
	#expect(banner.contains("banner__title"))
	#expect(banner.contains("banner__text"))
	#expect(banner.contains("banner__close"))
	#expect(banner.contains("data-dismiss"))
	#expect(rendered(WebUIBanner(variant: .success, message: "x")).contains("banner--success"))
	#expect(rendered(WebUIBanner(variant: .danger, message: "x")).contains("banner--error"))
	#expect(rendered(WebUIBanner(variant: .info, message: "x")).contains("banner--info"))

	let feed = rendered(WebUIActivityFeed([
		WebUIActivityFeed.Group("Today", items: [
			WebUIActivityFeed.Item(icon: .checkCircle, text: "Shipped", time: "2h"),
		]),
	]))
	#expect(feed.contains("activity"))
	#expect(feed.contains("activity__group"))
	#expect(feed.contains("activity__item"))
	#expect(feed.contains("activity__icon"))
	#expect(feed.contains("activity__text"))
	#expect(feed.contains("activity__time"))
	let unsafeFeed = rendered(WebUIActivityFeed([
		WebUIActivityFeed.Group("<b>today</b>", items: [
			WebUIActivityFeed.Item(icon: .bell, text: "<script>x</script>", time: "<1m"),
		]),
	]))
	#expect(unsafeFeed.contains("&lt;script&gt;x&lt;/script&gt;"))
	#expect(unsafeFeed.contains("&lt;1m"))
// p2 chat set: the sheet's chat family plus the scroller/marker/attachment.
	let scroller = rendered(WebUIMessageScroller(height: "18rem", id: "sc", ariaLabel: "Thread") {
		Text("first")
		Text("second")
	})
	#expect(scroller.contains("scroll-area scroll-area--reverse scroll-area--fade-y"))
	#expect(scroller.contains("role=\"log\""))
	#expect(scroller.contains("aria-live=\"polite\""))
	#expect(scroller.contains("tabindex=\"0\""))
	#expect(scroller.contains("height: 18rem; max-height: 18rem"))
	// bottom-anchored layout: children emit in reverse dom order
	let firstAt = scroller.range(of: "first")!
	let secondAt = scroller.range(of: "second")!
	#expect(secondAt.lowerBound < firstAt.lowerBound)
	#expect(!rendered(WebUIMessageScroller(fade: false) { Text("x") }).contains("scroll-area--fade-y"))

	let marker = rendered(WebUIMarker("Today"))
	#expect(marker.contains("class=\"marker\""))
	#expect(marker.contains("role=\"separator\""))
	#expect(marker.contains("marker__rule"))
	#expect(marker.contains("marker__label"))
	#expect(rendered(WebUIMarker("Pinned", icon: .clock, sticky: true)).contains("marker--sticky"))
	#expect(rendered(WebUIMarker("Pinned", icon: .clock)).contains("marker__glyph"))
	#expect(!rendered(WebUIMarker("Bare", spread: false)).contains("marker__rule"))
	#expect(rendered(WebUIMarker("<b>x</b>")).contains("&lt;b&gt;x&lt;/b&gt;"))

	let attachment = rendered(WebUIAttachment(name: "notes.md", meta: "12 KB", removable: true, id: "att"))
	#expect(attachment.contains("class=\"attachment\""))
	#expect(attachment.contains("attachment__icon"))
	#expect(attachment.contains("attachment__name"))
	#expect(attachment.contains("attachment__meta"))
	#expect(attachment.contains("attachment__remove"))
	#expect(attachment.contains("data-dismiss"))
	#expect(attachment.contains("id=\"att\""))
	#expect(rendered(WebUIAttachment(name: "x", meta: "y", state: .uploading)).contains("attachment--uploading"))
	#expect(rendered(WebUIAttachment(name: "x", state: .error)).contains("attachment--error"))
	#expect(rendered(WebUIAttachment(name: "<script>x</script>")).contains("&lt;script&gt;"))

	let bubble = rendered(WebUIChatBubble("hi there", side: .sent, time: "09:41", receipt: .read))
	#expect(bubble.contains("chat__bubble chat__bubble--sent"))
	#expect(bubble.contains("chat__time"))
	#expect(bubble.contains("chat__receipt chat__receipt--read"))
	#expect(bubble.contains("aria-label=\"Read\""))
	#expect(rendered(WebUIChatBubble("x", side: .received)).contains("chat__bubble--received"))
	let reacted = rendered(WebUIChatBubble("x", reactions: [WebUIChatBubble.Reaction(label: "up", count: 2, active: true)]))
	#expect(reacted.contains("chat__reactions"))
	#expect(reacted.contains("chat__reaction chat__reaction--active"))
	#expect(rendered(WebUIChatBubble("line1\nline2")).contains("line1<br>line2"))
	#expect(rendered(WebUIChatBubble("<b>x</b>")).contains("&lt;b&gt;x&lt;/b&gt;"))
	// a received bubble never shows an outgoing receipt
	#expect(!rendered(WebUIChatBubble("x", side: .received, receipt: .read)).contains("chat__receipt"))

	let thread = rendered(WebUIMessage(name: "Dana", text: "green", time: "09:12"))
	#expect(thread.contains("class=\"chat__thread\""))
	#expect(thread.contains("chat__meta"))
	#expect(thread.contains("class=\"chat__bubble\""))
	let ownThread = rendered(WebUIMessage(name: "You", text: "ok", own: true))
	#expect(ownThread.contains("chat__thread chat__thread--own"))
	#expect(ownThread.contains("chat__bubble chat__bubble--own"))
// p3 composition primitives: card anatomy, field, item, toggle group, scroll top.
	let tap: EventHandler = { _ in [] }
	let anatomy = rendered(WebUICard(
		variant: .outlined,
		eyebrow: "eyebrow",
		title: "title",
		description: "desc",
		headerIcon: .activity,
		media: .image,
		mediaBadge: "badge",
		text: "text",
		footerMeta: "meta",
		actions: { WebUIButton("Go", variant: .primary) }
	) {
		Text("body")
	})
	#expect(anatomy.contains("card card--outlined"))
	#expect(anatomy.contains("card__media"))
	#expect(anatomy.contains("card__media-badge"))
	#expect(anatomy.contains("card__header"))
	#expect(anatomy.contains("card__eyebrow"))
	#expect(anatomy.contains("card__title"))
	#expect(anatomy.contains("card__icon"))
	#expect(anatomy.contains("card__desc"))
	#expect(anatomy.contains("card__text"))
	#expect(anatomy.contains("card__footer"))
	#expect(anatomy.contains("card__meta"))
	#expect(anatomy.contains("card__actions"))
	// a bare card keeps the old markup: no anatomy slots, just card + body
	let bare = rendered(WebUICard { Text("x") })
	#expect(bare.contains("card card--elevated"))
	#expect(bare.contains("card__body"))
	#expect(!bare.contains("card__header"))
	#expect(!bare.contains("card__actions"))
	#expect(rendered(WebUICard(variant: .horizontal) { Text("x") }).contains("card card--horizontal"))
	#expect(rendered(WebUICard(variant: .hover) { Text("x") }).contains("card--hover"))
	#expect(rendered(WebUICard(variant: .compact) { Text("x") }).contains("card--compact"))
	#expect(rendered(WebUICard(variant: .disabled) { Text("x") }).contains("card--disabled"))

	let field = rendered(WebUIField(
		label: "Name",
		controlID: "nm",
		required: true,
		note: "taken",
		noteKind: .error,
		count: "3 / 20",
		helper: "Shown on your profile"
	) {
		WebUIInput(placeholder: "Name", id: "nm")
	})
	#expect(field.contains("class=\"field\""))
	#expect(field.contains("field__row"))
	#expect(field.contains("field__label field__label--required"))
	#expect(field.contains("for=\"nm\""))
	#expect(field.contains("field__hint field__hint--error"))
	#expect(field.contains("field__count"))
	#expect(field.contains("field__helper"))
	#expect(rendered(WebUIField(label: "x", helper: "bad", helperIsError: true) { Text("y") }).contains("field__helper field__helper--error"))
	#expect(rendered(WebUIField(label: "x", note: "ok", noteKind: .success) { Text("y") }).contains("field__hint--success"))
	#expect(rendered(WebUIField(label: "<b>x</b>") { Text("y") }).contains("&lt;b&gt;x&lt;/b&gt;"))

	let row = rendered(WebUIItem(
		title: "web-01",
		subtitle: "us-east-1",
		meta: "42 ms",
		icon: .server,
		selected: true,
		id: "row-1"
	) {
		WebUIButton("Open", variant: .ghost, size: .sm)
	})
	#expect(row.contains("list__item list__item--selected"))
	#expect(row.contains("list__icon"))
	#expect(row.contains("list__title"))
	#expect(row.contains("list__sub"))
	#expect(row.contains("list__meta"))
	#expect(row.contains("list__actions"))
	#expect(row.contains("list__action"))
	#expect(row.contains("id=\"row-1\""))
	#expect(!rendered(WebUIItem(title: "bare")).contains("list__actions"))

	let chips = rendered(WebUIToggleGroup(
		options: [
			WebUIToggleGroup.Option("all", "All", selected: true),
			WebUIToggleGroup.Option("web", "Web"),
		],
		id: "filters",
		onToggle: tap
	))
	#expect(chips.contains("chip chip--filter chip--filter-active"))
	#expect(chips.contains("chip chip--filter\""))
	#expect(chips.contains("aria-pressed=\"true\""))
	#expect(chips.contains("id=\"filters-opt-0\""))
	#expect(chips.contains("data-component-id=\"filters\""))
	#expect(chips.contains("role=\"group\""))
	#expect(chips.contains("flex-wrap: wrap"))

	let top = rendered(WebUIScrollTop(progress: 0.4, id: "to-top", onTap: tap))
	#expect(top.contains("scroll-top scroll-top--ring"))
	#expect(top.contains("scroll-top__ring"))
	#expect(top.contains("ring__track"))
	#expect(top.contains("ring__fill"))
	#expect(top.contains("stroke-dashoffset=\"60.0\""))
	#expect(top.contains("scroll-top__icon"))
	#expect(top.contains("aria-label=\"Back to top\""))
	#expect(top.contains("data-component-id=\"to-top\""))
	let plainTop = rendered(WebUIScrollTop())
	#expect(!plainTop.contains("scroll-top--ring"))
	#expect(plainTop.contains("scroll-top__icon"))
// p3b nav chrome: navbar search + hamburger, menu sections and item states.
	let nav = rendered(WebUINavbar(
		brand: "Acme",
		links: [WebUINavbar.Link("A", href: "#")],
		search: WebUINavbar.Search(placeholder: "Find", shortcut: "Ctrl K", id: "ns"),
		mobileMenu: true
	) {
		WebUIButton("Go")
	})
	#expect(nav.contains("navbar__search"))
	#expect(nav.contains("<kbd>Ctrl K</kbd>"))
	#expect(nav.contains("id=\"ns\""))
	#expect(nav.contains("navbar__hamburger"))
	#expect(nav.contains("aria-label=\"Menu\""))
	#expect(!rendered(WebUINavbar { Text("x") }).contains("navbar__hamburger"))
	#expect(!rendered(WebUINavbar { Text("x") }).contains("navbar__search"))
	#expect(rendered(WebUINavbar(search: WebUINavbar.Search(id: "s")) { Text("x") }).contains("role=\"search\""))

	let menu = rendered(WebUIMenu(items: [
		WebUIMenu.Item("One", active: true),
		WebUIMenu.Item("Two", hint: "Ctrl 2", submenu: true, dividerBefore: true),
		WebUIMenu.Item("Three", avatar: "DA", section: "Group"),
		WebUIMenu.Item("Four", danger: true),
	], header: "Heading", search: "Find", panel: true))
	#expect(menu.contains("menu menu__panel"))
	#expect(menu.contains("menu__header"))
	#expect(menu.contains("menu__search"))
	#expect(menu.contains("menu__section"))
	#expect(menu.contains("menu__divider"))
	#expect(menu.contains("menu__item--active"))
	#expect(menu.contains("menu__item--has-sub"))
	#expect(menu.contains("menu__item--danger"))
	#expect(menu.contains("menu__avatar"))
	#expect(menu.contains("menu__hint"))
	let plainMenu = rendered(WebUIMenu(items: [WebUIMenu.Item("Only")]))
	#expect(!plainMenu.contains("menu__panel"))
	#expect(!plainMenu.contains("menu__header"))
	#expect(plainMenu.contains("menu__item"))
}

@Test("composite components pin their surface")
func compositeSurfacePins() {
	let table = rendered(WebUITable(headers: ["Name", "P95"], rows: [[Text("a"), Text("2")]], id: "tbl"))
	#expect(table.contains("table"))
	#expect(table.contains("th"))
	#expect(table.contains("<td"))

	let tree = rendered(WebUITree(nodes: [WebUITree.Node(id: "n1", label: "Node", icon: .fileText)], id: "tree"))
	#expect(tree.contains("role=\"tree\""))
	#expect(tree.contains("n1"))

	let listView = rendered(WebUIListView(items: [WebUIListItem(id: "l1", title: "Title", subtitle: "sub", icon: .users)], selectedID: "l1", id: "list"))
	#expect(listView.contains("list"))

	let segmented = rendered(WebUISegmentedControl(items: [WebUISegmentedItem(id: "s1", label: "One", count: 3)], selectedID: "s1", id: "seg"))
	#expect(segmented.contains("segmented"))

	let sidebar = rendered(WebUISidebar(items: [WebUISidebarItem(id: "home", label: "Home", icon: .settings, href: "/")], activeID: "home", id: "rail", style: .rail))
	#expect(sidebar.contains("sidebar"))
	#expect(sidebar.contains("href=\"/\""))

	let panel = rendered(WebUIPanel(title: "Chat", subtitle: "2", edge: .leading) { Text("x") })
	#expect(panel.contains("panel"))
	#expect(panel.contains("panel__body"))

	let search = rendered(WebUISearchField(placeholder: "Filter…", id: "search"))
	#expect(search.contains("search-field"))

	let composer = rendered(WebUIComposer(placeholder: "Message…", inputID: "in-0", id: "bar", hint: "Enter to send"))
	#expect(composer.contains("composer"))
	#expect(composer.contains("name=\"message\""))

	let select = rendered(WebUISelect(id: "sel", options: [WebUISelect.Option(value: "a", label: "A")], value: "a", onChange: nil))
	#expect(select.contains("<select"))
	#expect(select.contains("<select id=\"sel\""))

	let descList = rendered(WebUIDescriptionList([("Key", "Value")]))
	#expect(descList.contains("list--desc"))

	let stat = rendered(WebUIStat(label: "p95", value: "120ms", trend: "-8%", trendDirection: .down))
	#expect(stat.contains("stat"))

	let pagination = rendered(WebUIPagination(page: 2, pages: 5, id: "pg"))
	#expect(pagination.contains("pagination"))

	let timeline = rendered(WebUITimeline(events: [WebUITimeline.Event(time: "now", title: "Done", status: .completed)], orientation: .vertical))
	#expect(timeline.contains("timeline"))

	let breadcrumb = rendered(WebUIBreadcrumb(items: [WebUIBreadcrumb.Item("Home", href: "/")], current: WebUIBreadcrumb.Item("Pets")))
	#expect(breadcrumb.contains("breadcrumb"))

	let tooltip = rendered(WebUITooltip("hint", position: .top) { Text("label") })
	#expect(tooltip.contains("tooltip"))

	let turnReasoning = rendered(WebUIReasoningBlock("think"))
	#expect(turnReasoning.contains("turn-reasoning"))
	let turnTool = rendered(WebUIToolStep(name: "read_file", arguments: "p:t", result: "ok", isError: false, meta: " · 1s"))
	#expect(turnTool.contains("turn-tool"))
	#expect(turnTool.contains("turn-tool__name"))
	let turnSummary = rendered(WebUITurnSummary("1 tool"))
	#expect(turnSummary.contains("turn-summary"))
}

// MARK: - Document assembly

@Test("the webuiauth public surface compiles against its documented shapes")
func authSurfacePins() throws {
	// signature carets: deleting or renaming any member below fails the build.
	let record = PasswordRecord(
		salt: try PasswordVerifier.makeSalt(),
		hash: [UInt8]("pw".utf8),
		parameters: .interactive
	)
	_ = try PasswordRecord(encoded: record.encodedString())
	let store: any AuthSessionStore = InMemoryAuthSessionStore()
	let throttle = LoginThrottle(windowSeconds: 60, maxAttempts: 5)
	let tokenStore = SingleUseTokenStore()
	let semaphore = AsyncSemaphore(permits: 1)
	let identity = Identity(id: "u", roles: [Role.member])
	let session = AuthenticatedSession(
		id: [1], tokenHash: [2], identityID: "u", csrfSeed: [3],
		createdAt: Date(), expiresAt: Date(), lastSeenAt: Date()
	)
	let context = AuthContext(session: session, identity: identity)
	_ = context
	_ = session.isExpired()

	// behavioral carets on the security-critical members.
	let csrf = try CSRFProtection.generateSecret()
	let signed = try CSRFProtection.token(for: "login", secret: csrf)
	#expect(CSRFProtection.validate(signed, for: "login", secret: csrf))
	#expect(!CSRFProtection.validate(signed, for: "logout", secret: csrf))

	let token = try SessionToken.generate()
	#expect(try SessionToken.hash(token).count == 32)

	let cookie = try HTTPCookie(
		name: "a", value: "b",
		attributes: .init(maxAge: 60, path: "/", httpOnly: true, sameSite: .lax)
	).setCookieHeaderValue()
	#expect(cookie.hasPrefix("a=b"))
	#expect(CookieParser.requestCookies("a=b; c=d") == ["a": "b", "c": "d"])

	#expect(throttle.record("ip:1"))
	_ = tokenStore
	_ = semaphore
	_ = store
}

@Test("document assembly pins csp nonce, runtime config, and theming")
func documentSurfacePins() {
	let doc = WebUIDocument(
		title: "T",
		body: Text("hi").render(),
		runtimeConfig: RuntimeConfig(renderToken: "rt-1")
	).render()
	#expect(doc.contains("<title>T</title>"))
	#expect(doc.contains("<meta name=\"webui-config\""))
	#expect(doc.contains("renderToken"))

	let themed = WebUIDocument(body: Text("x").render(), theme: WebUITheme(scheme: .dark)).render()
	#expect(themed.contains("color-scheme: dark"))
}

// MARK: - Runtime config surface

@Test("runtime config accepts the full documented shape")
func runtimeConfigSurfacePins() {
	let config = RuntimeConfig(
		wsUrl: "/ws",
		wsReconnect: true,
		wsMaxReconnectDelayMs: 8000,
		wsPingIntervalMs: 30000,
		wsPongTimeoutMs: 10000,
		maxQueueSize: 100,
		debounceInputMs: 200,
		debounceMaxWaitMs: 1000,
		optimisticSettleMs: 5000,
		logLevel: "warn",
		renderToken: "tok"
	)
	_ = config
}
