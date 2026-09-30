import Testing
import WebUI

// MARK: - ProseGuard
//
// the first law, as a scanner: prose never reaches a client. these cases pin the
// places a naive `grep -c '//'` gate gets wrong — a url in a string, a template
// literal, a regex — and then assert the four payloads a client can receive.

@Suite("prose guard")
struct ProseGuardTests {

	@Test("a line comment is found, with the line it opens on")
	func lineComment() {
		let js = "var a = 1;\n// the note\nvar b = 2;\n"
		let findings = ProseGuard.findings(in: js, language: .javaScript)
		#expect(findings.count == 1)
		#expect(findings.first?.line == 2)
		#expect(findings.first?.text.contains("the note") == true)
	}

	@Test("a block comment is found, and its body is not scanned for more")
	func blockComment() {
		let js = "/* one // two\n   three */\nvar a = 1;"
		let findings = ProseGuard.findings(in: js, language: .javaScript)
		#expect(findings.count == 1)
		#expect(findings.first?.line == 1)
	}

	@Test("`//` inside a string is not a comment — the engine carries a ws url")
	func urlInString() {
		let js = #"var wsUrl = url || config.wsUrl || 'ws://' + location.host + '/ws';"#
		#expect(ProseGuard.findings(in: js, language: .javaScript).isEmpty)
	}

	@Test("`//` and `/*` inside a template literal are not comments")
	func proseInTemplate() {
		let js = "var u = `ws://${host}/ws`;\nvar note = `a // b /* c`;\n"
		#expect(ProseGuard.findings(in: js, language: .javaScript).isEmpty)
	}

	@Test("a comment inside a template's `${ … }` hole is still found")
	func commentInTemplateHole() {
		let js = "var v = `x${a // note\n}b`;\n"
		let findings = ProseGuard.findings(in: js, language: .javaScript)
		#expect(findings.count == 1)
		#expect(findings.first?.line == 1)
	}

	@Test("a regex literal's slashes are not a comment")
	func regexLiteral() {
		let js = "var re = /a\\/b/;\nvar x = 1;\n"
		#expect(ProseGuard.findings(in: js, language: .javaScript).isEmpty)
	}

	@Test("a regex after a keyword is the documented false positive, reported not hidden")
	func regexAfterKeyword() {
		// the preceder set is deliberately conservative (`)` is division far more
		// often than a regex follows a paren), so `return /…/` reads as division and
		// a `//` inside the body is reported. the trade is one-sided: a false failure
		// names its line and is local, a false negative ships the prose.
		let js = "return /a\\/\\//;\n"
		#expect(ProseGuard.findings(in: js, language: .javaScript).count == 1)
	}

	@Test("a css block comment is found; `//` is not a css comment")
	func cssComments() {
		let css = ":root { --a: 1; }\n/* designer note */\n.a { color: red; }\n.b { outline: 1px solid // not a comment; }\n"
		let findings = ProseGuard.findings(in: css, language: .css)
		#expect(findings.count == 1)
		#expect(findings.first?.line == 2)
	}

	@Test("`/*` inside a css string is not a comment")
	func cssStringIsNotAComment() {
		let css = ".a::before { content: \"/*\"; }\n"
		#expect(ProseGuard.findings(in: css, language: .css).isEmpty)
	}

	// MARK: the payloads

	@Test("every payload a client can receive is prose-free")
	func shippedPayloadsAreProseFree() {
		let payloads: [(String, String, ProseGuard.Language)] = [
			("WebUIAssets.js", WebUIAssets.js, .javaScript),
			("WebUIAssets.engine", WebUIAssets.engine, .javaScript),
			("WebUIAssets.shell", WebUIAssets.shell, .javaScript),
			("WebUIAssets.cssMinified", WebUIAssets.cssMinified, .css),
		]
		for (label, text, language) in payloads {
			let findings = ProseGuard.findings(in: text, language: language)
			#expect(findings.isEmpty, "\(label) carries prose: \(findings.prefix(3).map(\.description))")
		}
	}

	@Test("the guard would have caught the shipped prose it was written for")
	func guardCatchesRegression() {
		// the runtime shipped a seven-line "Host extension points" block verbatim
		// until the guard existed; this is that exact shape, asserted to be found.
		let js = "  var instance = null;\n\n  // Host extension points.\n  var hooks = [];\n"
		let findings = ProseGuard.findings(in: js, language: .javaScript)
		#expect(findings.count == 1)
		#expect(findings.first?.line == 3)
	}
}