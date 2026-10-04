import Foundation
import Testing
import WebUI
import WebUICore

// MARK: - WebUIIsland — DX-4a byte-identity + the pinned serialization contract
//
// the W0-captured smoke page (`/tmp/dx-content-baseline/smoke.page.html`)
// carries two hand-written island region divs:
//
//   <div id="island-validate" data-webui-island="validate"
//        data-webui-args='{"value":"a","rules":[{"rule":"required"},
//        {"rule":"minLength","arg":4}]}'></div>
//   <div id="island-never" data-webui-island="never-built"
//        data-webui-args='{}'></div>
//
// they are extracted VERBATIM into `Tests/WebUITests/Fixtures/
// dx-w0-island-regions.html` (committed). every test in this suite that
// produces region markup must reproduce those bytes exactly — a reordered
// attribute, a `4.0`, a Dictionary-ordered args pair, or a double-quote
// attribute change all trip the byte-diff.

@Suite("WebUIIsland — byte-identical region markup (DX-4a)")
struct WebUIIslandTests {
	/// the captured fixture, as committed test resource (Bundle.module) with
	/// the package-root path as the fallback for runners that skip bundles.
	private static let fixturePath = "Tests/WebUITests/Fixtures/dx-w0-island-regions.html"

	private static func fixtureText() -> String {
		if let url = Bundle.module.url(forResource: "dx-w0-island-regions", withExtension: "html"),
		   let bundled = try? String(contentsOf: url, encoding: .utf8) {
			return bundled
		}
		return (try? String(contentsOfFile: fixturePath, encoding: .utf8)) ?? ""
	}

	/// the typed arguments that must serialize to the capture's wired JSON.
	private static let validateArgs = WebUIIslandArgs([
		.init("value", "a"),
		.init("rules", [
			.object([.init("rule", "required")]),
			.object([.init("rule", "minLength"), .init("arg", 4)]),
		]),
	])

	@Test("render() is byte-identical to the W0-captured smoke regions")
	func byteDiffAgainstW0Capture() {
		let fixture = Self.fixtureText()
		// validate: the derived-id path (name "validate" → id "island-validate").
		let validate = WebUIIsland("validate", args: Self.validateArgs).render()
		// never-built: the capture's region id is the hand-chosen "island-never",
		// which no derivation rule reproduces — the explicit-id path exists for it.
		let never = WebUIIsland(id: "island-never", name: "never-built").render()

		// the fixture is exactly the two captured lines, LF, trailing newline.
		#expect(fixture.count(where: { $0 == "\n" }) == 2)
		#expect(fixture == validate + "\n" + never + "\n")
		let lines = fixture.split(separator: "\n", omittingEmptySubsequences: false)
		#expect(String(lines[0]) == validate)
		#expect(String(lines[1]) == never)
	}

	@Test("the full validate region matches the capture byte-for-byte, spelled out")
	func exactValidateRegion() {
		let html = WebUIIsland("validate", args: Self.validateArgs).render()
		#expect(html == #"<div id="island-validate" data-webui-island="validate" data-webui-args='{"value":"a","rules":[{"rule":"required"},{"rule":"minLength","arg":4}]}'></div>"#)
		// a region is an empty paired div, not a void/self-closing element
		#expect(html.hasPrefix("<div "))
		#expect(html.hasSuffix("></div>"))
	}

	@Test("the empty-args region matches the capture's island-never")
	func emptyRegion() {
		let html = WebUIIsland(id: "island-never", name: "never-built").render()
		#expect(html == #"<div id="island-never" data-webui-island="never-built" data-webui-args='{}'></div>"#)
		// a lone @HotView with no wired args pre-emits an empty object (the
		// acceptance template's `WebUIIsland("feed")` form — appendix A).
		#expect(WebUIIsland("feed").render() == #"<div id="island-feed" data-webui-island="feed" data-webui-args='{}'></div>"#)
	}

	// MARK: the pinned serialization contract

	@Test("attribute order is pinned: id ⟶ data-webui-island ⟶ data-webui-args")
	func attributeOrder() {
		let html = WebUIIsland("validate", args: Self.validateArgs).render()
		let idIndex = html.firstRange(of: "id=\"island-validate\"")!.lowerBound
		let islandIndex = html.firstRange(of: "data-webui-island=")!.lowerBound
		let argsIndex = html.firstRange(of: "data-webui-args=")!.lowerBound
		#expect(idIndex < islandIndex)
		#expect(islandIndex < argsIndex)
	}

