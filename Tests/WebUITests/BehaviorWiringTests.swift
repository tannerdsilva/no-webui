import Testing
import WebUI
import WebUIDesignSystem

// slice S4's gate at the markup level: every component that advertises an
// interaction has to emit the typed attribute the engine reads, on the element
// that can honour it.
//
// these tests read emitted markup only — the same door `BehaviourVocabularyTests`
// reads — because that is what the client receives. a component that drops its
// attribute is a dead control, and a component that puts the attribute on the
// wrong element (the root instead of the panel, the panel instead of the list)
// is worse: it advertises an interaction it cannot deliver.
//
// the browser half is `designer/behaviour-probe.mjs`; this is the half that can
// fail before a browser is involved.

private func html(_ view: some View) -> String { view.markup.html }

@Suite("component behavior wiring")
struct BehaviorWiringTests {

	// MARK: - WebUIComboBox

	@Test("WebUIComboBox: the region filters, the panel dismisses and roves, options are one tab stop")
	func comboWiring() {
		let out = html(WebUIComboBox(placeholder: "pick", options: [.init("one"), .init("two")]))
		#expect(out.contains("class=\"combo\" data-filter-list"), "the filter region is the combo root: \(out)")
		#expect(out.contains("class=\"combo__panel\" data-dismiss data-roving"), "the panel is the dismiss layer and the roving group: \(out)")
		#expect(out.components(separatedBy: "tabindex=\"-1\"").count == 3, "both options carry tabindex -1: \(out)")
	}

	// MARK: - FilterList and its write-back

	@Test("FilterList: the bare marker stays bare, a source is the value")
	func filterListSource() {
		let bare = html(Element(.div) { Text("x") }.behavior(FilterList()))
		#expect(bare.contains(" data-filter-list"), "the contained form still emits the bare marker: \(bare)")
		#expect(!bare.contains("data-filter-list=\"\""), "an empty source is never spelled `=\"\"`: \(bare)")
		let sourced = html(Element(.div) { Text("x") }.behavior(FilterList(source: "#composer")))
		#expect(sourced.contains(" data-filter-list=\"#composer\""), "the source is the attribute's value: \(sourced)")
	}

	@Test("the filter write-back is three behaviors and three attributes")
	func filterWriteBack() {
		let insert = html(Element(.div) { Text("x") }.behavior(FilterInsert(target: "fx-composer")))
		#expect(insert.contains(" data-filter-insert=\"fx-composer\""), "the insert names its target: \(insert)")
		let template = html(Element(.div) { Text("x") }.behavior(FilterTemplate(text: "{value} ")))
		#expect(template.contains(" data-filter-template=\"{value} \""), "the template is the attribute's value, escaped but verbatim: \(template)")
		let clear = html(Element(.div) { Text("x") }.behavior(FilterClear()))
		#expect(clear.contains(" data-filter-clear"), "clear is the bare marker: \(clear)")
		#expect(!clear.contains("data-filter-clear=\"\""), "presence has no value: \(clear)")
	}

	// MARK: - WebUICommandPalette

	@Test("WebUICommandPalette: the dialog dismisses and filters, the results rove, items are one tab stop")
	func commandPaletteWiring() {
		let out = html(WebUICommandPalette(commands: [.init("Open", group: "File"), .init("Close", group: "File")]))
		#expect(out.contains("class=\"command-palette\" data-dismiss data-filter-list"), "the dialog carries both markers: \(out)")
		#expect(out.contains("class=\"command-palette__results\" data-roving"), "the results list is the roving group: \(out)")
		#expect(out.components(separatedBy: "class=\"command-palette__item\"").count - 1 == 2, "two items: \(out)")
		#expect(out.components(separatedBy: "tabindex=\"-1\"").count == 3, "both items carry tabindex -1: \(out)")
	}

	// MARK: - WebUIMessageScroller

	@Test("WebUIMessageScroller: the viewport follows and takes a key only when one is given")
	func messageScrollerWiring() {
		let plain = html(WebUIMessageScroller(content: [Text("line")]))
		#expect(plain.contains("data-follow=\"bottom\""), "the scroller follows by default: \(plain)")
		#expect(!plain.contains("data-scroll-key"), "no key, no per-key memory: \(plain)")
		let keyed = html(WebUIMessageScroller(scrollKey: "thread", content: [Text("line")]))
		#expect(keyed.contains("data-scroll-key=\"thread\""), "the key is emitted as given: \(keyed)")
	}

	// MARK: - WebUIToastStack / WebUIToast

	@Test("a toast is its own dismiss layer, and its close control stays")
	func toastWiring() {
		let out = html(WebUIToastStack { WebUIToast(tone: .info, message: "saved") })
		#expect(out.contains("class=\"toast toast--info\" data-dismiss role=\"alert\""), "the toast root is the layer: \(out)")
		#expect(out.contains("toast__close"), "the close control survives: \(out)")
		#expect(out.contains("class=\"toast-stack\""), "the stack is unchanged: \(out)")
	}

	// MARK: - WebUIDrawer

	@Test("WebUIDrawer: the panel is the layer and the close control is the affordance")
	func drawerWiring() {
		let out = html(WebUIDrawer(title: "Filters") { Text("body") })
		#expect(out.contains("class=\"drawer__panel\" data-dismiss"), "the panel is the dismiss layer: \(out)")
		#expect(out.contains("class=\"drawer__close\" data-dismiss"), "the close control is what the layer fires: \(out)")
		#expect(out.contains("role=\"dialog\""), "the overlay markup is untouched: \(out)")
	}

	// MARK: - WebUIKanban

