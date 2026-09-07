import WebUI
import RAW_sha256

// MARK: - Session token

/// opaque client-held session tokens.
///
/// `generate` draws 32 bytes exclusively from `SecureRandom` — it fails loudly
/// if the OS entropy source is unavailable and never falls back to a PRNG
/// (the `SystemRandomNumberGenerator` fallback elsewhere in the codebase is
/// deliberately unreachable from here).
public enum SessionToken {
	public static let byteCount = 32

	public enum TokenError: Error, Equatable, Sendable {
		/// the OS entropy source failed; no fallback was attempted.
		case entropyUnavailable
		/// the token has an invalid length for hashing.
		case invalidLength
	}

	/// generate a fresh 32-byte token.
	public static func generate() throws -> [UInt8] {
		guard let bytes = SecureRandom.bytes(byteCount) else {
			throw TokenError.entropyUnavailable
		}
		return bytes
	}

	/// the SHA-256 of a token — the only form a session store may persist.
	public static func hash(_ token: [UInt8]) throws -> [UInt8] {
		guard token.count == byteCount else {
			throw TokenError.invalidLength
		}
		var hasher = RAW_sha256.Hasher<RAW_sha256.Hash>()
		token.withUnsafeBytes { buffer in
			hasher.update(buffer)
		}
		var out = [UInt8](repeating: 0, count: 32)
		try out.withUnsafeMutableBytes { buffer in
			try hasher.finish(into: buffer.baseAddress!)
		}
		return out
	}
}
