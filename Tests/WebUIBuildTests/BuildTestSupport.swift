import Foundation
import Testing

// MARK: - shared helpers for the WebUIBuild suites
//
// file-scope internal so both suites share one scratch-directory factory and one
// independent `gunzip -c` — never the code under test.

/// a fresh temporary directory for one test's outputs.
func buildScratchDirectory(prefix: String) throws -> URL {
	let dir = FileManager.default.temporaryDirectory
		.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
	return dir
}

/// an independent `gunzip -c` over bytes this package produced — the outside instrument
/// that says whether a "variant" actually inflates.
func gunzipIndependently(_ data: Data) throws -> Data {
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