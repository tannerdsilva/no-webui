import Testing
import Foundation
import WebUICore

// the 25 register rows, pinned one test each.
//
// §24 of the behavior-layer journal is the naming authority: a row is a Swift
// type whose `AttributeRepresentable.name` equals the register's attribute
// exactly, a value whose serialization the register fixes, and an emission
// through the one `.behavior(_:)` door. `Documentation/BEHAVIOUR.md` is the
// contract the engine reads, so every name here must also appear there.
//
// prove-it-fails: changing a behavior's `name`, its value spelling, or the
// empty-value rule in `AttributeRepresentable.attributeText` turns the matching
// test red naming the attribute.

private func rendered(_ behavior: some Behavior) -> String {
	Element(.div) { Text("x") }.behavior(behavior).markup.html
}

@Suite("behavior primitives")
struct BehaviorPrimitivesTests {

	// MARK: - 1. scroll follow

	@Test("ScrollFollow serializes data-follow bottom/off")
	func scrollFollow() {
		#expect(ScrollFollowAttribute.name == "data-follow")
		#expect(ScrollFollow().attribute().value == "bottom")
		#expect(ScrollFollow(mode: .bottom).attribute().value == "bottom")
		#expect(ScrollFollow(mode: .off).attribute().value == "off")
		#expect(rendered(ScrollFollow()).contains(" data-follow=\"bottom\""))
		#expect(rendered(ScrollFollow(mode: .off)).contains(" data-follow=\"off\""))
	}

	// MARK: - 2. per-key scroll

	@Test("ScrollKey serializes data-scroll-key")
	func scrollKey() {
		#expect(ScrollKeyAttribute.name == "data-scroll-key")
		#expect(ScrollKey(key: "thread").attribute().value == "thread")
		#expect(rendered(ScrollKey(key: "thread")).contains(" data-scroll-key=\"thread\""))
	}

	// MARK: - 3. scroll to

	@Test("ScrollTo serializes data-scroll-to")
	func scrollTo() {
		#expect(ScrollToAttribute.name == "data-scroll-to")
		#expect(ScrollTo(id: "section-4").attribute().value == "section-4")
		#expect(rendered(ScrollTo(id: "section-4")).contains(" data-scroll-to=\"section-4\""))
	}

	// MARK: - 4. draft identity

	@Test("DraftIdentity serializes data-draft-id")
	func draftIdentity() {
		#expect(DraftIdentityAttribute.name == "data-draft-id")
		#expect(DraftIdentity(key: "composer").attribute().value == "composer")
		#expect(rendered(DraftIdentity(key: "composer")).contains(" data-draft-id=\"composer\""))
	}

	// MARK: - 5. focus return

	@Test("FocusReturn serializes data-focus-return, empty meaning the element itself")
	func focusReturn() {
		#expect(FocusReturnAttribute.name == "data-focus-return")
		#expect(FocusReturn(id: "search").attribute().value == "search")
		#expect(rendered(FocusReturn(id: "search")).contains(" data-focus-return=\"search\""))
		// empty is the element itself, so the attribute is still present — bare.
		#expect(FocusReturn().attribute().value == "")
		#expect(rendered(FocusReturn()).contains(" data-focus-return"))
		#expect(!rendered(FocusReturn()).contains("data-focus-return=\"\""))
	}

	// MARK: - 6. dismiss stack

	@Test("DismissStack serializes data-dismiss, empty layer as the bare marker")
	func dismissStack() {
		#expect(DismissStackAttribute.name == "data-dismiss")
		#expect(DismissStack(layer: "menu").attribute().value == "menu")
		#expect(rendered(DismissStack(layer: "menu")).contains(" data-dismiss=\"menu\""))
		#expect(DismissStack().attribute().value == "")
		#expect(rendered(DismissStack()).contains(" data-dismiss"))
		#expect(!rendered(DismissStack()).contains("data-dismiss=\"\""))
	}

	@Test("DrawerToggle serializes the drawer id")
	func drawerToggle() {
		#expect(DrawerToggleAttribute.name == "data-drawer-toggle")
		#expect(DrawerToggle(drawerID: "d1").attribute().value == "d1")
		#expect(rendered(DrawerToggle(drawerID: "d1")).contains(" data-drawer-toggle=\"d1\""))
	}

	// MARK: - 7. reorder

	@Test("Reorder serializes data-reorder")
	func reorder() {
		#expect(ReorderAttribute.name == "data-reorder")
		#expect(Reorder(inputID: "order").attribute().value == "order")
		#expect(rendered(Reorder(inputID: "order")).contains(" data-reorder=\"order\""))
	}

