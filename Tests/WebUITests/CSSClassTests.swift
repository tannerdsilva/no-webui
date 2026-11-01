import Testing
import WebUI

// the class vocabulary contract.
//
// the framework cannot ship the words: a measured 539 of the 562 class tokens
// the arc consumer spells are declared by arc's own sheet, and none is declared
// only by the framework's. what it ships is `CSSClass` — conformance is the
// declaration — plus the `ClassName` initializers that turn one into the
// attribute text an element merges.
//
// these tests pin the contract, not a vocabulary: the fixtures are local, and
// an app-side enum is expected to look exactly like them.

/// a fixture vocabulary: the shape an app is meant to declare.
private enum FixtureClass: String, CSSClass, CaseIterable {
	case card = "fixture-card"
	case row = "fixture-row"
	case muted = "fixture-muted"
}

/// a conformer that is not `RawRepresentable`: the protocol is the contract,
/// and a computed token is legal — the raw-value extension is only ergonomics.
private struct ComposedClass: CSSClass {
	let token: String
}

extension WebUITestRoot {
	@Suite("CSS class vocabulary", .serialized)
	struct CSSClassTests {

		@Test("a raw-value enum conformance yields its own token")
		func rawValueBecomesToken() {
			#expect(FixtureClass.card.token == "fixture-card")
			#expect(FixtureClass.allCases.map(\.token) == ["fixture-card", "fixture-row", "fixture-muted"])
		}

		@Test("a computed conformance is legal and is not second-class")
		func computedTokenConforms() {
			let composed = ComposedClass(token: "fixture-card fixture-muted")
			#expect(composed.token == "fixture-card fixture-muted")
			#expect(ClassName(composed).value == "fixture-card fixture-muted")
		}

		@Test("a declared token becomes class attribute text")
		func declaredTokenBecomesAttributeText() {
			#expect(ClassName(FixtureClass.row).value == "fixture-row")
			// the static form exists so a call site can say `.declared(...)` where a
			// ClassName is expected without spelling the initializer
			#expect(ClassName.declared(FixtureClass.row) == ClassName("fixture-row"))
		}

		@Test("several declared tokens join in order")
		func severalDeclaredTokensJoin() {
			#expect(ClassName([FixtureClass.card, FixtureClass.muted]).value == "fixture-card fixture-muted")
		}

		@Test("a declared class merges into the element's own classes")
		func declaredClassMerges() {
			// the 2.0 merge contract: a component's own classes survive a caller's
			// added ones, and nothing is repeated
			let html = Div(class: "fixture-card") { Text("x") }
				.addClass(ClassName(FixtureClass.muted))
				.markup.html
			#expect(html.contains("class=\"fixture-card fixture-muted\""), "got: \(html)")
		}

		@Test("a variadic declared list merges through classes(_:)")
		func variadicDeclaredListMerges() {
			let html = Div(class: "fixture-card") { Text("x") }
				.classes(ClassName(FixtureClass.row), ClassName(FixtureClass.muted))
				.markup.html
			#expect(html.contains("fixture-card fixture-row fixture-muted"), "got: \(html)")
		}

		@Test("the undeclared literal door still compiles during the migration window")
		func literalDoorStillCompiles() {
			// this is the door slice 4 deprecates. it is pinned here so the
			// deprecation has something to remove rather than a claim that it is gone.
			let named: ClassName = "fixture-row"
			#expect(named.value == "fixture-row")
			#expect(ClassName("fixture-row").value == "fixture-row")
		}
	}
}
