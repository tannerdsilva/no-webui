import Foundation
import WebUI
import RAW_sha256
import RAW_argon2

// MARK: - Parameters

/// Argon2id cost parameters, persisted alongside the hash.
public struct Argon2Parameters: Sendable, Codable, Equatable, Hashable {
	/// OWASP-recommended interactive-work settings: 19 MiB, t=2, parallelism 1.
	public static let interactive = Argon2Parameters(timeCost: 2, memoryCostKiB: 19_456, parallelism: 1)
	/// higher-cost settings for privileged credentials or batch enrollment.
	public static let recommended = Argon2Parameters(timeCost: 3, memoryCostKiB: 65_536, parallelism: 4)

	public var timeCost: UInt32
	public var memoryCostKiB: UInt32
	public var parallelism: UInt32

	public init(timeCost: UInt32, memoryCostKiB: UInt32, parallelism: UInt32) {
		self.timeCost = timeCost
		self.memoryCostKiB = memoryCostKiB
		self.parallelism = parallelism
	}
}

// MARK: - PasswordRecord

/// a stored password hash: salt + hash + the exact parameters used, carried
/// together so verification never guesses parameters.
public struct PasswordRecord: Sendable, Codable, Equatable {
	public var salt: Data
	public var hash: Data
	public var parameters: Argon2Parameters

	public init(salt: Data, hash: Data, parameters: Argon2Parameters) {
		self.salt = salt
		self.hash = hash
		self.parameters = parameters
	}

	/// PHC-shaped self-describing encoding:
	/// `$argon2id$v=19$m=<kiB>,t=<time>,p=<parallel>$<b64url salt>$<b64url hash>`
	public func encodedString() -> String {
		"$argon2id$v=19$m=\(parameters.memoryCostKiB),t=\(parameters.timeCost),p=\(parameters.parallelism)"
			+ "$\(PasswordVerifier.base64URLEncode(salt))"
			+ "$\(PasswordVerifier.base64URLEncode(hash))"
	}

	public init(encoded: String) throws {
		let segments = encoded.split(separator: "$", omittingEmptySubsequences: false)
		guard segments.count == 6,
		      segments[0] == "",
		      segments[1] == "argon2id",
		      segments[2].hasPrefix("v=") else {
			throw PasswordVerifier.VerifierError.malformedEncoding(encoded)
		}
		guard segments[3].hasPrefix("m="),
		      let m = UInt32(segments[3].dropFirst(2).split(separator: ",").first ?? ""),
		      segments[3].contains(",t="),
		      let t = UInt32(segments[3].split(separator: ",t=").last?.prefix(while: { $0 != "," }) ?? ""),
		      segments[3].contains(",p="),
		      let p = UInt32(segments[3].split(separator: ",p=").last ?? "") else {
			throw PasswordVerifier.VerifierError.malformedEncoding(encoded)
		}
		guard let saltData = PasswordVerifier.base64URLDecode(String(segments[4])),
		      let hashData = PasswordVerifier.base64URLDecode(String(segments[5])) else {
			throw PasswordVerifier.VerifierError.malformedEncoding(encoded)
		}
		self.salt = saltData
		self.hash = hashData
		self.parameters = Argon2Parameters(timeCost: t, memoryCostKiB: m, parallelism: p)
	}
}

// MARK: - PasswordVerifier

/// Argon2id hashing and verification built on rawdog's `RAW_argon2`.
///
/// verification is hand-built (rawdog exposes hash-with-parameters only), so
/// it is deliberately strict: parameters round-trip through `PasswordRecord`
/// and are never inferred.
public enum PasswordVerifier {

	public enum VerifierError: Swift.Error, Equatable, Sendable {
		case entropyUnavailable
		case malformedEncoding(String)
	}

	// MARK: salt

	/// a fresh 16-byte salt from the OS entropy source only.
	public static func makeSalt(length: Int = 16) throws -> Data {
		guard let bytes = SecureRandom.bytes(length) else {
			throw VerifierError.entropyUnavailable
		}
		return Data(bytes)
	}

	// MARK: hash / verify

	public static func hash(password: [UInt8], salt: [UInt8], parameters: Argon2Parameters) throws -> Data {
		// `RAW_sha256.Hash` is a 32-byte rawdog static buffer with the required
		// `RAW_staticbuff` conformance — reused here as the Argon2id tag output
		// type (the bytes are just a fixed-size tag; the type name is semantic
		// provenance only).
		let output: RAW_sha256.Hash = try RAW_argon2.ID.hash(
			password: consume password,
			salt: salt,
			timeCost: parameters.timeCost,
			memoryCost: parameters.memoryCostKiB,
			parallelism: parameters.parallelism,
			as: RAW_sha256.Hash.self
		)
		return Data(output.RAW_access { buffer in
			[UInt8](buffer)
		})
	}

	public static func verify(password: [UInt8], record: PasswordRecord) throws -> Bool {
		let computed = try hash(password: password, salt: [UInt8](record.salt), parameters: record.parameters)
		return constantTimeEquals(computed, record.hash)
	}

	// MARK: dummy hash

	private static let dummyPasswordString = "webuiauth-dummy-password-do-not-use"

	/// a hash produced with the same cost as a real one, for unknown users.
	/// verifying a real credential against it always fails, but the KDF runs
	/// either way, equalizing the timing of "user exists" vs "user unknown".
	public static func dummyRecord(parameters: Argon2Parameters = .interactive) throws -> PasswordRecord {
		let salt = try makeSalt()
		let hash = try hash(password: [UInt8](dummyPasswordString.utf8), salt: [UInt8](salt), parameters: parameters)
		return PasswordRecord(salt: salt, hash: hash, parameters: parameters)
	}

	// MARK: base64url

	static func base64URLEncode(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	static func base64URLDecode(_ string: String) -> Data? {
		var normalized = string
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		let remainder = normalized.count % 4
		if remainder != 0 {
			normalized += String(repeating: "=", count: 4 - remainder)
		}
		return Data(base64Encoded: normalized)
	}
}
