import Testing
import WebUICore

// the contract of `FieldID` / `FieldValues`.
//
// the point of the type is NOT that it is nicer to type — it is that one
// identity has one spelling, so the four-or-five places a field name used to
// appear cannot disagree. every test below is about agreement, not aesthetics.

@Suite("field identity")
struct FieldIDTests {

	private func markup(_ view: some View) -> String { view.markup.html }

	@Test("`field:` sets id and name from one value")
	func inputFromField() {
		let html = markup(Input(field: "cat-name-input"))
		#expect(html.contains("id=\"cat-name-input\""), "got: \(html)")
		#expect(html.contains("name=\"cat-name-input\""), "got: \(html)")
	}

	@Test("`field:` is byte-identical to spelling id and name by hand")
	func byteIdenticalToManualPair() {
		// the two spellings must not be distinguishable on the wire, or the
		// migration would move goldens and hide real changes among them.
		let viaField = markup(Input(field: "cat-name-input"))
		let viaPair = markup(Input(id: "cat-name-input", name: "cat-name-input"))
		#expect(viaField == viaPair, "field: \(viaField)\npair:  \(viaPair)")
	}

	@Test("the pair CAN disagree — which is exactly what the type prevents")
	func theDefectItRemoves() {
		// id and name are two independent Strings on the old initializer: a
		// field can post under one name while the handler reads another.
		let drifting = markup(Input(id: "cat-name-input", name: "cat-nam-input"))
		#expect(drifting.contains("id=\"cat-name-input\""))
		#expect(drifting.contains("name=\"cat-nam-input\""))
		// `field:` has no such state.
		let fixed = markup(Input(field: "cat-name-input"))
		#expect(fixed.contains("name=\"cat-name-input\""))
	}

	@Test("two identities cannot collide on the wire")
	func distinctIdentities() {
		let a = markup(Input(field: "first"))
		let b = markup(Input(field: "second"))
		#expect(a != b)
		#expect(!a.contains("second"))
	}

	@Test("textarea and select carry the same identity in both roles")
	func otherControls() {
		let ta = markup(TextArea(field: "notes", value: "x"))
		#expect(ta.contains("id=\"notes\"") && ta.contains("name=\"notes\""), "got: \(ta)")

		let sel = markup(Select(field: "effort",
		                        options: [SelectOption(value: "low", label: "Low")], selected: "low"))
		#expect(sel.contains("id=\"effort\"") && sel.contains("name=\"effort\""), "got: \(sel)")
	}

	@Test("a label binds to the same identity")
	func labelBinding() {
		let html = markup(Label("Name", for: "cat-name-input"))
		#expect(html.contains("for=\"cat-name-input\""), "got: \(html)")
	}

	@Test("the CSS selector and the wire id are the same identity")
	func selectorShape() {
		// the fifth role: a sheet targets `#cat-name-input`. deriving it from the
		// same value is what lets a census compare the two files.
		let id: FieldID = "cat-name-input"
		#expect(id.selector == "#cat-name-input")
		#expect(id.selector.dropFirst() == Substring(id.rawValue))
	}
}

@Suite("field values")
struct FieldValuesTests {

	@Test("a literal key resolves like the dictionary it replaces")
	func literalKeys() {
		// adoption must not require rewriting call sites: these are the exact
		// spellings arc uses against `[String: String]` today.
		var values: FieldValues = [:]
		values["cat-name-input"] = "work"
		#expect(values["cat-name-input"] == "work")
		#expect(values["missing"] ?? "" == "")
	}

	@Test("assigning nil removes the field, as distinct from empty")
	func removal() {
		var values: FieldValues = [:]
		values["a"] = "typed"
		values["a"] = nil
		#expect(values["a"] == nil, "removed, not empty")
		#expect(values.isEmpty)
	}

	@Test("dictionary-literal initialization")
	func dictionaryLiteral() {
		let values: FieldValues = ["a": "1", "b": "2"]
		#expect(values.count == 2)
		#expect(values["b"] == "2")
	}

	@Test("the defaulting subscript reads an untouched field as the fallback")
	func defaultingSubscript() {
		var values = FieldValues()
		values["edited"] = "new"
		#expect(values["edited", default: "original"] == "new")
		#expect(values["untouched", default: "original"] == "original")
	}

	@Test("a value survives a round trip through an explicit FieldID")
	func explicitIdentity() {
		// the reason the type exists: the write site and the read site can name
		// the same identity without repeating a literal.
		let field = FieldID("mcp-command-input")
		var values = FieldValues()
		values[field] = "npx"
		#expect(values[FieldID("mcp-command-input")] == "npx")
		#expect(values["mcp-command-input"] == "npx", "the literal and the value agree")
	}
}