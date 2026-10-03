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

enum BuildTestError: Error {
	case missingLiteral
	case badBase64
}

/// pull `private static let <label> = "<base64>"` back out of emitted source. base64 is
/// mechanically extractable, which is the point of the encoding: no escaping can silently
/// change bytes, so a test can prove the payload round-tripped.
func extractBase64Literal(_ source: String, label: String) throws -> Data {
	guard let start = source.range(of: "\(label) = \"") else {
		Issue.record("no `\(label)` literal in the emitted source")
		throw BuildTestError.missingLiteral
	}
	let rest = source[start.upperBound...]
	guard let end = rest.firstIndex(of: "\"") else {
		Issue.record("unterminated `\(label)` literal")
		throw BuildTestError.missingLiteral
	}
	guard let data = Data(base64Encoded: String(rest[..<end])) else {
		Issue.record("`\(label)` is not base64")
		throw BuildTestError.badBase64
	}
	return data
}