	@Test("args ride a single-quoted attribute; double quotes inside are raw JSON")
	func singleQuotedArgs() {
		let html = WebUIIsland("validate", args: Self.validateArgs).render()
		#expect(html.contains("data-webui-args='{\"value\":\"a\""))
		// the JSON's structural quotes are NOT attribute terminators
		#expect(html.contains("=\"island-validate\" data-webui-island=\"validate\" data-webui-args='"))
	}

	@Test("an Int arg serializes as 4, never 4.0")
	func intNotDouble() {
		#expect(WebUIIslandArgs([.init("arg", 4)]).json == #"{"arg":4}"#)
		let html = WebUIIsland("validate", args: Self.validateArgs).render()
		#expect(html.contains("\"arg\":4,") || html.contains("\"arg\":4}"))
		#expect(!html.contains("4.0"))
	}

	@Test("declaration order IS the byte order — reversing entries changes the bytes")
	func declarationOrder() {
		let ab = WebUIIslandArgs([.init("value", "a"), .init("rules", [.string("x")])])
		let ba = WebUIIslandArgs([.init("rules", [.string("x")]), .init("value", "a")])
		#expect(ab.json == #"{"value":"a","rules":["x"]}"#)
		#expect(ba.json == #"{"rules":["x"],"value":"a"}"#)
		#expect(ab.json != ba.json)
	}

	@Test("the empty object renders as {}")
	func emptyObject() {
		#expect(WebUIIslandArgs.empty.json == "{}")
		#expect(WebUIIslandArgs([]).json == "{}")
	}

	@Test("bool/null and scalar arrays render in canonical JSON")
	func scalars() {
		#expect(WebUIIslandArgs([
			.init("ok", true),
			.init("no", false),
			.init("nil", .null),
			.init("tags", [.string("a"), .string("b")]),
		]).json == #"{"ok":true,"no":false,"nil":null,"tags":["a","b"]}"#)
	}

	@Test("JSON strings escape quotes, backslashes and control scalars")
	func jsonStringEscaping() {
		let args = WebUIIslandArgs([
			.init("quote", "a\"b"),
			.init("slash", "a\\b"),
			.init("nl", "a\nb"),
			.init("ctrl", "\u{01}"),
		])
		#expect(args.json == #"{"quote":"a\"b","slash":"a\\b","nl":"a\nb","ctrl":"\u0001"}"#)
	}

	@Test("apostrophes/amps in values become attribute entities and decode back")
	func singleQuoteAttributeEscape() {
		// the JSON payload itself is untouched…
		let json = WebUIIslandArgs([.init("note", "don't & stop")]).json
		#expect(json == #"{"note":"don't & stop"}"#)
		// …but the single-quoted attribute carries the entity forms, which the
		// browser decodes before the engine's JSON.parse — round-trip safe.
		let html = WebUIIsland("note", args: WebUIIslandArgs([.init("note", "don't & stop")])).render()
		#expect(html == #"<div id="island-note" data-webui-island="note" data-webui-args='{"note":"don&#39;t &amp; stop"}'></div>"#)
	}

	@Test("the derived-id convenience matches the common capture form")
	func derivedID() {
		#expect(WebUIIsland("feed", args: .empty).render().hasPrefix(#"<div id="island-feed""#))
		#expect(WebUIIsland("validate", args: Self.validateArgs).render().hasPrefix(#"<div id="island-validate""#))
		// the explicit-id init is honored byte-for-byte (the never-built case)
		#expect(WebUIIsland(id: "island-never", name: "never-built").render().hasPrefix(#"<div id="island-never""#))
	}

	@Test("the hand-written smoke markup is reproduced exactly (no Raw() divergence)")
	func smokeRawEquivalence() {
		// the two captured strings are the literal values the smoke host
		// hand-writes via Raw(...) — guard the Raw-based page and the view
		// primitive against drifting apart.
		let validate = #"<div id="island-validate" data-webui-island="validate" data-webui-args='{"value":"a","rules":[{"rule":"required"},{"rule":"minLength","arg":4}]}'></div>"#
		let never = #"<div id="island-never" data-webui-island="never-built" data-webui-args='{}'></div>"#
		#expect(WebUIIsland("validate", args: Self.validateArgs).render() == validate)
		#expect(WebUIIsland(id: "island-never", name: "never-built").render() == never)
	}
}
