import Foundation
import RAW
import RAW_hmac
import RAW_sha256
import WebUICore

#if os(Linux)
import Glibc
#else
import Security
#endif

// MARK: - HMAC-SHA256

// thin facade over rawdog's official crypto suite (RAW_sha256 + RAW_hmac,
// v21+). the framework delegates to it instead of carrying its own
// implementation; outputs are pinned byte-for-byte against the rfc 4231
// vectors in Tests/WebUITests/CryptoTests.swift.
public enum HMACSHA256 {
	public static func authenticate(message: [UInt8], with key: [UInt8]) throws -> [UInt8] {
		var hmac = try RAW_hmac.HMAC<RAW_sha256.Hasher>(key: key)
		try hmac.update(message: message)
		var digest = [UInt8](repeating: 0, count: 32)
		// the buffer is non-empty, so its base address is never nil; a nil base
		// would mean the hasher and the buffer disagree about the digest size,
		// which must fail loudly rather than yield an all-zero digest.
		let finished = try digest.withUnsafeMutableBytes { buffer -> Bool in
			guard let base = buffer.baseAddress else { return false }
			try hmac.finish(into: base)
			return true
		}
		precondition(finished, "HMAC-SHA256 digest buffer has no base address")
		return digest
	}

	public static func hex(message: [UInt8], key: [UInt8]) throws -> String {
		bytesToHex(try authenticate(message: message, with: key))
	}

	public static func hex(message: String, key: String) throws -> String? {
		try hex(message: [UInt8](message.utf8), key: [UInt8](key.utf8))
	}
}

// MARK: - SHA-256

/// plain sha-256 over rawdog's implementation. it exists because `CryptoKit`
/// is apple-only: the design system hashes its stylesheet into a content
/// address, and that hash has to be computable on linux too. the digest is
/// identical to any conforming implementation, so addresses derived from it
/// are stable across platforms.
public enum SHA256 {
	/// lowercase hex of `sha256(bytes)`.
	public static func hex(_ bytes: [UInt8]) -> String {
		var hasher = RAW_sha256.Hasher()
		bytes.withUnsafeBytes { buffer in
			hasher.update(buffer)
		}
		var out = [UInt8](repeating: 0, count: 32)
		// `finish(into:)` fails only on a buffer-size mismatch, and 32 bytes is
		// exactly the sha-256 digest size: a failure means the hasher contract
		// moved underneath us. fail loudly — a silently truncated digest would
		// mint a wrong content address for the stylesheet.
		let finished = out.withUnsafeMutableBytes { buffer -> Bool in
			guard let base = buffer.baseAddress else { return false }
			do {
				try hasher.finish(into: base)
				return true
			} catch {
				return false
			}
		}
		precondition(finished, "RAW_sha256.finish failed on a 32-byte buffer")
		return bytesToHex(out)
	}
}

// MARK: - Byte helpers

public func bytesToHex(_ bytes: [UInt8]) -> String {
	let table = Array("0123456789abcdef".utf8)
	var out = [UInt8]()
	out.reserveCapacity(bytes.count * 2)
	for byte in bytes {
		out.append(table[Int(byte >> 4)])
		out.append(table[Int(byte & 0x0f)])
	}
	return String(decoding: out, as: UTF8.self)
}

// MARK: - Secure Random

// cryptographically secure random bytes: /dev/urandom on linux, getrandom is
// not exposed by every swift linux sdk's glibc module map; SecRandomCopyBytes
// on apple platforms. a thin os-entropy wrapper — no algorithm implemented
// here.
public enum SecureRandom {
	/// `count` fresh random bytes, or `nil` when the platform source fails.
	public static func bytes(_ count: Int) -> [UInt8]? {
		guard count > 0 else { return count == 0 ? [] : nil }
		var out = [UInt8](repeating: 0, count: count)
		#if os(Linux)
		// O_CLOEXEC: the entropy descriptor must never leak into a spawned child.
		let fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC)
		guard fd >= 0 else { return nil }
		defer { close(fd) }
		var offset = 0
		while offset < count {
			let n = read(fd, &out[offset], count - offset)
			if n < 0 {
				if errno == EINTR { continue }
				return nil
			}
			if n == 0 { return nil }
			offset += n
		}
		return out
		#else
		let status = out.withUnsafeMutableBytes { (ptr) -> Int32 in
			// non-empty buffer ⇒ non-nil base address; treat a nil base like an
			// entropy failure, which is what this function's optional reports.
			guard let base = ptr.baseAddress else { return errSecParam }
			return SecRandomCopyBytes(kSecRandomDefault, count, base)
		}
		guard status == errSecSuccess else { return nil }
		return out
		#endif
	}
}

// MARK: - Secure Random Source

/// the entropy source, as an injectable value.
///
/// `SecureRandom` is the platform call; this protocol is the same shape a
/// caller can substitute so a test can make entropy *fail* — the one condition
/// that must produce a degraded render rather than a tokenless page — without
/// a process-wide switch. the render token is the only consumer today.
public protocol SecureRandomSource: Sendable {
	/// `count` fresh bytes, or `nil` when the source cannot produce them.
	func bytes(_ count: Int) -> [UInt8]?
}

/// the platform source: `/dev/urandom` on linux, `SecRandomCopyBytes` on apple
/// platforms — exactly ``SecureRandom/bytes(_:)``.
public struct SystemSecureRandom: SecureRandomSource {
	public init() {}

	public func bytes(_ count: Int) -> [UInt8]? {
		SecureRandom.bytes(count)
	}
}

extension SecureRandomSource where Self == SystemSecureRandom {
	/// the production source, spelled so a defaulted parameter can say
	/// `.system` and mean today's behaviour.
	public static var system: SystemSecureRandom { SystemSecureRandom() }
}

// MARK: - Strict entropy

// the failure shape a render owner needs: `bytes` reports `nil` and the caller
// has to decide. `requireBytes` is the decision already made — no token, no
// page — so a render that cannot be token-bound fails as `entropyUnavailable`
// instead of shipping a tokenless page (design C, §7.2 rule 4).

extension SecureRandomSource {
	/// `count` fresh bytes from this source, or
	/// ``WebUIFailure/entropyUnavailable``.
	///
	/// this is the loud door every render path should use: a `nil` from
	/// ``bytes(_:)`` is a *failure*, not a value to paper over with an empty
	/// token, which would make every event on the page unroutable while the
	/// page itself looked fine.
	public func requireBytes(_ count: Int) throws -> [UInt8] {
		guard let bytes = bytes(count) else { throw WebUIFailure.entropyUnavailable }
		return bytes
	}
}

extension SecureRandom {
	/// `count` bytes from `source`, or ``WebUIFailure/entropyUnavailable``.
	///
	/// the sibling of ``SecureRandom/bytes(_:)`` that fails loudly, so a caller
	/// that must not degrade (a render minting its token) writes one `try`
	/// instead of an `if let` whose `else` is easy to leave empty.
	public static func requireBytes(
		_ count: Int,
		using source: any SecureRandomSource = .system
	) throws -> [UInt8] {
		try source.requireBytes(count)
	}
}
