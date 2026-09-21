import Foundation
import Testing
@testable import WebUI

// the `WebUIWasmPlugin` build-tool plugin emits `WebUIWasmInfo` during every
// host build from the prebuilt wasm client artifact. this suite pins the
// contract: the carrier must agree with the artifact on disk (presence, byte
// count, sha-256) so a host build can never disagree with what a server would
// serve — the immutable-cache url is derived from the same bytes either way.
struct WasmCarrierTests {
	private static let artifactPath = ".build/out/Products/Release-webassembly-wasm32/WebUIClient.wasm"

	private static func readArtifact() throws -> [UInt8] {
		let fd = open(artifactPath, O_RDONLY)
		if fd < 0 { return [] }
		defer { close(fd) }
		var st = stat()
		guard fstat(fd, &st) == 0, st.st_size > 0 else { return [] }
		let size = Int(st.st_size)
		var bytes = [UInt8](repeating: 0, count: size)
		let n = bytes.withUnsafeMutableBytes { buf in
			read(fd, buf.baseAddress, size)
		}
		return n == size ? bytes : []
	}

	private static func hex(_ bytes: [UInt8]) -> String {
		bytes.map { String(format: "%02x", $0) }.joined()
	}

	@Test("the generated carrier agrees with the on-disk artifact (presence)")
	func carrierPresenceMatchesDisk() throws {
		let bytes = try Self.readArtifact()
		#expect(WebUIWasmInfo.present == !bytes.isEmpty)
	}

	@Test("the carrier's byte count equals the artifact's")
	func carrierByteCountMatchesDisk() throws {
		let bytes = try Self.readArtifact()
		guard !bytes.isEmpty else { return }  // absent artifact: carrier says 0
		#expect(WebUIWasmInfo.byteCount == bytes.count)
	}

	@Test("the carrier's sha-256 matches the artifact (so hashed url == served bytes)")
	func carrierShaMatchesDisk() throws {
		let bytes = try Self.readArtifact()
		guard !bytes.isEmpty else { return }
		#expect(WebUIWasmInfo.sha256 == WebUIBoot.wasmHash(of: bytes))
		#expect(WebUIWasmInfo.sha256.count == 64)
	}

	@Test("WebUIBoot exposes the carrier to hosts without re-reading the artifact")
	func bootExposesCarrier() {
		let sha = WebUIBoot.wasmSHA256
		#expect((sha.isEmpty && !WebUIBoot.wasmAvailable) || (!sha.isEmpty && WebUIBoot.wasmAvailable))
		#expect(WebUIBoot.wasmProductURL() == nil || WebUIBoot.wasmProductURL()!.lastPathComponent == "WebUIClient.wasm")
	}

	@Test("the product-name overload resolves consumer artifacts under their own name")
	func productNameOverloadResolves() {
		// the framework artifact exists (or not) under WebUIClient; the overload
		// must never fabricate a url for an arbitrary name.
		let resolved = WebUIBoot.wasmProductURL(productName: "ConsumerClient")
		if resolved != nil {
			#expect(resolved!.lastPathComponent == "ConsumerClient.wasm")
		}
	}
}
