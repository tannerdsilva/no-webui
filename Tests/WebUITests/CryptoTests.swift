import Testing
import Foundation
import WebUI

// rfc 4231 known-answer tests. these run against rawdog's official sha-256 /
// hmac suite (via the HMACSHA256 facade) — the same vectors execute on macOS
// and linux, pinning byte-identical output on both.

private func hexDecode(_ hex: String) -> [UInt8] {
	let clean = hex.filter { !$0.isWhitespace }
	var out = [UInt8]()
	out.reserveCapacity(clean.count / 2)
	var index = clean.startIndex
	while index < clean.endIndex {
		let next = clean.index(index, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
		if let byte = UInt8(String(clean[index..<next]), radix: 16) {
			out.append(byte)
		}
		index = next
	}
	return out
}

@Suite("HMAC-SHA256 Known-Answer Tests (RFC 4231)")
struct RFC4231Tests {

	@Test("test case 1 — 20-byte key, short message")
	func case1() throws {
		let key = [UInt8](repeating: 0x0b, count: 20)
		let message = Array("Hi There".utf8)
		let expected = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("test case 2 — short key within the block size")
	func case2() throws {
		let key = Array("Jefe".utf8)
		let message = Array("what do ya want for nothing?".utf8)
		let expected = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("test case 3 — block-size key, 50-byte data")
	func case3() throws {
		let key = [UInt8](repeating: 0xaa, count: 20)
		let message = [UInt8](repeating: 0xdd, count: 50)
		let expected = "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("test case 4 — key with sequential bytes, 50-byte data")
	func case4() throws {
		let key = hexDecode("0102030405060708090a0b0c0d0e0f10111213141516171819")
		let message = [UInt8](repeating: 0xcd, count: 50)
		let expected = "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("test case 5 — rfc truncates the digest to 128 bits; prefix must match")
	func case5() throws {
		let key = [UInt8](repeating: 0x0c, count: 20)
		let message = Array("Test With Truncation".utf8)
		let full = try HMACSHA256.hex(message: message, key: key)
		#expect(full.hasPrefix("a3b6167473100ee06e0c796c2955552b"))
		#expect(full.count == 64)
	}

	@Test("test case 6 — key larger than the block size is hashed first")
	func case6() throws {
		let key = [UInt8](repeating: 0xaa, count: 131)
		let message = Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8)
		let expected = "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("test case 7 — large key and large data")
	func case7() throws {
		let key = [UInt8](repeating: 0xaa, count: 131)
		let message = Array("This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.".utf8)
		let expected = "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"
		#expect(try HMACSHA256.hex(message: message, key: key) == expected)
	}

	@Test("empty key and message produce the known hmac digest")
	func emptyKeyAndMessage() throws {
		let digest = try HMACSHA256.authenticate(message: [], with: [])
		#expect(bytesToHex(digest) == "b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad")
	}

	@Test("string-based hex API matches byte-based API")
	func stringAPI() throws {
		let viaBytes = try HMACSHA256.hex(message: Array("message".utf8), key: Array("key".utf8))
		let viaStrings = try HMACSHA256.hex(message: "message", key: "key")
		#expect(viaStrings == viaBytes)
		#expect(viaStrings?.count == 64)
	}
}

@Suite("Secure Random Bytes")
struct SecureRandomTests {

	@Test("produces the requested length of bytes")
	func length() {
		#expect(SecureRandom.bytes(0) == [])
		#expect(SecureRandom.bytes(16)?.count == 16)
		#expect(SecureRandom.bytes(32)?.count == 32)
	}

	@Test("does not emit all-zero buffers")
	func notAllZeros() {
		let bytes = SecureRandom.bytes(64) ?? []
		#expect(!Set(bytes).isSubset(of: [0]))
	}

	@Test("two draws differ (smoke)")
	func notConstant() {
		let a = SecureRandom.bytes(32) ?? []
		let b = SecureRandom.bytes(32) ?? []
		#expect(a != b)
	}

	@Test("CSRF secrets and nonces remain valid base64-url strings")
	func csrfSurface() {
		let secret = CSRFProtection.generateSecret()
		#expect(!secret.isEmpty)
		#expect(Data(base64Encoded: secret)?.count == 32)
		let token = CSRFProtection.token(for: "form-1", secret: secret)
		#expect(CSRFProtection.validate(token, for: "form-1", secret: secret))
		#expect(!CSRFProtection.validate(token, for: "form-2", secret: secret))
	}
}
