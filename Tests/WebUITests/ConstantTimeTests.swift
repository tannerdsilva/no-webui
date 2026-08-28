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

	@Test("data overload behaves identically")
	func dataOverload() {
		#expect(constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3])))
		#expect(constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 4])) == false)
		#expect(constantTimeEquals(Data(), Data([1])) == false)
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
}
