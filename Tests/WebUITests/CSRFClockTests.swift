import Testing
import Foundation
import WebUI
import WebUICore

// one clock, one entropy source, one failure policy.
//
// the clock is an argument (`now:`), not a stored or global seam: every case
// below pins it and never sleeps. the nonce comes from `SecureRandom`, so two
// tokens minted at the *same* pinned instant still differ — the property the
// single-use login-token store depends on.

@Suite("CSRFClockInjection")
struct CSRFClockTests {

	private static let pinnedNow: TimeInterval = 1_700_000_000
	private static let secret = "pinned-test-secret-not-random"

	@Test("a token minted at T validates inside its window and fails after it")
	func windowBoundaries() throws {
		let t = Self.pinnedNow
		let token = try CSRFProtection.token(for: "login", secret: Self.secret, maxAge: 60, now: t)

		#expect(CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t))
		// the last still-live instant
		#expect(CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t + 59))
		// and the first dead one: `now < expires` is strict, so expiry is exclusive
		#expect(!CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t + 60))
		#expect(!CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t + 61))
	}

	@Test("a token minted at T does not validate an hour later")
	func farFutureRejected() throws {
		let t = Self.pinnedNow
		let token = try CSRFProtection.token(for: "login", secret: Self.secret, now: t)
		#expect(!CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t + 3600))
	}

	@Test("two tokens minted at the same now differ (the nonce is real)")
	func sameInstantUniqueness() throws {
		let t = Self.pinnedNow
		// the embedded expiry is `Int`-truncated, so without a per-mint nonce
		// these two payloads would be byte-identical at one pinned instant.
		let first = try CSRFProtection.token(for: "login", secret: Self.secret, now: t)
		let second = try CSRFProtection.token(for: "login", secret: Self.secret, now: t)
		#expect(first != second)
		#expect(CSRFProtection.validate(first, for: "login", secret: Self.secret, now: t))
		#expect(CSRFProtection.validate(second, for: "login", secret: Self.secret, now: t))
	}

	@Test("the nonce is 32 hex characters from SecureRandom, not a UUID string")
	func nonceShape() throws {
		let token = try CSRFProtection.token(for: "login", secret: Self.secret, now: Self.pinnedNow)
		let decoded = try #require(Base64.decode(token))
		let parts = String(decoding: decoded, as: UTF8.self)
			.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
		#expect(parts.count == 4)
		let nonce = String(parts[2])
		// same length class as the UUID-hex it replaced: 16 bytes, hex-encoded.
		#expect(nonce.count == 32)
		#expect(nonce.allSatisfy { $0.isHexDigit })
		#expect(!nonce.contains("-"))
	}

	@Test("a tampered signature still fails at a pinned clock")
	func tamperedSignature() throws {
		let t = Self.pinnedNow
		let token = try CSRFProtection.token(for: "login", secret: Self.secret, maxAge: 60, now: t)
		let decoded = try #require(Base64.decode(token))
		let text = String(decoding: decoded, as: UTF8.self)
		// flip the last hex digit of the signature: a well-formed token whose
		// mac no longer matches. the clock is pinned, so expiry cannot be the
		// reason it rejects.
		let flipped = String(text.dropLast()) + (text.hasSuffix("0") ? "1" : "0")
		let forged = Base64.encode(Array(flipped.utf8))
		#expect(!CSRFProtection.validate(forged, for: "login", secret: Self.secret, now: t))
		#expect(CSRFProtection.validate(token, for: "login", secret: Self.secret, now: t))
		// and a token signed with a different secret never validates
		let other = try CSRFProtection.token(for: "login", secret: "another-secret", maxAge: 60, now: t)
		#expect(!CSRFProtection.validate(other, for: "login", secret: Self.secret, now: t))
	}

	@Test("the embedded expiry is exactly the pinned now plus maxAge")
	func expiryIsPinned() throws {
		let t = Self.pinnedNow
		let token = try CSRFProtection.token(for: "login", secret: Self.secret, maxAge: 1800, now: t)
		let expiry = try #require(CSRFProtection.expiry(of: token))
		#expect(Int(expiry) == Int(t) + 1800)
	}
}

@Suite("DocumentNonce")
struct DocumentNonceTests {

	@Test("a document renders with a nonce-backed csp and a nonced prelude")
	func documentRendersWithNonce() throws {
		let doc = HTMLDocument(body: .trusted("<p>x</p>"))
		let nonce = try #require(doc.nonce)
		#expect(!nonce.isEmpty)
		// 16 bytes, base64-url: 22 characters, no padding
		#expect(nonce.count == 22)
		#expect(!nonce.contains("="))

		let html = doc.markup.html
		#expect(html.contains("<meta http-equiv=\"Content-Security-Policy\""))
		#expect(html.contains("script-src 'self' 'wasm-unsafe-eval' 'nonce-\(nonce)'"))
		#expect(html.contains("<script nonce=\"\(nonce)\">"))
		// never an empty attribute: a nonce-less inline script is exactly the
		// page the suppression path exists to prevent.
		#expect(!html.contains("nonce=\"\""))
	}

	@Test("two documents mint different nonces")
	func distinctNonces() {
		let a = HTMLDocument(body: .trusted("<p>a</p>")).nonce
		let b = HTMLDocument(body: .trusted("<p>b</p>")).nonce
		#expect(a != nil)
		#expect(b != nil)
		#expect(a != b)
	}

	@Test("a head script carries the document nonce")
	func headScriptCarriesNonce() throws {
		let doc = HTMLDocument(body: .trusted("<p>x</p>"), headContent: .script(src: "/a.js"))
		let nonce = try #require(doc.nonce)
		#expect(doc.markup.html.contains("<script src=\"/a.js\" nonce=\"\(nonce)\"></script>"))
	}
}
