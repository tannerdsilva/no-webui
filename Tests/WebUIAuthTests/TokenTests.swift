import Foundation
import Testing

@testable import WebUIAuth

@Suite("SessionToken")
struct SessionTokenTests {

	@Test("generated tokens are 32 bytes and unique")
	func uniqueness() throws {
		let a = try SessionToken.generate()
		let b = try SessionToken.generate()
		#expect(a.count == SessionToken.byteCount)
		#expect(a != b)
	}

	@Test("hash is 32 bytes and deterministic")
	func hashDeterminism() throws {
		let token = try SessionToken.generate()
		let h1 = try SessionToken.hash(token)
		let h2 = try SessionToken.hash(token)
		#expect(h1.count == 32)
		#expect(h1 == h2)
	}

	@Test("hash never equals the token and differs across tokens")
	func hashProperties() throws {
		let a = try SessionToken.generate()
		let b = try SessionToken.generate()
		let ha = try SessionToken.hash(a)
		let hb = try SessionToken.hash(b)
		#expect(ha != a)
		#expect(hb != b)
		#expect(ha != hb)
	}

	@Test("hashing a wrong-length token throws")
	func invalidLength() {
		#expect(throws: SessionToken.TokenError.invalidLength) {
			_ = try SessionToken.hash(Data([0x01, 0x02]))
		}
	}
}
