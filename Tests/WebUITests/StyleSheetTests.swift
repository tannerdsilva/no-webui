import Testing
import WebUI
import WebUIDesignSystem

// MARK: - StyleSheet (W5.3)
//
// `StyleSheet` is the public, layered artifact for host-defined css: a typed
// `CascadeLayer` (webui / webui.utilities / host), a result builder over the
// existing `CSSRule` vocabulary, and a `css` payload that is self-contained —
// the canonical layer order statement plus the rules inside `@layer host { … }`
// — so it wins the cascade by origin wherever its bytes land.

@Suite("StyleSheet")
struct StyleSheetTests {

	@Test("the builder accepts single rules, arrays, and control flow")
	func builderForms() {
		let sheet = StyleSheet(name: "probe") {
			CSSRule(".a", [CSSDeclaration("color", "red")])
			if true {
				CSSRule(".b", [CSSDeclaration("color", "blue")])
			} else {
				CSSRule(".b", [CSSDeclaration("color", "black")])
			}
			for n in 0..<2 {
				CSSRule(".c-\(n)", [CSSDeclaration("gap", "\(n)px")])
			}
			LayoutStyles.complete
		}
		let expected = 1 + 1 + 2 + LayoutStyles.complete.count
		#expect(sheet.rules.count == expected, "saw \(sheet.rules.count), expected \(expected)")
		#expect(sheet.rules[0].selector == ".a")
		#expect(sheet.rules[1].selector == ".b")
		#expect(sheet.rules[2].selector == ".c-0")
		#expect(sheet.rules[3].selector == ".c-1")
	}

	@Test("the default layer is host")
	func defaultLayer() {
		#expect(StyleSheet(name: "x") { CSSRule(".a", []) }.layer == .host)
		#expect(StyleSheet(name: "x", layer: .webui) { CSSRule(".a", []) }.layer == .webui)
	}

	@Test("cascade layers carry the webui, webui.utilities and host names, host last")
	func layerNames() {
		#expect(CascadeLayer.webui.rawValue == "webui")
		#expect(CascadeLayer.utilities.rawValue == "webui.utilities")
		#expect(CascadeLayer.host.rawValue == "host")
		// the canonical order: framework, then the utility layer, then host —
		// the statement that makes a host sheet win by origin anywhere.
		#expect(CascadeLayer.orderStatement == "@layer webui, webui.utilities, host;")
	}

	@Test("the css payload is the order statement plus the named layer block")
	func cssShape() {
		let sheet = StyleSheet(name: "probe") {
			CSSRule(".host-card", [CSSDeclaration("padding", "1rem")])
			CSSRule(".host-card__title", [CSSDeclaration("font-weight", "700")])
		}
		let css = sheet.css
		#expect(css.hasPrefix("@layer webui, webui.utilities, host;\n@layer host {\n"))
		#expect(css.contains("  .host-card {\n    padding: 1rem;\n  }"))
		#expect(css.contains("  .host-card__title {\n    font-weight: 700;\n  }"))
		#expect(css.hasSuffix("}\n}"))
		// the shipped bytes carry no prose
		#expect(!css.contains("/*"))
	}

	@Test("a layer-scoped sheet rides the named layer")
	func explicitLayerRidesTheLayer() {
		let sheet = StyleSheet(name: "util", layer: .utilities) {
			CSSRule(".util-x", [CSSDeclaration("display", "grid")])
		}
		#expect(sheet.css.hasPrefix("@layer webui, webui.utilities, host;\n@layer webui.utilities {\n"))
		#expect(sheet.css.contains("  .util-x {\n    display: grid;\n  }"))
	}

