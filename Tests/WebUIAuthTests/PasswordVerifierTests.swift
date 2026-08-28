import Foundation
import Testing

@testable import WebUIAuth

@Suite("PasswordVerifier")
struct PasswordVerifierTests {

	@Test("salt is 16 bytes and unique")
	func salt() throws {
		let a = try PasswordVerifier.makeSalt()
		let b = try PasswordVerifier.makeSalt()
		#expect(a.count == 16)
		#expect(a != b)
	}

	@Test("hash is deterministic for identical inputs and 32 bytes")
	func hashDeterminism() throws {
		let salt = try PasswordVerifier.makeSalt()
		let h1 = try PasswordVerifier.hash(password: [UInt8]("hunter2".utf8), salt: [UInt8](salt), parameters: .interactive)
		let h2 = try PasswordVerifier.hash(password: [UInt8]("hunter2".utf8), salt: [UInt8](salt), parameters: .interactive)
		#expect(h1.count == 32)
		#expect(h1 == h2)
	}

	@Test("hash differs across salts and across passwords")
	func hashDiversity() throws {
		let saltA = try PasswordVerifier.makeSalt()
		let saltB = try PasswordVerifier.makeSalt()
		let ha = try PasswordVerifier.hash(password: [UInt8]("p".utf8), salt: [UInt8](saltA), parameters: .interactive)
		let hb = try PasswordVerifier.hash(password: [UInt8]("p".utf8), salt: [UInt8](saltB), parameters: .interactive)
		let hc = try PasswordVerifier.hash(password: [UInt8]("q".utf8), salt: [UInt8](saltA), parameters: .interactive)
		#expect(ha != hb)
		#expect(ha != hc)
	}

	@Test("verify accepts the correct password and rejects wrong ones")
	func verify() throws {
		let record = PasswordRecord(
			salt: try PasswordVerifier.makeSalt(),
			hash: Data(),
			parameters: .interactive
		)
		let hash = try PasswordVerifier.hash(password: [UInt8]("correct horse".utf8), salt: [UInt8](record.salt), parameters: .interactive)
		let full = PasswordRecord(salt: record.salt, hash: hash, parameters: .interactive)
		#expect(try PasswordVerifier.verify(password: [UInt8]("correct horse".utf8), record: full))
		#expect(try PasswordVerifier.verify(password: [UInt8]("battery staple".utf8), record: full) == false)
	}

	@Test("verify fails when parameters drift from the stored record")
	func parameterDrift() throws {
		let salt = try PasswordVerifier.makeSalt()
		let hash = try PasswordVerifier.hash(password: [UInt8]("p".utf8), salt: [UInt8](salt), parameters: .interactive)
		let drifted = PasswordRecord(
			salt: salt,
			hash: hash,
			parameters: Argon2Parameters(timeCost: 5, memoryCostKiB: 19_456, parallelism: 1)
		)
		#expect(try PasswordVerifier.verify(password: [UInt8]("p".utf8), record: drifted) == false)
	}

	@Test("dummy record costs a real hash but verifies against nothing")
	func dummyHash() throws {
		let dummy = try PasswordVerifier.dummyRecord()
		#expect(dummy.hash.count == 32)
		let realSalt = try PasswordVerifier.makeSalt()
		let realHash = try PasswordVerifier.hash(password: [UInt8]("real".utf8), salt: [UInt8](realSalt), parameters: .interactive)
		let real = PasswordRecord(salt: realSalt, hash: realHash, parameters: .interactive)
		#expect(try PasswordVerifier.verify(password: [UInt8]("real".utf8), record: dummy) == false)
		#expect(try PasswordVerifier.verify(password: [UInt8]("some guess".utf8), record: real) == false)
	}

	@Test("encoded string round-trips salt, hash, and parameters")
	func encodingRoundTrip() throws {
		let record = PasswordRecord(
			salt: try PasswordVerifier.makeSalt(),
			hash: Data(repeating: 0x5A, count: 32),
			parameters: .interactive
		)
		let decoded = try PasswordRecord(encoded: record.encodedString())
		#expect(decoded == record)
	}

	@Test("malformed encodings are rejected")
	func malformedEncodings() {
		#expect(throws: PasswordVerifier.VerifierError.self) {
			_ = try PasswordRecord(encoded: "not-a-valid-string")
		}
		#expect(throws: PasswordVerifier.VerifierError.self) {
			_ = try PasswordRecord(encoded: "$bcrypt$v=19$m=19456,t=2,p=1$AAAA$AAAA")
		}
		#expect(throws: PasswordVerifier.VerifierError.self) {
			_ = try PasswordRecord(encoded: "$argon2id$v=19$m=notanumber,t=2,p=1$AAAA$AAAA")
		}
	}
}
