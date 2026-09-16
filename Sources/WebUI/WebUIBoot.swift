import Foundation
import RAW
import RAW_sha256

/// server-side helpers for serving the wasm client artifact: locating the
/// release product and content-addressing it. the framework emits bytes via
/// `HTMLDocument(clientMode:)`; serving (routes, cache headers) is the host
/// server's job — these helpers make computing the `webui-wasm` url trivial.
public enum WebUIBoot {
	/// the release `WebUIClient.wasm` product url under `.build`, or `nil`
	/// when the artifact has not been built (the gates build it first).
	public static func wasmProductURL() -> URL? {
		let candidate = URL(fileURLWithPath: ".build/out/Products/Release-webassembly-wasm32/WebUIClient.wasm")
		return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
	}

	/// sha-256 lowercase hex over a byte string; an empty string signals "no
	/// bytes". used to content-address the artifact so the immutable-cache
	/// route is automatically cache-busted when the binary changes
	/// (`/__assets/app.<hash>.wasm`).
	public static func wasmHash(of bytes: [UInt8]) -> String {
		var hasher = RAW_sha256.Hasher()
		bytes.withUnsafeBytes { hasher.update($0) }
		var digest = [UInt8](repeating: 0, count: 32)
		do {
			try digest.withUnsafeMutableBytes { buffer in
				try hasher.finish(into: buffer.baseAddress!)
			}
			return bytesToHex(digest)
		} catch {
			return ""
		}
	}
}
