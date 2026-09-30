import Testing
import WebUI
import WebUIDesignSystem

// MARK: - pre-paint theme prelude
//
// Without the prelude, a client with a stored scheme sees the DEFAULT palette paint first
// and then get replaced — a flash on every load. The prelude must be inline (a deferred
// script runs too late) and must therefore carry the csp nonce.

@Suite("theme prelude")
struct ThemePreludeTests {

	private func document(_ themePrelude: Bool = true, includeRuntime: Bool = true) -> String {
		HTMLDocument(
			title: "t",
			body: "<p>x</p>",
			includeRuntime: includeRuntime,
			themePrelude: themePrelude
		).render()
	}

	@Test("is emitted, inline, carrying the nonce, and free of comments")
	func preludeShape() {
		let html = document()
		#expect(html.contains("data-theme"))
		#expect(html.contains("data-scheme"))
		#expect(html.contains("localStorage.getItem('webui-theme')"))
		#expect(html.contains("localStorage.getItem('webui-scheme')"))
		// inline + nonced: a deferred or external prelude would run after first paint
		let nonced = html.range(of: #"<script nonce="[^"]+">\(function\(\)"#, options: .regularExpression)
		#expect(nonced != nil, "the prelude must be an inline nonce-carrying script")
		// first law: it is a shipped web asset. assert on the bytes that actually ship, not
		// on the constant — the rendered output is the thing a client parses.
		let body = preludeBody(html)
		#expect(!body.isEmpty)
		#expect(!body.contains("//"))
		#expect(!body.contains("/*"))
	}

	@Test("stays under its byte budget — it is on the critical path")
	func preludeBudget() {
		// the E2 budget gate pins engine/shell/sheet/islands from the asset manifest; the
		// prelude is a swift constant, not a file, so its ceiling lives beside its other
		// invariants. measured 213 bytes on 2026-09-30 — the ceiling carries ~20% headroom,
		// so a behaviour fix fits and a rewrite that triples the prelude does not.
		let bytes = preludeBody(document()).utf8.count
		#expect(bytes <= 256, "the pre-paint prelude ships inline on every themed page: \(bytes) bytes")
	}

	/// the inline script's body, i.e. what the client parses.
	private func preludeBody(_ html: String) -> String {
		guard let open = html.range(of: "<script nonce="),
			  let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex)
		else { return "" }
		let tag = html[open.upperBound..<close.lowerBound]
		guard let gt = tag.firstIndex(of: ">") else { return "" }
		return String(tag[tag.index(after: gt)...])
	}

	@Test("lands before the stylesheet, so the attribute is set before anything paints")
	func preludePrecedesStylesheet() {
		let html = document()
		let prelude = html.range(of: "localStorage.getItem('webui-theme')")!
		if let sheet = html.range(of: "<style>") {
			#expect(prelude.lowerBound < sheet.lowerBound)
		}
		if let link = html.range(of: "<link rel=\"stylesheet\"") {
			#expect(prelude.lowerBound < link.lowerBound)
		}
	}

	@Test("is suppressed when the caller opts out")
	func optOut() {
		#expect(!document(false).contains("localStorage.getItem('webui-theme')"))
	}

	@Test("is suppressed with no client runtime, which is the only thing that honours it")
	func suppressedWithoutRuntime() {
		let html = document(true, includeRuntime: false)
		#expect(!html.contains("localStorage.getItem('webui-theme')"),
			"a prelude that sets an attribute nothing reads is pure payload")
	}

	@Test("the engine honours the exact keys and attributes the prelude sets")
	func agreesWithTheEngine() {
		// the two cannot drift: the prelude is server-side, the reader is the engine asset.
		let engine = WebUIAssets.engine
		#expect(engine.contains("webui-theme"))
		#expect(engine.contains("webui-scheme"))
		#expect(engine.contains("data-theme"))
		#expect(engine.contains("data-scheme"))
		// comment lines only: `//` also appears inside string literals (urls, messages).
		let commentLines = engine
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { $0.hasPrefix("//") || $0.hasPrefix("/*") }
		#expect(commentLines.isEmpty, "the engine is a shipped asset: \(commentLines.prefix(3))")
	}

	@Test("the emitted csp authorizes the prelude's nonce")
	func cspAuthorizesTheNonce() {
		// invariant #1: every inline script's nonce is named by the policy that ships
		// with the page. a policy without it blocks the prelude — measured on the smoke
		// page and the block sweeps, where the console carried a `script-src` violation
		// and a stored theme never applied before paint.
		let html = document()
		guard let match = html.firstMatch(of: /<script nonce="([^"]+)">\(function\(\)/) else {
			Issue.record("no prelude to authorize")
			return
		}
		let nonce = String(match.1)
		#expect(html.contains("'nonce-\(nonce)'"), "the policy must name the prelude's nonce")
		#expect(html.contains("script-src 'self' 'wasm-unsafe-eval' 'nonce-\(nonce)'"))
	}

	@Test("a host policy with no nonce source suppresses the prelude instead of shipping a blocked script")
	func hostPolicyWithoutNonceSourceSkipsPrelude() {
		let html = HTMLDocument(
			title: "t",
			body: "<p>x</p>",
			contentSecurityPolicy: "default-src 'self'; script-src 'self';"
		).render()
		#expect(!html.contains("localStorage.getItem('webui-theme')"),
			"a prelude the browser will refuse is payload plus a console error")
		#expect(!html.contains("<script nonce="), "no inline script is emitted at all")
		#expect(html.contains("content=\"default-src 'self'; script-src 'self';\""),
			"the host's own policy is kept verbatim")
	}
}
