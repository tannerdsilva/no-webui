import Foundation
import Testing
import WebUIBuild

// MARK: - the promoted gzip helpers
//
// these are the bytes a client receives: the framework's own tool and a consumer's tool
// both call through here, so the flags, the determinism rule and the failure shape are
// asserted once, against an independent known-answer vector rather than against the
// helper's own output.

@Suite("build gzip helpers")
struct GzipTests {

	static let probePlain = ".probe{color:teal}"
	/// `printf '.probe{color:teal}' | gzip -n -9 -c` — 38 bytes, produced outside this
	/// package. the header carries no timestamp and no name (`-n`) and the compression
	/// flags say level 9 (`0x02`), so this doubles as the determinism vector: if the
	/// helper's flags drift (a header mtime, a name, a lower level), it stops matching.
	static let probeGzip: [UInt8] = [
		0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03,
		0xd3, 0x2b, 0x28, 0xca, 0x4f, 0x4a, 0xad, 0x4e, 0xce, 0xcf,
		0xc9, 0x2f, 0xb2, 0x2a, 0x49, 0x4d, 0xcc, 0xa9, 0x05, 0x00,
		0x19, 0xff, 0x10, 0x08, 0x12, 0x00, 0x00, 0x00,
	]

	@Test("a payload compresses to the known gzip bytes (the `-n -9` rule)")
	func knownAnswer() throws {
		let out = try #require(gzip(Data(Self.probePlain.utf8)))
		#expect(Array(out) == Self.probeGzip)
		#expect(Array(out.prefix(4)) == [0x1f, 0x8b, 0x08, 0x00])
	}

	@Test("the string overload agrees with the byte overload")
	func stringOverloadAgrees() throws {
		let viaText = try #require(gzip(Self.probePlain))
		let viaBytes = try #require(gzip(Data(Self.probePlain.utf8)))
		#expect(viaText == viaBytes)
	}

	@Test("two runs on the same input are byte-identical — no timestamp, no name")
	func deterministic() throws {
		// larger than a pipe buffer, so the temporary-file route is exercised at size too.
		let payload = String(repeating: ":root { --token: 1 }\n", count: 8_000)
		let first = try #require(gzip(payload))
		let second = try #require(gzip(payload))
		#expect(first == second)
		#expect(first.count < payload.utf8.count, "the point of the variant is that it is smaller")
	}

	@Test("an empty payload is nil-safe and still a valid stream")
	func emptyPayload() throws {
		let out = try #require(gzip(Data()), "the helper must not crash or lie on empty input")
		#expect(Array(out.prefix(4)) == [0x1f, 0x8b, 0x08, 0x00])
		// the independent instrument: the bytes must inflate back to empty.
		#expect(try gunzip(out).isEmpty)
	}

	/// an independent `gunzip -c` over the helper's bytes — never the helper's own logic.
	private func gunzip(_ data: Data) throws -> Data {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["gunzip", "-c"]
		let input = Pipe()
		let output = Pipe()
		process.standardInput = input
		process.standardOutput = output
		try process.run()
		input.fileHandleForWriting.write(data)
		try input.fileHandleForWriting.close()
		let inflated = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return inflated
	}
}