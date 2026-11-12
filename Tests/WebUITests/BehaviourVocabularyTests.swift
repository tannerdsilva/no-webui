import Testing
import Foundation
import WebUICore

// the engine's markup contract, pinned.
//
// the engine applies consequences by reading `data-*` attributes; a behavior
// exists only because a typed Swift value serialized to one. that makes the
// attribute set a public API, and this suite is its gate: every `data-*` the
// engine mentions must be named in `Documentation/BEHAVIOUR.md`, and every
// canonical behavior name must be a `data-` attribute the document declares.
//
// prove-it-fails: deleting one row from BEHAVIOUR.md turns
// `engineAttributesAreDocumented` red naming exactly that attribute.

@Suite("behaviour vocabulary")
struct BehaviourVocabularyTests {
	private static let packageRoot = FrozenSurface.packageRoot()

	private static func read(_ relative: String) throws -> String {
		try String(
			contentsOf: packageRoot.appendingPathComponent(relative),
			encoding: .utf8
		)
	}

	private static func attributes(in text: String) -> Set<String> {
		let pattern = /data-[a-z][a-z0-9-]*/
		return Set(text.matches(of: pattern).map { String($0.output) })
	}

	/// the §22.5 canonical names. the document is normative over every other
	/// mention in the plan, so the gate pins the document against this list.
	private static let canonical: Set<String> = [
		"data-follow",
		"data-follow-state",
		"data-scroll-key",
		"data-scroll-to",
		"data-draft-id",
		"data-focus-return",
		"data-dismiss",
		"data-reorder",
		"data-copy",
		"data-table-enhance",
		"data-skip-to",
		"data-reltime",
		"data-started",
		"data-elapsed",
		"data-preserve-open",
		"data-inline-edit",
		"data-roving",
		"data-scrollspy",
		"data-theme-choice",
		"data-autogrow",
		"data-submit-on-enter",
		"data-clear-on-submit",
		"data-clamp",
		"data-upload-into",
	]

	@Test("every attribute the engine reads is named in BEHAVIOUR.md")
	func engineAttributesAreDocumented() throws {
		let engine = try Self.read("designer/assets/webui-engine.js")
		let doc = try Self.read("Documentation/BEHAVIOUR.md")
		let engineAttributes = Self.attributes(in: engine)
		#expect(!engineAttributes.isEmpty, "engine source read as empty — the gate would pass vacuously")
		let documented = Self.attributes(in: doc)
		let missing = engineAttributes.subtracting(documented).sorted()
		#expect(
			missing.isEmpty,
			"engine reads attributes BEHAVIOUR.md does not name: \(missing.joined(separator: ", "))"
		)
	}

	@Test("the document declares every canonical behavior attribute")
	func canonicalAttributesAreDeclared() throws {
		let doc = try Self.read("Documentation/BEHAVIOUR.md")
		let documented = Self.attributes(in: doc)
		let missing = Self.canonical.subtracting(documented).sorted()
		#expect(
			missing.isEmpty,
			"BEHAVIOUR.md is missing canonical attributes: \(missing.joined(separator: ", "))"
		)
	}

	@Test("a behavior serializes through one escaped attribute door")
	func behaviorSerializesThroughOneDoor() {
		struct FixtureAttribute: AttributeRepresentable {
			static let name = "data-fixture"
			let value: String
		}
		struct FixtureBehavior: Behavior {
			let value: String
			func attribute() -> FixtureAttribute { FixtureAttribute(value: value) }
		}

		let html = Element(.div) { Text("x") }
			.behavior(FixtureBehavior(value: "a\"b&c"))
			.markup
			.html
		#expect(html.contains("data-fixture=\"a&quot;b&amp;c\""), "attribute was not escaped: \(html)")
		#expect(!html.contains("data-fixture='"), "attribute used the wrong quoting: \(html)")
	}

	@Test("an escaping behavior value cannot break out of the attribute")
	func behaviorValueCannotBreakOut() {
		struct FixtureAttribute: AttributeRepresentable {
			static let name = "data-fixture"
			let value: String
		}
		struct FixtureBehavior: Behavior {
			let value: String
			func attribute() -> FixtureAttribute { FixtureAttribute(value: value) }
		}

		let html = Element(.div) { Text("x") }
			.behavior(FixtureBehavior(value: "\" onmouseover=\"alert(1)"))
			.markup
			.html
		#expect(!html.contains("onmouseover=\"alert(1)\""), "attribute value escaped its quotes: \(html)")
	}
}
