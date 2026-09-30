import Foundation
import Testing
import WebUICore
import WebUIBuild

// MARK: - the manifest
//
// `Assets/webui-assets.json` is the one lever SwiftPM gives a vendored plugin: a file
// convention the plugin discovers. `load` validates it — an unknown key, an unknown kind
// or a missing path fails naming the entry rather than being ignored — and `embed` writes
// every entry as generated swift in one file.

@Suite("asset manifest")
struct ManifestTests {

	static let cssPayload = "/* note: would ship */\n.probe { color: teal; }\n\n\n.other { color: red; }\n"

	/// the three kinds, one each: a file that is minified + prose-gated, an inline text
	/// entry, and a directory bag.
	static let manifestJSON = """
	{
	  "types": [
	    { "name": "ProbeCSS", "kind": "file", "path": "vendor/probe.min.css",
	      "contentType": "text/css; charset=utf-8", "minify": true, "prose": "check" },
	    { "name": "ProbeInline", "kind": "text", "text": "var probe = 1;\\n",
	      "contentType": "text/javascript" },
	    { "name": "ProbeFonts", "kind": "directory", "path": "vendor/fonts",
	      "extensions": [".woff2"], "contentType": "font/woff2" }
	  ]
	}
	"""

	static let fontA: [UInt8] = [0x77, 0x4F, 0x46, 0x32]
	static let fontB: [UInt8] = [0x77, 0x4F, 0x46, 0x33]

	/// a `<root>/Assets/` tree with the manifest and every file it names.
	func fixture(manifestJSON: String? = nil) throws -> (root: URL, manifest: URL) {
		let root = try buildScratchDirectory(prefix: "webui-manifest")
		let assets = root.appendingPathComponent("Assets")
		try FileManager.default.createDirectory(
			at: assets.appendingPathComponent("vendor/fonts"), withIntermediateDirectories: true
		)
		try Self.cssPayload.write(
			to: assets.appendingPathComponent("vendor/probe.min.css"), atomically: true, encoding: .utf8
		)
		try Data(Self.fontA).write(to: assets.appendingPathComponent("vendor/fonts/a.woff2"))
		try Data(Self.fontB).write(to: assets.appendingPathComponent("vendor/fonts/b.woff2"))
		// not named by `extensions`: must not appear in the emitted bag.
		try Data([0x78]).write(to: assets.appendingPathComponent("vendor/fonts/c.txt"))

		let manifest = assets.appendingPathComponent("webui-assets.json")
		try (manifestJSON ?? Self.manifestJSON).write(to: manifest, atomically: true, encoding: .utf8)
		return (root, manifest)
	}

	// MARK: tests

	@Test("one file, three types: two shipped assets and one directory bag")
	func embedsThreeEntries() throws {
		let (root, manifestURL) = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		let out = root.appendingPathComponent("Embedded.swift")

		let manifest = try WebUIAssetManifest.load(from: manifestURL)
		let receipts = try WebUIAssetBuilder.embed(manifest: manifest, to: out)

		#expect(receipts.map(\.typeName) == ["ProbeCSS", "ProbeInline", "ProbeFonts"])
		// the file entry is minified: its receipt reports the minified size, and the emitted
		// bytes equal `minifyCSS` of the source file.
		let minified = minifyCSS(Self.cssPayload)
		#expect(receipts[0].bytes == minified.utf8.count)
		#expect((receipts[0].gzipBytes ?? 0) > 0)
		// the directory receipt counts every included file's bytes (4 + 4), and carries a
		// fingerprint of the set (a build record, not a url address).
		#expect(receipts[2].bytes == Self.fontA.count + Self.fontB.count)
		#expect(receipts[2].stamp.count == 12)
		#expect(receipts[2].gzipBytes == nil, "a directory bag is not one compressed payload")

		let source = try String(contentsOf: out, encoding: .utf8)
		#expect(source.contains("import WebUICore"))
		#expect(source.contains("public enum ProbeCSS: WebUIShippedAsset"))
		#expect(source.contains("public enum ProbeInline: WebUIShippedAsset"))
		#expect(source.contains("public enum ProbeFonts {"))
		#expect(source.contains("filesBase64: [String: String]"))
		// the directory's extensions filtered: two woff2 files, not the txt.
		#expect(source.contains("\"a.woff2\": \"\(Data(Self.fontA).base64EncodedString())\""))
		#expect(source.contains("\"b.woff2\": \"\(Data(Self.fontB).base64EncodedString())\""))
		#expect(!source.contains("c.txt"))

		// the file entry's payload decodes out of the source to the minified bytes.
		let body = try extractBase64Literal(source, label: "bodyBase64")
		#expect(Array(body) == Array(minified.utf8))
		// the inline entry ships the javascript verbatim (nothing to minify, prose off):
		// its receipt counts the payload exactly.
		#expect(receipts[1].bytes == "var probe = 1;\n".utf8.count)
	}