	// MARK: - 8. clipboard

	@Test("Clipboard serializes data-copy, empty meaning the element's own text")
	func clipboard() {
		#expect(ClipboardAttribute.name == "data-copy")
		#expect(Clipboard(text: "swift").attribute().value == "swift")
		#expect(rendered(Clipboard(text: "swift")).contains(" data-copy=\"swift\""))
		#expect(Clipboard().attribute().value == "")
		#expect(rendered(Clipboard()).contains(" data-copy"))
		#expect(!rendered(Clipboard()).contains("data-copy=\"\""))
	}

	// MARK: - 9. table enhancement

	@Test("TableEnhance serializes data-table-enhance sort/filter/sort filter")
	func tableEnhance() {
		#expect(TableEnhanceAttribute.name == "data-table-enhance")
		#expect(TableEnhance(mode: .sort).attribute().value == "sort")
		#expect(TableEnhance(mode: .filter).attribute().value == "filter")
		#expect(TableEnhance(mode: .sortAndFilter).attribute().value == "sort filter")
		#expect(rendered(TableEnhance(mode: .sort)).contains(" data-table-enhance=\"sort\""))
		#expect(rendered(TableEnhance(mode: .filter)).contains(" data-table-enhance=\"filter\""))
		#expect(rendered(TableEnhance(mode: .sortAndFilter)).contains(" data-table-enhance=\"sort filter\""))
	}

	// MARK: - 10. skip target

	@Test("SkipTarget serializes data-skip-to")
	func skipTarget() {
		#expect(SkipTargetAttribute.name == "data-skip-to")
		#expect(SkipTarget(id: "main").attribute().value == "main")
		#expect(rendered(SkipTarget(id: "main")).contains(" data-skip-to=\"main\""))
	}

	// MARK: - 11. ticking label

