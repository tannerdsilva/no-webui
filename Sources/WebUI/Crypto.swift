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
		var hmac = try RAW_hmac.HMAC<RAW_sha256.Hasher<RAW_sha256.Hash>>(key: key)
		try hmac.update(message: message)
		var digest = [UInt8](repeating: 0, count: 32)
		try digest.withUnsafeMutableBytes { buffer in
			try hmac.finish(into: buffer.baseAddress!)
		}
		return digest
	}

	public static func hex(message: [UInt8], key: [UInt8]) throws -> String {
		bytesToHex(try authenticate(message: message, with: key))
	}

	public static func hex(message: String, key: String) throws -> String? {
		guard let keyData = key.data(using: .utf8),
		      let messageData = message.data(using: .utf8) else {
			return nil
		}
		return try hex(message: [UInt8](messageData), key: [UInt8](keyData))
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
		let fd = open("/dev/urandom", O_RDONLY)
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
			SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
		}
		guard status == errSecSuccess else { return nil }
		return out
		#endif
	}
}
