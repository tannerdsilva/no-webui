import Foundation
import Testing

// integration tests for `WebUIWasmTool` (the build-tool plugin's executable):
// ran as a subprocess against both a synthetic wasm artifact and --missing,
// so the plugin's generated carrier contract is pinned independently of the
// SwiftPM plugin wiring.
struct WebUIWasmToolTests {
	// a minimal valid wasm binary: magic "\0asm" + version 1 + one empty type
	// section (section id 1, size 1: count 0) — structurally parseable.
	static let validWasm: [UInt8] = [
		0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,  // magic + version 1
		0x01, 0x01, 0x00,                                // type section, size 1, 0 types
	]

	static let badMagicWasm: [UInt8] = [
		0x00, 0x61, 0x73, 0x6D, 0x02, 0x00, 0x00, 0x00,  // version 2
	]

	/// the tool is a build product, so `swift test` without `swift build`
	/// legitimately leaves it absent. every test carries this as an
	/// `.enabled(if:)` trait — one mechanism, so a new test cannot forget a
	/// guard and abort the runner (which is how this target used to die on linux).
	static var toolAvailable: Bool { toolURL() != nil }
	static let unavailable: Comment = "WebUIWasmTool not built — run `swift build` first"

	static func toolURL() -> URL? {
		// scanned, not hard-coded: the product directory carries a platform
		// suffix on linux (`Debug-linux-x86_64`) and on cross targets, so a fixed
		// `.build/out/Products/Debug/...` path resolves to nil there — and a nil
		// `Process.executableURL` is a fatalError *inside Foundation*, which
		// aborts the whole test runner instead of failing one test.
		let root = ".build/out/Products"
		if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
			for dir in entries.sorted() {
				let candidate = root + "/" + dir + "/WebUIWasmTool"
				if FileManager.default.isExecutableFile(atPath: candidate) {
					return URL(fileURLWithPath: candidate)
				}
			}
		}
		// legacy layout, for older SwiftPM
		for legacy in [".build/debug/WebUIWasmTool", ".build/release/WebUIWasmTool"] {
			if FileManager.default.isExecutableFile(atPath: legacy) {
				return URL(fileURLWithPath: legacy)
			}
		}
		return nil
	}

	func runTool(_ args: [String]) throws -> (status: Int32, out: String) {
		// `#require` rather than assignment: a missing tool must be a clean test
		// failure, never a Foundation trap.
		let url = try #require(Self.toolURL(), "\(Self.unavailable)")
		let process = Process()
		process.executableURL = url
		process.arguments = args
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		process.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
	}

	// MARK: -

	@Test("--missing emits an absent carrier with empty sha and zero count", .enabled(if: toolAvailable, unavailable))
	func missingCarrier() throws {
		let tmp = NSTemporaryDirectory() + "wasm-tool-missing-\(UUID().uuidString).swift"
		defer { try? FileManager.default.removeItem(atPath: tmp) }
		let (status, out) = try runTool(["--missing", "--output", tmp])
		#expect(status == 0)
		#expect(out.contains("absent carrier"))
		let text = try String(contentsOfFile: tmp, encoding: .utf8)
		#expect(text.contains("public static let present = false"))
		#expect(text.contains("public static let sha256 = \"\""))
		#expect(text.contains("public static let byteCount = 0"))
	}

	@Test("a valid artifact produces a present carrier with matching sha and count", .enabled(if: toolAvailable, unavailable))
	func validArtifactCarrier() throws {
		let tmp = NSTemporaryDirectory() + "wasm-tool-valid-\(UUID().uuidString)"
		let wasmPath = tmp + ".wasm"
		let swiftPath = tmp + ".swift"
		defer {
			try? FileManager.default.removeItem(atPath: wasmPath)
			try? FileManager.default.removeItem(atPath: swiftPath)
		}
		try Data(Self.validWasm).write(to: URL(fileURLWithPath: wasmPath))
		let (status, out) = try runTool(["--wasm-input", wasmPath, "--output", swiftPath, "--product", "ProbeClient"])
		#expect(status == 0)
		#expect(out.contains("validated + hashed"))
		let text = try! String(contentsOfFile: swiftPath, encoding: .utf8)
		#expect(text.contains("public static let present = true"))
		#expect(text.contains("public static let byteCount = \(Self.validWasm.count)"))
		#expect(text.contains("public static let product = \"ProbeClient\""))
		// sha must be the sha-256 of the synthetic artifact
		let sha = text.split(separator: "\"").map(String.init).first { $0.count == 64 }
		#expect(sha != nil)
	}

	@Test("a corrupt artifact fails the tool (build-time integrity gate)", .enabled(if: toolAvailable, unavailable))
	func corruptArtifactFails() throws {
		let tmp = NSTemporaryDirectory() + "wasm-tool-bad-\(UUID().uuidString)"
		let wasmPath = tmp + ".wasm"
		let swiftPath = tmp + ".swift"
		defer {
			try? FileManager.default.removeItem(atPath: wasmPath)
			try? FileManager.default.removeItem(atPath: swiftPath)
		}
		try Data(Self.badMagicWasm).write(to: URL(fileURLWithPath: wasmPath))
		let (status, out) = try runTool(["--wasm-input", wasmPath, "--output", swiftPath])
		#expect(status != 0)
		#expect(out.contains("version"))
	}

	@Test("a missing file fails the tool (never emits a stale carrier)", .enabled(if: toolAvailable, unavailable))
	func missingFileFails() throws {
		let (status, out) = try runTool(["--wasm-input", "/nonexistent/x.wasm", "--output", "/tmp/x.swift"])
		#expect(status != 0)
		#expect(out.contains("cannot read"))
	}

	// MARK: - strip mode (`--strip-input` / `--strip-output`)

	// a wasm with a custom section (id 0) interleaved between two non-custom
	// sections: custom ("name" — 0x00) then type (0x01) then function (0x03).
	// header + 3 sections, each with (id, leb128 size, payload).
	static let wasmWithCustom: [UInt8] = {
		var out: [UInt8] = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]
		// custom section id 0, size 6, payload = name length (5) + "hello"
		out += [0x00, 0x06, 0x05, 0x68, 0x65, 0x6C, 0x6C, 0x6F]
		// type section id 1, size 1 (0 types)
		out += [0x01, 0x01, 0x00]
		// function section id 3, size 1 (0 fields)
		out += [0x03, 0x01, 0x00]
		return out
	}()

	@Test("strip removes custom sections but preserves header + non-custom sections", .enabled(if: toolAvailable, unavailable))
	func stripRemovesCustomKeepsRest() throws {
		let tmp = NSTemporaryDirectory() + "wasm-tool-strip-\(UUID().uuidString)"
		let inPath = tmp + ".wasm"
		let outPath = tmp + "-out.wasm"
		defer {
			try? FileManager.default.removeItem(atPath: inPath)
			try? FileManager.default.removeItem(atPath: outPath)
		}
		try Data(Self.wasmWithCustom).write(to: URL(fileURLWithPath: inPath))
		let (status, out) = try runTool(["--strip-input", inPath, "--strip-output", outPath])
		#expect(status == 0)
		#expect(out.contains("stripped 8 bytes"))
		let stripped = try Data(contentsOf: URL(fileURLWithPath: outPath))
		// custom section = id + size + 6 payload = 8 bytes removed
		#expect(stripped.count == Self.wasmWithCustom.count - 8)
		// stripped == header + type section + function section, verbatim
		let expected = [UInt8](Self.wasmWithCustom[0..<8]) + [0x01, 0x01, 0x00] + [0x03, 0x01, 0x00]
		#expect(Array(stripped) == expected)
		// stripped must NOT contain the custom "hello" payload
		#expect(String(decoding: stripped, as: UTF8.self).contains("hello") == false)
	}

	@Test("strip is a no-op on an artifact with no custom sections", .enabled(if: toolAvailable, unavailable))
	func stripNoCustomIsNoop() throws {
		let tmp = NSTemporaryDirectory() + "wasm-tool-stripn-\(UUID().uuidString)"
		let inPath = tmp + ".wasm"
		let outPath = tmp + "-out.wasm"
		defer {
			try? FileManager.default.removeItem(atPath: inPath)
			try? FileManager.default.removeItem(atPath: outPath)
		}
		try Data(Self.validWasm).write(to: URL(fileURLWithPath: inPath))
		let (status, _) = try runTool(["--strip-input", inPath, "--strip-output", outPath])
		#expect(status == 0)
		let stripped = try Data(contentsOf: URL(fileURLWithPath: outPath))
		#expect(Array(stripped) == Self.validWasm)
	}
}
