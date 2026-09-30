import Foundation
import Testing

// integration test for the prose guard's build-time refusal: the asset tool must
// fail, naming the file and line, when a payload would ship a comment. the
// scanner's own cases live in `ProseGuardTests`; what is asserted here is the
// contract the plugin and a build actually see — exit code and message.
struct ProseGuardCLITests {

	static var toolAvailable: Bool { toolURL() != nil }
	static let unavailable: Comment = "WebUIAssetTool not built — run `swift build` first"

	static func toolURL() -> URL? {
		let root = ".build/out/Products"
		if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
			for dir in entries.sorted() {
				let candidate = root + "/" + dir + "/WebUIAssetTool"
				if FileManager.default.isExecutableFile(atPath: candidate) {
					return URL(fileURLWithPath: candidate)
				}
			}
		}
		for legacy in [".build/debug/WebUIAssetTool", ".build/release/WebUIAssetTool"] {
			if FileManager.default.isExecutableFile(atPath: legacy) {
				return URL(fileURLWithPath: legacy)
			}
		}
		return nil
	}

	func runTool(_ args: [String]) throws -> (status: Int32, out: String) {
		let url = try #require(Self.toolURL(), "\(Self.unavailable)")
		let process = Process()
		process.executableURL = url
		process.arguments = args
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	func scratch() throws -> String {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("webui-prose-\(UUID().uuidString)")
		try FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
		return dir.path
	}

	func write(_ text: String, to path: String) throws {
		try text.write(toFile: path, atomically: true, encoding: .utf8)
	}

	@Test("a comment in a js payload fails the build, naming file and line",
	      .enabled(if: toolAvailable))
	func jsProseFailsBuild() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		try write(":root {\n\t--alpha: 1;\n}\n", to: dir + "/in.css")
		try write("var a = 1;\n// prose would ship\nvar b = 2;\n", to: dir + "/in.js")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--js-input", dir + "/in.js",
			"--output", dir + "/out.swift",
		])
		#expect(result.status != 0, "a prose payload must not build: \(result.out)")
		#expect(result.out.contains("in.js:2:"), "the failure names file and line: \(result.out)")
		#expect(result.out.contains("prose would ship"), "the failure quotes the prose: \(result.out)")
	}

	@Test("a `//` inside a string does not fail the build",
	      .enabled(if: toolAvailable))
	func urlInStringBuilds() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		try write(":root {\n\t--alpha: 1;\n}\n", to: dir + "/in.css")
		try write("var wsUrl = 'ws://' + location.host;\n", to: dir + "/in.js")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--js-input", dir + "/in.js",
			"--output", dir + "/out.swift",
		])
		#expect(result.status == 0, "a url is not prose: \(result.out)")
	}

	@Test("a comment left in the minified sheet fails the build",
	      .enabled(if: toolAvailable))
	func cssCommentSurvivesMinifyFailsBuild() throws {
		// the working file's notes are stripped by `minifyCSS`; this payload is the
		// minified output, so a comment here means the strip missed one.
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		try write(":root {\n\t--alpha: 1;\n}\n", to: dir + "/in.css")
		try write("// note\n", to: dir + "/engine.js")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--engine-input", dir + "/engine.js",
			"--output", dir + "/out.swift",
		])
		#expect(result.status != 0, "the engine payload is a shipped surface: \(result.out)")
		#expect(result.out.contains("engine.js:1:"), "the failure names file and line: \(result.out)")
	}
}