	@Test("a host sheet's rules reach the served document inside the host layer, after the framework statement")
	func documentEmissionOrder() throws {
		let doc = WebUIDocument(
			title: "t",
			body: "<button class=\"button button--primary\">go</button>",
			styleSheets: [
				StyleSheet(name: "probe") {
					CSSRule(".button--primary", [CSSDeclaration("background", "rgb(240, 20, 20)")])
				}
			],
			stylesheetURL: nil
		).renderThroughBuffer()

		// this test asserts *rendered output*: the collision pair — the
		// framework's own `.button--primary` rule and the host's — both reach
		// the page, and the host block lands after the framework's order
		// statement, so the layer order makes the host rule win.
		let framework = try #require(doc.range(of: "@layer webui, webui.utilities;"))
		let hostStatement = try #require(doc.range(of: "@layer webui, webui.utilities, host;"))
		let hostBlock = try #require(doc.range(of: "@layer host {"))
		// the indented declaration shape is unique to the host-emitted block
		// (the framework rule writes `  background: var(--btn-bg);`).
		let hostRule = try #require(doc.range(of: ".button--primary {\n    background: rgb(240, 20, 20);\n  }"))

		#expect(framework.lowerBound < hostStatement.lowerBound, "the host order statement must land after the framework's")
		#expect(hostStatement.lowerBound < hostBlock.lowerBound, "the host statement must precede the host layer block")
		#expect(hostBlock.lowerBound < hostRule.lowerBound, "the host rule must ride inside the host layer block")
		// the framework's own collision rule (indentation stripped by minify)
		#expect(doc.contains("background: var(--btn-bg);"), "the framework's own rule must still be on the page for the collision to exist")
	}

	@Test("a linked-framework page still carries the host sheet inline, after the link")
	func linkedModeStillEmitsHostSheets() throws {
		let doc = WebUIDocument(
			title: "t",
			body: "<p>x</p>",
			styleSheets: [
				StyleSheet(name: "probe") { CSSRule(".x", [CSSDeclaration("color", "red")]) }
			],
			stylesheetURL: "/__assets/css.abc"
		).renderThroughBuffer()
		let link = try #require(doc.range(of: "<link rel=\"stylesheet\" href=\"/__assets/css.abc\">"))
		let hostStatement = try #require(doc.range(of: "@layer webui, webui.utilities, host;"))
		#expect(link.upperBound < hostStatement.lowerBound, "the host layer must come after the framework link, so it is declared later")
		#expect(doc.contains("@layer host {\n  .x {\n    color: red;\n  }"))
	}

	@Test("a page without host sheets emits byte-identically")
	func noHostByteIdentity() throws {
		// the csp nonce is re-minted on every render — the only thing that may
		// differ between two renders of the same document (the byte pin on the
		// real showcase counts bytes, which the nonce never moves). scrub it in
		// both spots (attribute and csp source) and compare the rest exactly.
		let scrubbed = Self.scrubbedNonces(_:)
		// `plain` is the pre-W5.3 call shape — no styleSheets argument at all —
		// and must emit byte-identically to one that passes an empty list.
		let plain = scrubbed(WebUIDocument(title: "t", body: "<p>x</p>", stylesheetURL: nil).renderThroughBuffer())
		let withEmpty = scrubbed(WebUIDocument(title: "t", body: "<p>x</p>", styleSheets: [], stylesheetURL: nil).renderThroughBuffer())
		let withExplicitHostless = scrubbed(WebUIDocument(
			title: "t",
			body: "<p>x</p>",
			styleSheets: [StyleSheet(name: "empty", layer: .host, { [] })],
			stylesheetURL: nil
		).renderThroughBuffer())
		#expect(plain == withEmpty)
		// the default document never declares a host layer
		#expect(!plain.contains("@layer webui, webui.utilities, host;"))
		// an empty sheet is still an emission (it declares the host layer) —
		// the shell must not mistake it for nothing.
		#expect(withExplicitHostless != plain)
		#expect(withExplicitHostless.contains("@layer webui, webui.utilities, host;"))
	}

	private static func scrubbedNonces(_ html: String) -> String {
		html
			.replacingOccurrences(of: #"nonce="[A-Za-z0-9_-]+""#, with: #"nonce="N""#, options: .regularExpression)
			.replacingOccurrences(of: #"'nonce-[A-Za-z0-9_-]+'"#, with: "'nonce-N'", options: .regularExpression)
	}
}
