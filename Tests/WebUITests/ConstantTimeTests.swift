import Foundation
import Testing

@testable import WebUI

@Suite("ConstantTimeEquals")
struct ConstantTimeEqualsTests {

	@Test("equal byte sequences compare equal")
	func equal() {
		#expect(constantTimeEquals([1, 2, 3, 4], [1, 2, 3, 4]))
		#expect(constantTimeEquals(Array("token-secret".utf8), Array("token-secret".utf8)))
	}

	@Test("differing byte sequences compare unequal")
	func unequal() {
		#expect(constantTimeEquals([1, 2, 3], [1, 2, 4]) == false)
		#expect(constantTimeEquals([0x00], [0x01]) == false)
	}

	@Test("length mismatch short-circuits to false")
	func lengthMismatch() {
		#expect(constantTimeEquals([1, 2, 3], [1, 2]) == false)
		#expect(constantTimeEquals([], [1]) == false)
	}

	@Test("byte-sequence comparison matches expected results")
	func dataOverload() {
		#expect(constantTimeEquals([1, 2, 3], [1, 2, 3]))
		#expect(constantTimeEquals([1, 2, 3], [1, 2, 4]) == false)
		#expect(constantTimeEquals([], [1]) == false)
	}

	@Test("differing at the last byte still fails")
	func lastByteDiffers() {
		#expect(constantTimeEquals([0, 0, 0, 0xFF], [0, 0, 0, 0xFE]) == false)
	}
}

@Suite("CSRFRegression")
struct CSRFRegressionTests {

	@Test("valid tokens still validate end-to-end after the constant-time swap")
	func validToken() {
		let secret = CSRFProtection.generateSecret()
		let token = CSRFProtection.token(for: "login-form", secret: secret)
		#expect(CSRFProtection.validate(token, for: "login-form", secret: secret))
	}

	@Test("tampered signatures are rejected")
	func tampered() {
		let secret = CSRFProtection.generateSecret()
		let token = CSRFProtection.token(for: "login-form", secret: secret)
		#expect(CSRFProtection.validate(token + "x", for: "login-form", secret: secret) == false)
		#expect(CSRFProtection.validate(token, for: "other-form", secret: secret) == false)
		#expect(CSRFProtection.validate(token, for: "login-form", secret: "different") == false)
	}

	@Test("expiry(of:) reads the embedded timestamp of a valid token")
	func expiryAccessor() {
		let secret = CSRFProtection.generateSecret()
		let before = Date().timeIntervalSince1970
		let token = CSRFProtection.token(for: "login", secret: secret, maxAge: 1800)
		let expiry = CSRFProtection.expiry(of: token)
		#expect(expiry != nil)
		#expect(expiry! > before)
		#expect(expiry! <= before + 1800 + 1)
		// the expiry is in the future while the token is valid.
		#expect(CSRFProtection.validate(token, for: "login", secret: secret))
		#expect(CSRFProtection.expiry(of: "not-a-token") == nil)
		#expect(CSRFProtection.expiry(of: "!!!bad!!!") == nil)
	}

	@Test("tokens minted in the same wall-clock second are unique")
	func sameSecondUniqueness() {
		let secret = CSRFProtection.generateSecret()
		// the expiry payload is second-truncated; without the per-token nonce
		// these would be byte-identical, which would break single-use stores.
		let first = CSRFProtection.token(for: "login", secret: secret)
		let second = CSRFProtection.token(for: "login", secret: secret)
		#expect(first != second)
		#expect(CSRFProtection.validate(first, for: "login", secret: secret))
		#expect(CSRFProtection.validate(second, for: "login", secret: secret))
	}
}
