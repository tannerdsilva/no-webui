import Testing
import WebUI

// MARK: - csp extras
//
// A host that needs one more directive than the default policy has (`img-src … https:`,
// a `font-src`, a `form-action`) used to have to pass the whole policy — and a restated
// policy names no nonce source, so `HTMLDocument` suppressed the pre-paint theme prelude
// rather than ship an inline script the browser refuses. Extras extend the default
// instead, merged per directive name, and the nonce survives.
//
// These tests assert through `render()`: the rendered output is the thing a client
// parses, and the policy is only correct if it ends up in the page that way.

@Suite("csp extras")
struct CSPExtrasTests {

	private func render(
		policy: String? = nil,
		extras: String? = nil
	) -> String {
		HTMLDocument(
			title: "t",
			body: "<p>x</p>",
			clientMode: ClientBoot(),
			contentSecurityPolicy: policy,
			contentSecurityPolicyExtras: extras
		).render()
	}

	private func policyLine(_ html: String) -> String {
		guard let range = html.range(of: #"<meta http-equiv="Content-Security-Policy" content="[^"]*""#, options: .regularExpression)
		else { return "" }
		return String(html[range])
	}

	@Test("extras merge per name and the nonce survives, so the prelude is emitted")
	func extrasKeepTheNonceAndThePrelude() {
		let html = render(extras: "img-src 'self' data: https: blob:; font-src 'self' data:")
		let policy = policyLine(html)

		// the extra replaced the default's img-src (repeating a name is undefined)
		#expect(policy.contains("img-src 'self' data: https: blob:"))
		#expect(policy.components(separatedBy: "img-src ").count == 2)
		// a directive the default does not have is appended
		#expect(policy.contains("font-src 'self' data:"))
		// everything else is carried over untouched, nonce included
		#expect(policy.contains("script-src 'self' 'wasm-unsafe-eval' 'nonce-"))
		#expect(policy.contains("connect-src 'self' ws: wss:"))
		// and the prelude is actually emitted, which is the point of keeping the nonce
		#expect(html.range(of: #"<script nonce="[^"]+">"#, options: .regularExpression) != nil)
	}

	@Test("without extras the policy is byte-identical to the nonced default")
	func noExtrasIsTheDefault() {
		let html = render()
		let policy = policyLine(html)
		#expect(policy.contains("default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'nonce-"))
		#expect(!policy.contains("font-src"))
		#expect(html.range(of: #"<script nonce="[^"]+">"#, options: .regularExpression) != nil)
	}

	@Test("a restated policy still suppresses the prelude — extras do not rescue a missing nonce")
	func restatedPolicyKeepsTheOldRule() {
		let html = render(policy: "default-src 'self'; script-src 'self'", extras: "img-src 'self' https:")
		let policy = policyLine(html)
		// the extras still merge into a host policy …
		#expect(policy.contains("img-src 'self' https:"))
		// … but the policy names no nonce, so no inline script may be emitted
		#expect(html.range(of: #"<script nonce="[^"]+">"#, options: .regularExpression) == nil)
	}

	@Test("a policy with no client runtime merges the extras and carries no wasm permission")
	func noRuntimePolicyMergesExtras() {
		let html = HTMLDocument(
			title: "t",
			body: "<p>x</p>",
			includeRuntime: false,
			contentSecurityPolicyExtras: "img-src 'self' data: https:"
		).render()
		let policy = policyLine(html)
		#expect(policy.contains("img-src 'self' data: https:"))
		#expect(!policy.contains("wasm-unsafe-eval"))
	}
}