	@Test("WebUIKanban: the board reorders into a hidden input derived from its id")
	func kanbanWiring() {
		let board = WebUIKanban(columns: [.init("Todo", cards: [.init("a")]), .init("Done", cards: [])], id: "tasks")
		let out = html(board)
		#expect(out.contains("class=\"kanban\" id=\"tasks\" data-reorder=\"tasks-order\""), "the derived input id: \(out)")
		#expect(out.contains("<input id=\"tasks-order\" type=\"hidden\" name=\"order\" value=\"\">"), "the hidden input is rendered: \(out)")
		#expect(out.contains("<div class=\"kanban__column\" id=\"tasks-order-col-0\">"), "every column is an id-bearing reorder item: \(out)")
		#expect(out.contains("<div class=\"kanban__column\" id=\"tasks-order-col-1\">"), "the second column is one too: \(out)")

		let explicit = html(WebUIKanban(columns: [.init("Todo", cards: [.init("a")])], id: "tasks", reorderInputID: "order-field"))
		#expect(explicit.contains("data-reorder=\"order-field\""), "an explicit input id wins: \(explicit)")
		#expect(explicit.contains("id=\"order-field\""), "the explicit input is rendered: \(explicit)")
		#expect(explicit.contains("id=\"order-field-col-0\""), "column ids follow the explicit input id: \(explicit)")

		let inert = html(WebUIKanban(columns: [.init("Todo", cards: [.init("a")])]))
		#expect(!inert.contains("data-reorder"), "no id and no input id is inert, not a dead promise: \(inert)")
		#expect(!inert.contains("type=\"hidden\""), "no hidden input either: \(inert)")
		#expect(!inert.contains("kanban__column\" id="), "and no column ids for a reorder that cannot happen: \(inert)")
	}

	// MARK: - WebUIInlineEdit

	@Test("WebUIInlineEdit: the root edits locally and the save control owns the handler")
	func inlineEditWiring() {
		let out = html(WebUIInlineEdit("title", state: .editing, id: "edit", onSave: { _ in [] }))
		#expect(out.contains("class=\"inline-edit inline-edit--editing\" id=\"edit\" data-inline-edit"), "the edit root carries the marker and its id: \(out)")
		#expect(!out.contains("id=\"edit\" data-component-id"), "the root is not the save control: \(out)")
		#expect(out.contains("inline-edit__check\" type=\"button\" id=\"edit-save\" data-component-id=\"edit-save\" data-event=\"click\""), "the check owns the save handler: \(out)")
		#expect(out.contains("inline-edit__pencil\" type=\"button\" id=\"edit-cancel\""), "the cancel is a plain button: \(out)")
	}

	// MARK: - WebUIScrollTop

	@Test("WebUIScrollTop: the affordance scrolls to the document top unless given a target")
	func scrollTopWiring() {
		let top = html(WebUIScrollTop())
		#expect(top.contains(" data-scroll-to>"), "an empty value is the document top: \(top)")
		#expect(!top.contains("data-scroll-to=\"\""), "the bare spelling is canonical: \(top)")
		let targeted = html(WebUIScrollTop(scrollToID: "comments"))
		#expect(targeted.contains("data-scroll-to=\"comments\""), "a target id is honoured: \(targeted)")
	}

	// MARK: - WebUIDisclosure

	@Test("WebUIDisclosure: a native details whose open state survives a patch")
	func disclosureWiring() {
		let out = html(WebUIDisclosure("More", open: true, id: "more") { Text("hidden") })
		#expect(out.hasPrefix("<details class=\"disclosure\" id=\"more\" data-preserve-open open>"), "the marker needs the id it memoises: \(out)")
		#expect(out.contains("<summary class=\"disclosure__summary\">More</summary>"), "the summary is the label: \(out)")
		#expect(out.contains("class=\"disclosure__body\""), "the body wrapper: \(out)")

		let closed = html(WebUIDisclosure("More") { Text("hidden") })
		#expect(!closed.contains("data-preserve-open"), "no id, no promise of preservation: \(closed)")
		#expect(!closed.contains(" open>"), "closed by default: \(closed)")
	}

	// MARK: - DraftSeed

	@Test("DraftSeed: a server seed serializes beside the identity it seeds")
	func draftSeedWiring() throws {
		#expect(DraftSeedAttribute.name == "data-draft-value", "the name is the engine's read key: \(DraftSeedAttribute.name)")
		let rendered = DraftSeed(text: "server-a").attributeText
		#expect(rendered == " data-draft-value=\"server-a\"", "the seed is the attribute's value: \(rendered)")

		let seeded = html(Input(id: "seed").behavior(DraftIdentity(key: "a")).behavior(DraftSeed(text: "server-a")))
		let start = try #require(seeded.range(of: "<input"), "no input tag in: \(seeded)")
		let end = try #require(seeded[start.upperBound...].firstIndex(of: ">"), "the input tag never closes: \(seeded)")
		let tag = seeded[start.lowerBound..<end]
		#expect(tag.contains("data-draft-id=\"a\""), "the identity is on the control: \(seeded)")
		#expect(tag.contains("data-draft-value=\"server-a\""), "the seed rides the same control: \(seeded)")
	}

	// MARK: - ReadingKeys

	@Test("ReadingKeys: a bare presence marker on the element that scrolls")
	func readingKeysWiring() {
		let attribute = ReadingKeys().attributeText
		#expect(attribute == " data-reading-keys", "a presence marker is the bare spelling: \(attribute)")
		#expect(ReadingKeysAttribute.name == "data-reading-keys", "the name is the dispatch key: \(ReadingKeysAttribute.name)")

		let out = html(Element(.div) { Text("lines") }.behavior(ReadingKeys()))
		#expect(out.contains("data-reading-keys"), "the marker reaches the element: \(out)")
		#expect(!out.contains("data-reading-keys=\""), "and never carries a value: \(out)")
	}
}
