import Foundation
import Testing

// MARK: - the asset tool's CLI harness
//
// the tool is a build product, so `swift test` without `swift build` legitimately leaves it
// absent; every CLI suite carries `assetToolAvailable` as an `.enabled(if:)` trait, so a
// missing tool is a skip and never a Foundation trap inside `Process`. file-scope internal:
// the CLI suites share one locator, one runner and one scratch factory.

var assetToolAvailable: Bool { assetToolURL() != nil }

var assetToolUnavailableNote: Comment { "WebUIAssetTool not built — run `swift build` first" }

func assetToolURL() -> URL? {
	// scanned, not hard-coded: the product directory carries a platform suffix off
	// darwin, and a nil `Process.executableURL` aborts the runner.
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

func runAssetTool(_ args: [String]) throws -> (status: Int32, out: String) {
	let url = try #require(assetToolURL(), "\(assetToolUnavailableNote)")
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

/// a scratch directory the test removes when it ends.
func assetToolScratch(prefix: String) throws -> String {
	let dir = FileManager.default.temporaryDirectory
		.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
	try FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
	return dir.path
}

func writeAssetToolInput(_ text: String, to path: String) throws {
	try text.write(toFile: path, atomically: true, encoding: .utf8)
}