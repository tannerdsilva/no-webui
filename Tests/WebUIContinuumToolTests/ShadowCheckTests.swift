import Foundation
import Testing
@testable import WebUIContinuumTool

// MARK: - DX-15b shadow-check unit fixtures (lane T)
//
// the anti-shadow policy leg, in isolation: the selector-extraction legs pick
// exact class tokens out of string-literal CSS, `CSSRule("…")` args and
// `class="…"` literals; the DS union (built-in + real-artifact) names the
// owning component; a consumer sheet that restyles a DS class by its exact
// name is caught and named. the demo tree runs the SAME verb end-to-end
// (`designer/probes/t-*.mjs`) — these fixtures pin the pure functions.

@Suite("shadow: selector-extraction leg")
struct ShadowExtractionTests {

	@Test("string-literal CSS yields exact class tokens (triple-quoted sheet)")
	func stringLiteralCSS() {
		let source = "let sheet = \"\"\"\n.chip {\n  background: #111;\n}\n.chip--primary:hover { }\n\"\"\""
		let tokens = WebUIContinuumTool.Run.cssSelectors(in: source)
		#expect(tokens.contains("chip"))
		#expect(tokens.contains("chip--primary"))
	}

	@Test("string-literal CSS in a single-line escaped string")
	func singleQuotedCSS() {
		let source = "let a = \" .chip { } .chip--primary:hover { } \""
		let tokens = WebUIContinuumTool.Run.cssSelectors(in: source)
		#expect(tokens.contains("chip"))
		#expect(tokens.contains("chip--primary"))
	}

	@Test("CSSRule args yield the first argument's class tokens")
	func cssRuleArgs() {
		let tokens = WebUIContinuumTool.Run.cssRuleSelectors(
			in: "CSSRule(\".toast\", [CSSDeclaration(\"background\", \"black\")])"
		)
		#expect(tokens == ["toast"])
	}

	@Test("escaped class= attribute form (the on-disk shape) is read")
	func classAttributeLiterals() {
		// on-disk consumer source: the quote is escaped inside the Swift string.
		let source = "let html = \"<span class=\\\"swatch tool-btn\\\"></span>\""
		let tokens = WebUIContinuumTool.Run.escapedClassLiterals(in: source)
		#expect(tokens.contains("swatch"))
		#expect(tokens.contains("tool-btn"))
	}

	@Test("dedup across legs")
	func dedup() {
		let source = "CSSRule(\".chip\", []) + \" .chip { } \""
		let tokens = WebUIContinuumTool.Run.extractClassTokens(from: source)
		#expect(tokens.filter { $0 == "chip" }.count == 1)
	}

	@Test("escaped DS attribute form is read (the inventory scan's blind spot)")
	func escapedAttributeForm() {
		let tokens = WebUIContinuumTool.Run.escapedClassLiterals(in: " \" class=\\\"toast \\(variant.rawValue)\\\"\"")
		#expect(tokens.contains("toast"))
	}

	@Test("a plain class= literal (raw-string HS form) is still read by the legacy leg")
	func plainClassLiteral() {
		// the on-disk plain form — e.g. WebUIShell's raw-string markup
		// (`class="engine-status-mirror"`); no backslashes involved.
		let source = #"out += "<span class="counter-value"></span>""#
		let tokens = classLiterals(in: source)
		#expect(tokens.contains("counter-value"))
	}
}

@Suite("shadow: the DS union")
struct ShadowUnionTests {

	@Test("the built-in reference covers the nine shadowed classes")
	func builtInCoversNine() {
		let union = WebUIContinuumTool.Run.builtInDSUnion
		for name in ["chip", "kv", "toast", "modal-overlay", "log-line", "md", "swatch", "inline-edit", "tool-btn"] {
			#expect(union[name] != nil, "built-in DS union must list '\(name)'")
		}
		// the component-emitted classes name their owning component.
		#expect(union["chip"] == "WebUIChip")
		#expect(union["toast"] == "WebUIToast")
		#expect(union["modal-overlay"] == "WebUIModal")
		#expect(union["inline-edit"] == "WebUIInlineEdit")
	}

	@Test("DS component scan claims emitted classes with their component")
	func dsScanClaims() throws {
		let core = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/WebUIDesignSystemCore")
		guard FileManager.default.fileExists(atPath: core.path) else { return }
		let claims = try WebUIContinuumTool.Run.dsComponentClaims(in: core.path)
		// a component claims its emitted classes (the escaped-literal form).
		#expect(claims["WebUIToast"]?.contains("toast") == true, "WebUIToast must claim 'toast'")
		#expect(claims["WebUIChip"]?.contains("chip") == true, "WebUIChip must claim 'chip'")
		#expect(claims["WebUIModal"]?.contains("modal-overlay") == true, "WebUIModal must claim 'modal-overlay'")
	}

	@Test("the union from real artifacts contains the sheet's selectors")
	func realUnion() throws {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let css = root.appendingPathComponent("designer/assets/design-system.css")
		guard FileManager.default.fileExists(atPath: css.path) else { return }
		let core = root.appendingPathComponent("Sources/WebUIDesignSystemCore")
		let union = try WebUIContinuumTool.Run.buildDSUnion(
			dsCSS: css.path, dsSources: core.path, inventory: nil
		)
		#expect(union["chip"] != nil)
		#expect(union["kv"] != nil)
		#expect(union["swatch"] != nil)
		#expect(union["toast"] != nil)
	}
}

@Suite("shadow: files it never scans")
struct ShadowSourceTests {

	@Test("DS source paths are refused, not scanned")
	func refusesDSPaths() {
		#expect(WebUIContinuumTool.Run.isDesignSystemSource("/pkg/Sources/WebUIDesignSystemCore/View.swift"))
		#expect(WebUIContinuumTool.Run.isDesignSystemSource("/pkg/Sources/WebUIDesignSystem/Theme.swift"))
		#expect(WebUIContinuumTool.Run.isDesignSystemSource("/pkg/designer/assets/design-system.css"))
		#expect(!WebUIContinuumTool.Run.isDesignSystemSource("/consumer/Chrome.swift"))
		#expect(!WebUIContinuumTool.Run.isDesignSystemSource("/consumer/Sources/App/Theme.swift"))
	}
}
