import Foundation
import RAW
import RAW_hmac
import RAW_sha256

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
