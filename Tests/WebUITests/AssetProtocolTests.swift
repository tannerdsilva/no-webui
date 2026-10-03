import Foundation
import Testing
import WebUI
import WebUICore
import WebUIServer

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

	/// the compressed shape: a body/gzip pair whose bytes are the shared wire fixture, so
	/// the server test can assert both variants byte-for-byte.
	struct CompressedStub: WebUIShippedAsset {
		static let contentType = "text/css; charset=utf-8"
		static let body: [UInt8] = Array(probePlain.utf8)
		static let stamp = "b9fe308ce259"
		static let gzip: [UInt8]? = probeGzip
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

	@Test("a shipped asset's bytes and variant arrive under its own stamp")
	func shippedAssetServes() async throws {
		let asset = WebUIAsset(CompressedStub.self, path: "/ui/stub.css")
		// in-contract, the published literal and the recomputed digest agree — the address
		// the wire carries is the stub's own stamp, and the registration is the bare path.
		#expect(asset.stamp == CompressedStub.stamp)
		#expect(asset.url == "/ui/stub.css?v=b9fe308ce259")
		#expect(asset.registration.path == "/ui/stub.css")

		try await withServer(
			requestRender: { _ in "<p>page</p>" },
			router: EventRouter(),
			assets: [asset.registration],
			portBase: 24000
		) { port in
			// the published address answers with the payload bytes…
			let (headers, body) = try await rawGET(
				"http://127.0.0.1:\(port)\(asset.url)", acceptEncoding: "identity"
			)
			#expect(headers.contains("200 OK"))
			#expect(String(decoding: body, as: UTF8.self) == probePlain)
			// …and the variant the conformance carried is what a gzip client gets.
			let (gzHeaders, gzBody) = try await rawGET(
				"http://127.0.0.1:\(port)\(asset.url)", acceptEncoding: "gzip"
			)
			#expect(gzHeaders.contains("Content-Encoding: gzip"))
			#expect(gzBody == Data(probeGzip))
		}
	}

	@Test("a drifted stamp literal cannot keep an old url alive in a year-long cache")
	func driftedLiteralCannotStaleTheUrl() {
		// out of contract by construction: the literal names bytes that are not these. the
		// server recomputes, so the failure stays where it belongs (the generator's own
		// round-trip tests) instead of reaching a cache as a url whose bytes changed.
		struct DriftedStub: WebUIShippedAsset {
			static let contentType = "text/css; charset=utf-8"
			static let body: [UInt8] = Array(":root { --probe: 2 }\n".utf8)
			static let stamp = "aaaa0000bbbb"
			static let gzip: [UInt8]? = nil
		}
		let asset = WebUIAsset(DriftedStub.self, path: "/ui/drift.css")
		#expect(asset.stamp == String(SHA256.hex(DriftedStub.body).prefix(12)))
		#expect(asset.stamp != DriftedStub.stamp)
	}
}