	@Test("two runs are byte-identical, directory keys included")
	func deterministic() throws {
		let (root, manifestURL) = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		let manifest = try WebUIAssetManifest.load(from: manifestURL)
		let first = root.appendingPathComponent("One.swift")
		let second = root.appendingPathComponent("Two.swift")

		_ = try WebUIAssetBuilder.embed(manifest: manifest, to: first)
		_ = try WebUIAssetBuilder.embed(manifest: manifest, to: second)
		#expect(try Data(contentsOf: first) == (try Data(contentsOf: second)))
	}

	@Test("a path that is not there fails, naming the entry and the path")
	func missingPathNamesTheEntry() throws {
		let broken = Self.manifestJSON.replacingOccurrences(of: "vendor/probe.min.css", with: "vendor/nope.css")
		let (root, manifestURL) = try fixture(manifestJSON: broken)
		defer { try? FileManager.default.removeItem(at: root) }
		let manifest = try WebUIAssetManifest.load(from: manifestURL)

		do {
			_ = try WebUIAssetBuilder.embed(manifest: manifest, to: root.appendingPathComponent("Bad.swift"))
			Issue.record("a missing asset must not embed")
		} catch let error as WebUIBuildError {
			#expect(error.description.contains("ProbeCSS"), "the failure names the entry: \(error)")
			#expect(error.description.contains("vendor/nope.css"), "the failure names the path: \(error)")
		}
	}

	@Test("an unknown key fails rather than being ignored")
	func unknownKeyFails() throws {
		let broken = Self.manifestJSON.replacingOccurrences(
			of: "\"contentType\": \"text/javascript\"",
			with: "\"colour\": \"red\", \"contentType\": \"text/javascript\""
		)
		let (root, manifestURL) = try fixture(manifestJSON: broken)
		defer { try? FileManager.default.removeItem(at: root) }

		do {
			_ = try WebUIAssetManifest.load(from: manifestURL)
			Issue.record("an unknown key must not load")
		} catch let error as WebUIBuildError {
			#expect(error.description.contains("colour"), "the failure names the key: \(error)")
			#expect(error.description.contains("ProbeInline"), "the failure names the entry: \(error)")
		}
	}

	@Test("an unknown kind fails, naming the entry")
	func unknownKindFails() throws {
		let broken = Self.manifestJSON.replacingOccurrences(of: "\"kind\": \"file\"", with: "\"kind\": \"folder\"")
		let (root, manifestURL) = try fixture(manifestJSON: broken)
		defer { try? FileManager.default.removeItem(at: root) }

		do {
			_ = try WebUIAssetManifest.load(from: manifestURL)
			Issue.record("an unknown kind must not load")
		} catch let error as WebUIBuildError {
			#expect(error.description.contains("folder"), "the failure quotes the kind: \(error)")
			#expect(error.description.contains("ProbeCSS"), "the failure names the entry: \(error)")
		}
	}
}