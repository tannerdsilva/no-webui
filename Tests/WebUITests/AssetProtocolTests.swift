import Foundation
import Testing
import WebUI
import WebUICore

// MARK: - the shipped-asset protocol
//
// `WebUIShippedAsset` is the one thing generated consumer code imports: a build tool emits
// a type per asset (bytes, address, compressed variant) and the server turns that
// conformance into a url and a registration that cannot disagree. what this suite pins is
// the convention the protocol *expresses* — the stamp is the sha256 prefix of the bytes it
// addresses — with a known-answer vector, because a stamp/body mismatch is exactly the
// "every page links a 404" bug class the protocol exists to make unrepresentable.

/// the stub conformance carries its stamp as a LITERAL, the way generated code does.
/// the payload and its digest are a fixed pair:
/// `printf ':root { --probe: 1 }\n' | shasum -a 256`
/// → `dc8a9766bbab75fd34df634ac3f103f26b8e11d909a3e8d09575046393dc05f3`
@Suite("shipped asset protocol")
struct AssetProtocolTests {

	struct StubAsset: WebUIShippedAsset {
		static let contentType = "text/css; charset=utf-8"
		static let body: [UInt8] = Array(":root { --probe: 1 }\n".utf8)
		static let stamp = "dc8a9766bbab"
		static let gzip: [UInt8]? = nil
	}

	@Test("a conformance's stamp is the sha256 prefix of the bytes it names")
	func stampIsTheSha256PrefixOfBody() {
		let digest = SHA256.hex(StubAsset.body)
		#expect(StubAsset.stamp == String(digest.prefix(12)), "the literal stamp drifted from the payload it addresses")
		#expect(StubAsset.stamp.count == 12, "the url convention is `?v=<12 hex>`")
	}

	@Test("the conformance is consumed through its metatype, binary-safe and Foundation-free")
	func conformanceDispatchShape() {
		// generated code is never referenced by name — `WebUIAsset(shipped:)` takes
		// `any WebUIShippedAsset.Type`. dispatch of the four members through that
		// existential is what the server will rely on, so it is pinned here.
		let typed: any WebUIShippedAsset.Type = StubAsset.self
		#expect(typed.body == Array(":root { --probe: 1 }\n".utf8), "the payload is `[UInt8]`, never `Data`")
		#expect(typed.gzip == nil, "a variant is optional: a build host without `gzip` still ships bytes")
		#expect(typed.contentType.hasPrefix("text/css"))
	}
}