	@Test("TickingLabel serializes the ms epoch as data-reltime")
	func tickingLabel() {
		#expect(TickingLabelAttribute.name == "data-reltime")
		#expect(TickingLabel(epochMilliseconds: 1_700_000_000_000).attribute().value == "1700000000000")
		#expect(rendered(TickingLabel(epochMilliseconds: 1_700_000_000_000))
			.contains(" data-reltime=\"1700000000000\""))
	}

	// MARK: - 12. elapsed clock

	@Test("ElapsedClock serializes the ms epoch as data-started")
	func elapsedClock() {
		#expect(ElapsedClockAttribute.name == "data-started")
		#expect(ElapsedClock(startedMilliseconds: 1_700_000_000_000).attribute().value == "1700000000000")
		#expect(rendered(ElapsedClock(startedMilliseconds: 1_700_000_000_000))
			.contains(" data-started=\"1700000000000\""))
	}

	// MARK: - 13. disclosure

	@Test("Disclosure serializes the bare data-preserve-open")
	func disclosure() {
		#expect(DisclosureAttribute.name == "data-preserve-open")
		#expect(Disclosure().attribute().value == "")
		#expect(rendered(Disclosure()).contains(" data-preserve-open"))
		#expect(!rendered(Disclosure()).contains("data-preserve-open=\"\""))
	}

	// MARK: - 14. inline edit

	@Test("InlineEdit serializes the bare data-inline-edit")
	func inlineEdit() {
		#expect(InlineEditAttribute.name == "data-inline-edit")
		#expect(InlineEdit().attribute().value == "")
		#expect(rendered(InlineEdit()).contains(" data-inline-edit"))
		#expect(!rendered(InlineEdit()).contains("data-inline-edit=\"\""))
	}

	// MARK: - 15. roving tabindex

	@Test("Roving serializes the bare data-roving")
	func roving() {
		#expect(RovingAttribute.name == "data-roving")
		#expect(Roving().attribute().value == "")
		#expect(rendered(Roving()).contains(" data-roving"))
		#expect(!rendered(Roving()).contains("data-roving=\"\""))
	}

	// MARK: - 16. scrollspy

	@Test("Scrollspy serializes the bare data-scrollspy")
	func scrollspy() {
		#expect(ScrollspyAttribute.name == "data-scrollspy")
		#expect(Scrollspy().attribute().value == "")
		#expect(rendered(Scrollspy()).contains(" data-scrollspy"))
		#expect(!rendered(Scrollspy()).contains("data-scrollspy=\"\""))
	}

	// MARK: - 17. theme choice

	@Test("ThemeChoice serializes data-theme-choice light/dark/system")
	func themeChoice() {
		#expect(ThemeChoiceAttribute.name == "data-theme-choice")
		#expect(ThemeChoice(mode: .light).attribute().value == "light")
		#expect(ThemeChoice(mode: .dark).attribute().value == "dark")
		#expect(ThemeChoice(mode: .system).attribute().value == "system")
		#expect(rendered(ThemeChoice(mode: .light)).contains(" data-theme-choice=\"light\""))
		#expect(rendered(ThemeChoice(mode: .dark)).contains(" data-theme-choice=\"dark\""))
		#expect(rendered(ThemeChoice(mode: .system)).contains(" data-theme-choice=\"system\""))
	}

	// MARK: - 18. autogrow

	@Test("Autogrow serializes the bare data-autogrow")
	func autogrow() {
		#expect(AutogrowAttribute.name == "data-autogrow")
		#expect(Autogrow().attribute().value == "")
		#expect(rendered(Autogrow()).contains(" data-autogrow"))
		#expect(!rendered(Autogrow()).contains("data-autogrow=\"\""))
	}

	// MARK: - 19. submit on enter

	@Test("SubmitOnEnter serializes the bare data-submit-on-enter")
	func submitOnEnter() {
		#expect(SubmitOnEnterAttribute.name == "data-submit-on-enter")
		#expect(SubmitOnEnter().attribute().value == "")
		#expect(SubmitOnEnter().attribute().mode == .legacy)
		#expect(SubmitOnEnterAttribute().mode == .legacy)
		#expect(rendered(SubmitOnEnter()).contains(" data-submit-on-enter"))
		#expect(!rendered(SubmitOnEnter()).contains("data-submit-on-enter=\"\""))
	}

	@Test("SubmitOnEnter(mode:) carries the mode and serializes plain/meta by value")
	func submitOnEnterModes() {
		#expect(SubmitOnEnterMode.legacy.rawValue == "legacy")
		#expect(SubmitOnEnterMode.plain.rawValue == "plain")
		#expect(SubmitOnEnterMode.meta.rawValue == "meta")
		#expect(SubmitOnEnter(mode: .legacy).mode == .legacy)
		#expect(SubmitOnEnter(mode: .plain).attribute().mode == .plain)
		#expect(SubmitOnEnterAttribute(mode: .plain).value == "plain")
		#expect(SubmitOnEnterAttribute(mode: .meta).value == "meta")
	}

	@Test("SubmitOnEnterAttribute(mode:) renders the value form; legacy stays bare")
	func submitOnEnterModeAttributeText() {
		#expect(SubmitOnEnterAttribute(mode: .plain).attributeText == " data-submit-on-enter=\"plain\"")
		#expect(SubmitOnEnterAttribute(mode: .meta).attributeText == " data-submit-on-enter=\"meta\"")
		#expect(SubmitOnEnterAttribute(mode: .legacy).attributeText == " data-submit-on-enter")
		#expect(rendered(SubmitOnEnter(mode: .plain)).contains(" data-submit-on-enter=\"plain\""))
		#expect(rendered(SubmitOnEnter(mode: .meta)).contains(" data-submit-on-enter=\"meta\""))
		#expect(!rendered(SubmitOnEnter(mode: .legacy)).contains("data-submit-on-enter=\"legacy\""))
	}

	// MARK: - 20. clear on submit

	@Test("ClearOnSubmit serializes the bare data-clear-on-submit")
	func clearOnSubmit() {
		#expect(ClearOnSubmitAttribute.name == "data-clear-on-submit")
		#expect(ClearOnSubmit().attribute().value == "")
		#expect(rendered(ClearOnSubmit()).contains(" data-clear-on-submit"))
		#expect(!rendered(ClearOnSubmit()).contains("data-clear-on-submit=\"\""))
	}

	// MARK: - 21. number clamp

	@Test("NumberClamp serializes min,max as data-clamp")
	func numberClamp() {
		#expect(NumberClampAttribute.name == "data-clamp")
		#expect(NumberClamp(min: 0, max: 10).attribute().value == "0,10")
		#expect(NumberClamp(min: -5, max: 5).attribute().value == "-5,5")
		#expect(rendered(NumberClamp(min: 0, max: 10)).contains(" data-clamp=\"0,10\""))
		#expect(rendered(NumberClamp(min: -5, max: 5)).contains(" data-clamp=\"-5,5\""))
	}

	// MARK: - 22. filter list

	@Test("FilterList serializes the bare data-filter-list")
	func filterList() {
		#expect(FilterListAttribute.name == "data-filter-list")
		#expect(FilterList().attribute().value == "")
		#expect(rendered(FilterList()).contains(" data-filter-list"))
		#expect(!rendered(FilterList()).contains("data-filter-list=\"\""))
	}

	// MARK: - the rules the register rests on

	@Test("an empty value is the bare attribute; a non-empty value is quoted and escaped")
	func emptyValueIsTheBareAttribute() {
		struct FixtureAttribute: AttributeRepresentable {
			static let name = "data-fixture"
			let value: String
		}
		struct FixtureBehavior: Behavior {
			let value: String
			func attribute() -> FixtureAttribute { FixtureAttribute(value: value) }
		}

		// the pin: one consequence, one spelling.
		#expect(FixtureBehavior(value: "").attributeText == " data-fixture")
		#expect(FixtureBehavior(value: "v").attributeText == " data-fixture=\"v\"")
		#expect(FixtureBehavior(value: "a\"b&c").attributeText == " data-fixture=\"a&quot;b&amp;c\"")

		let bare = Element(.div) { Text("x") }.behavior(FixtureBehavior(value: "")).markup.html
		#expect(bare.contains(" data-fixture"))
		#expect(!bare.contains("data-fixture=\"\""), "an empty value must not be spelled `=\"\"`: \(bare)")
	}

	@Test("a text-carrying behavior is escaped, never spliced")
	func textValueIsEscaped() {
		let html = rendered(Clipboard(text: "a\"b&c<d>"))
		#expect(html.contains(" data-copy=\"a&quot;b&amp;c&lt;d&gt;\""), "value was not escaped: \(html)")
		#expect(!html.contains("onmouseover"), "attribute value escaped its quotes: \(html)")
	}

	@Test("the register's 25 attributes are distinct")
	func registerIsInjective() {
		let names: [String] = [
			ScrollFollowAttribute.name,
			ScrollKeyAttribute.name,
			ScrollToAttribute.name,
			DraftIdentityAttribute.name,
			FocusReturnAttribute.name,
			DismissStackAttribute.name,
			ReorderAttribute.name,
			ClipboardAttribute.name,
			TableEnhanceAttribute.name,
			SkipTargetAttribute.name,
			TickingLabelAttribute.name,
			ElapsedClockAttribute.name,
			DisclosureAttribute.name,
			InlineEditAttribute.name,
			RovingAttribute.name,
			ScrollspyAttribute.name,
			ThemeChoiceAttribute.name,
			AutogrowAttribute.name,
			SubmitOnEnterAttribute.name,
			ClearOnSubmitAttribute.name,
			NumberClampAttribute.name,
			FilterListAttribute.name,
			FilterInsertAttribute.name,
			FilterTemplateAttribute.name,
			FilterClearAttribute.name,
		]
		#expect(names.count == 25)
		#expect(Set(names).count == names.count, "two behaviors claim one attribute")
	}

	@Test("every behavior attribute is named in BEHAVIOUR.md")
	func everyAttributeAppearsInTheVocabularyDocument() throws {
		let doc = try String(
			contentsOf: FrozenSurface.packageRoot().appendingPathComponent("Documentation/BEHAVIOUR.md"),
			encoding: .utf8
		)
		let documented = Set(doc.matches(of: /data-[a-z][a-z0-9-]*/).map { String($0.output) })
		#expect(!documented.isEmpty, "BEHAVIOUR.md read as empty — the gate would pass vacuously")

		let names: [String] = [
			ScrollFollowAttribute.name,
			ScrollKeyAttribute.name,
			ScrollToAttribute.name,
			DraftIdentityAttribute.name,
			FocusReturnAttribute.name,
			DismissStackAttribute.name,
			ReorderAttribute.name,
			ClipboardAttribute.name,
			TableEnhanceAttribute.name,
			SkipTargetAttribute.name,
			TickingLabelAttribute.name,
			ElapsedClockAttribute.name,
			DisclosureAttribute.name,
			InlineEditAttribute.name,
			RovingAttribute.name,
			ScrollspyAttribute.name,
			ThemeChoiceAttribute.name,
			AutogrowAttribute.name,
			SubmitOnEnterAttribute.name,
			ClearOnSubmitAttribute.name,
			NumberClampAttribute.name,
			FilterListAttribute.name,
			FilterInsertAttribute.name,
			FilterTemplateAttribute.name,
			FilterClearAttribute.name,
		]
		let missing = Set(names).subtracting(documented).sorted()
		#expect(
			missing.isEmpty,
			"BEHAVIOUR.md does not name: \(missing.joined(separator: ", "))"
		)
	}
}
