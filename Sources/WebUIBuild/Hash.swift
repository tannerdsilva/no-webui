import RAW
import RAW_sha256

// MARK: - sha-256 (build-side)
//
// deliberately local. the plugin → tool → library chain cannot depend on WebUI: WebUI's own
// asset plugin invokes `WebUIAssetTool`, which depends on this library, so a WebUI
// dependency here is a manifest cycle SwiftPM refuses. WebUICore — the plan's proposed home
// for `SHA256` — must stay rawdog-free, because the client build reaches `DesignToken`
// through it precisely to avoid rawdog. the plan deferred the relocation as "harmless
// today"; the cycle proves the deferral's premise wrong, and this facade is the smallest
// legal shape: rawdog's primitive, no public surface, one function.
//
// the digest is the dependency's, not ours; the emitter's stamp is pinned against an
// external vector (`shasum -a 256`) in `WebUIBuildTests`, so a wrong facade fails a test
// rather than minting wrong addresses.

/// lowercase hex of `sha256(bytes)`.
func sha256Hex(_ bytes: [UInt8]) -> String {
	var hasher = RAW_sha256.Hasher()
	bytes.withUnsafeBytes { buffer in
		hasher.update(buffer)
	}
	var digest = [UInt8](repeating: 0, count: 32)
	// `finish(into:)` fails only on a buffer-size mismatch, and 32 bytes is exactly the
	// sha-256 digest size: a failure means the hasher contract moved underneath us. fail
	// loudly — a silently truncated digest would mint a wrong content address.
	let finished = digest.withUnsafeMutableBytes { buffer -> Bool in
		guard let base = buffer.baseAddress else { return false }
		do {
			try hasher.finish(into: base)
			return true
		} catch {
			return false
		}
	}
	precondition(finished, "RAW_sha256.finish failed on a 32-byte buffer")
	let table = Array("0123456789abcdef".utf8)
	var out: [UInt8] = []
	out.reserveCapacity(digest.count * 2)
	for byte in digest {
		out.append(table[Int(byte >> 4)])
		out.append(table[Int(byte & 0x0f)])
	}
	return String(decoding: out, as: UTF8.self)
}