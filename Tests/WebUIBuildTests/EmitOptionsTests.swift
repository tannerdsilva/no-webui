import Foundation
import Testing
import WebUICore
import WebUIBuild

// MARK: - emit options
//
// the two transformations a host may ask for on the way in: `minify` (the same css minifier
// the framework's own sheet goes through, so a working sheet's designer notes never reach a
// client) and `prose` (the guard that refuses a payload whose comments would ship). prose
// runs on the payload as it will ship — after minify — so a comment the minifier strips is
// not a finding.

@Suite("emit options")
struct EmitOptionsTests {

	static let sheetWithNotes = """
	/* designer note: the accent is tuned for the dark pass */
	:root { --probe: 1 }


	.card { color: red; }
	"""

	static let commentPayload = ":root { --probe: 1 }\n/* note: ships to clients */\n"

	@Test("minify shrinks the payload and the emitted bytes equal `minifyCSS(input)`")
	func minifyShrinks() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }
		let out = dir.appendingPathComponent("MinifiedSheet.swift")

		let receipt = try WebUIAssetBuilder.emit(
			shipped: Self.sheetWithNotes,
			typeName: "MinifiedSheet",
			options: .init(minify: true, prose: .off, contentType: "text/css; charset=utf-8"),
			to: out
		)
		let expected = minifyCSS(Self.sheetWithNotes)
		#expect(receipt.bytes == expected.utf8.count)
		#expect(receipt.bytes < Self.sheetWithNotes.utf8.count, "minify must be strictly smaller here")

		let source = try String(contentsOf: out, encoding: .utf8)
		let body = try extractBase64Literal(source, label: "bodyBase64")
		#expect(Array(body) == Array(expected.utf8))
		#expect(!String(decoding: body, as: UTF8.self).contains("designer note"), "the note did not ship")
	}

	@Test("prose finds a comment that would ship, naming line and text")
	func proseRefusesAComment() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }

		do {
			_ = try WebUIAssetBuilder.emit(
				shipped: Self.commentPayload,
				typeName: "ChattySheet",
				options: .init(prose: .check, contentType: "text/css; charset=utf-8"),
				to: dir.appendingPathComponent("ChattySheet.swift")
			)
			Issue.record("a comment in the payload must not build")
		} catch let error as WebUIBuildError {
			#expect(error.description.contains("ChattySheet"), "the failure names the type: \(error)")
			#expect(error.description.contains("line 2"), "the failure names the line: \(error)")
			#expect(error.description.contains("note: ships to clients"), "the failure quotes the prose: \(error)")
		}
	}

	@Test("a clean payload passes the prose gate, and the default policy does not scan")
	func prosePassesCleanPayloads() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }
		let clean = ":root { --probe: 1 }\n"

		let checked = try WebUIAssetBuilder.emit(
			shipped: clean, typeName: "CleanSheet",
			options: .init(prose: .check, contentType: "text/css; charset=utf-8"),
			to: dir.appendingPathComponent("CleanSheet.swift")
		)
		#expect(checked.bytes == clean.utf8.count)

		// `.off` (the default) ships what it is given, comment included — the gate is a
		// decision the caller makes, not an accident of the default.
		let unchecked = try WebUIAssetBuilder.emit(
			shipped: Self.commentPayload, typeName: "UncheckedSheet",
			options: .init(contentType: "text/css; charset=utf-8"),
			to: dir.appendingPathComponent("UncheckedSheet.swift")
		)
		#expect(unchecked.bytes == Self.commentPayload.utf8.count)
	}

	@Test("prose judges the payload as it ships: a comment the minifier strips is not a finding")
	func proseRunsAfterMinify() throws {
		let dir = try buildScratchDirectory(prefix: "webui-emit")
		defer { try? FileManager.default.removeItem(at: dir) }

		let receipt = try WebUIAssetBuilder.emit(
			shipped: Self.commentPayload, typeName: "MinifiedChatty",
			options: .init(minify: true, prose: .check, contentType: "text/css; charset=utf-8"),
			to: dir.appendingPathComponent("MinifiedChatty.swift")
		)
		#expect(receipt.bytes == minifyCSS(Self.commentPayload).utf8.count)
	}
}