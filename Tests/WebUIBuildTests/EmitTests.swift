import Foundation
import Testing
import WebUIBuild

// MARK: - the emitter
//
// `emit(shipped:)` turns one payload into one `WebUIShippedAsset` type — the shape a
// consumer's build tool writes and the consumer's server serves. the tests reconstruct the
// payload out of the emitted source (base64 is mechanically extractable, which is the point
// of the encoding: no escaping can silently change bytes) and inflate the emitted variant
// with an independent `gunzip`.

@Suite("asset emitter")
struct EmitTests {

	static let payload = ":root { --probe: 1 }\n/* probe */\n"
	/// the payload's sha256 prefix, measured outside this package:
	/// `printf ':root { --probe: 1 }\n/* probe */\n' | shasum -a 256`
	static let expectedStamp = "8c8581e09ea5"

	// MARK: tests

	@Test("writes a WebUIShippedAsset type carrying the payload, its address and its variant")
	func emitsTheType() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }
		let out = dir.appendingPathComponent("ProbeAsset.swift")

		let receipt = try WebUIAssetBuilder.emit(
			shipped: Self.payload,
			typeName: "ProbeAsset",
			options: .init(contentType: "text/css; charset=utf-8"),
			to: out
		)

		// the receipt: what shipped, and how big.
		#expect(receipt.typeName == "ProbeAsset")
		#expect(receipt.bytes == Self.payload.utf8.count)
		#expect((receipt.gzipBytes ?? 0) > 0, "a build host with `gzip` produces a variant")
		#expect(receipt.stamp == Self.expectedStamp)

		let source = try String(contentsOf: out, encoding: .utf8)
		#expect(source.contains("import WebUICore"))
		#expect(source.contains("public enum ProbeAsset: WebUIShippedAsset"))
		#expect(source.contains("contentType = \"text/css; charset=utf-8\""))
		#expect(source.contains("stamp = \"\(Self.expectedStamp)\""))
		#expect(source.contains("public static var text: String"), "text entries carry the inline convenience")

		// the payload decodes out of the source, byte for byte…
		let body = try extractBase64Literal(source, label: "bodyBase64")
		#expect(Array(body) == Array(Self.payload.utf8))
		// …and the emitted variant inflates to the same bytes.
		let variant = try extractBase64Literal(source, label: "gzipBase64")
		#expect(try gunzipIndependently(variant) == Data(Self.payload.utf8))
	}

	@Test("two runs are byte-identical")
	func deterministic() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }
		let first = dir.appendingPathComponent("One.swift")
		let second = dir.appendingPathComponent("Two.swift")

		for url in [first, second] {
			_ = try WebUIAssetBuilder.emit(
				shipped: Self.payload, typeName: "ProbeAsset",
				options: .init(contentType: "text/css; charset=utf-8"), to: url
			)
		}
		#expect(try Data(contentsOf: first) == (try Data(contentsOf: second)))
	}

	@Test("a type name that is not an identifier is refused, naming itself")
	func refusesInvalidTypeName() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }

		do {
			_ = try WebUIAssetBuilder.emit(
				shipped: Self.payload, typeName: "Not A Name",
				options: .init(contentType: "text/css; charset=utf-8"),
				to: dir.appendingPathComponent("Bad.swift")
			)
			Issue.record("a non-identifier type name must not reach generated code")
		} catch let error as WebUIBuildError {
			#expect(error.description.contains("Not A Name"))
		}
	}
}