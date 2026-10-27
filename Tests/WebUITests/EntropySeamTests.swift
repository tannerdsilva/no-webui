import Testing
import WebUI
import WebUIServer

// MARK: - 0.9 entropy seam
//
// `RenderToken.mint()` is public, frozen surface, and it used to call
// `SecureRandom` statically — so the one failure a page must survive (no
// entropy) had no way to be exercised. the seam is additive: an injectable
// source with a defaulted `.system`, so every zero-argument call keeps its exact
// meaning and a test can still make entropy fail.

/// an entropy source that always fails.
private struct FailingEntropy: SecureRandomSource {
	func bytes(_ count: Int) -> [UInt8]? { nil }
}

/// a source that returns a fixed byte for whatever it is asked for.
private struct FixedEntropy: SecureRandomSource {
	let byte: UInt8

	func bytes(_ count: Int) -> [UInt8]? {
		[UInt8](repeating: byte, count: count)
	}
}

@Suite("RenderToken entropy seam")
struct RenderTokenEntropyTests {

	@Test("a failing source makes mint return nil instead of a token")
	func failingSource() {
		#expect(RenderToken.mint(using: FailingEntropy()) == nil)
	}

	@Test("an injected source mints a 128-bit token")
	func injectedSource() {
		let token = RenderToken.mint(using: FixedEntropy(byte: 0xAB))
		let expected = Base64.encodeURL([UInt8](repeating: 0xAB, count: 16))
		#expect(token?.value == expected)
		// 16 bytes of base64url, unpadded
		#expect(token?.value.utf8.count == 22)
	}

	@Test("the default source is the platform one, and it still mints")
	func defaultSourceStillMints() throws {
		let token = try #require(RenderToken.mint())
		let explicit = try #require(RenderToken.mint(using: .system))
		#expect(token.value.utf8.count == 22)
		#expect(explicit.value.utf8.count == 22)
		#expect(!token.value.isEmpty)
		// two mints are independent draws
		let other = try #require(RenderToken.mint())
		#expect(other != token)
	}

	@Test("the platform source keeps its documented edge cases")
	func platformSourceContract() {
		#expect(SecureRandom.bytes(0) == [])
		#expect(SecureRandom.bytes(-1) == nil)
		#expect(SecureRandom.bytes(16)?.count == 16)
		#expect(FailingEntropy().bytes(0) == nil)
	}
}
