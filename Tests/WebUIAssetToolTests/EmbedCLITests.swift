import Foundation
import Testing

// integration tests for the tool's consumer-manifest mode, ran as a subprocess: the flags,
// the generated types, the output, and the exit code. the library-level behavior is covered
// by `WebUIBuildTests`; what is asserted here is the contract the plugin's command line sees.

struct EmbedCLITests {

	static let manifestJSON = """
	{
	  "types": [
	    { "name": "ProbeCSS", "kind": "file", "path": "vendor/probe.min.css",
	      "contentType": "text/css; charset=utf-8", "minify": true, "prose": "check" },
	    { "name": "ProbeInline", "kind": "text", "text": "var probe = 1;\\n",
	      "contentType": "text/javascript" }
	  ]
	}
	"""

	@Test("`--embed-manifest` writes the declared types",
	      .enabled(if: assetToolAvailable))
	func embedsAManifest() throws {
		let dir = try assetToolScratch(prefix: "webui-embed")
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let assets = dir + "/Assets"
		try FileManager.default.createDirectory(
			atPath: assets + "/vendor", withIntermediateDirectories: true
		)
		try writeAssetToolInput(":root { --probe: 1 }\n", to: assets + "/vendor/probe.min.css")
		try writeAssetToolInput(Self.manifestJSON, to: assets + "/webui-assets.json")

		let out = dir + "/Embedded.swift"
		let result = try runAssetTool([
			"--embed-manifest", assets + "/webui-assets.json",
			"--output", out,
		])
		#expect(result.status == 0, "embedding must succeed: \(result.out)")
		#expect(result.out.contains("ProbeCSS"), "the receipt names the type: \(result.out)")
		#expect(result.out.contains("ProbeInline"), "the receipt covers every entry: \(result.out)")

		let source = try String(contentsOfFile: out, encoding: .utf8)
		#expect(source.contains("public enum ProbeCSS: WebUIShippedAsset"))
		#expect(source.contains("public enum ProbeInline: WebUIShippedAsset"))
	}

	@Test("a bad manifest exits non-zero, naming the entry",
	      .enabled(if: assetToolAvailable))
	func refusesABadManifest() throws {
		let dir = try assetToolScratch(prefix: "webui-embed")
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let assets = dir + "/Assets"
		try FileManager.default.createDirectory(atPath: assets, withIntermediateDirectories: true)
		// the manifest is well-formed, but `vendor/probe.min.css` is not on disk.
		try writeAssetToolInput(Self.manifestJSON, to: assets + "/webui-assets.json")

		let result = try runAssetTool([
			"--embed-manifest", assets + "/webui-assets.json",
			"--output", dir + "/Embedded.swift",
		])
		#expect(result.status != 0, "a missing asset must not embed: \(result.out)")
		#expect(result.out.contains("ProbeCSS"), "the failure names the entry: \(result.out)")
	}

	@Test("a payload over its pinned ceiling exits non-zero, naming the entry and the ceiling",
	      .enabled(if: assetToolAvailable))
	func refusesAnOverCeilingPayload() throws {
		let dir = try assetToolScratch(prefix: "webui-embed")
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let assets = dir + "/Assets"
		try FileManager.default.createDirectory(atPath: assets + "/vendor", withIntermediateDirectories: true)
		try writeAssetToolInput(":root { --probe: 1 }\n", to: assets + "/vendor/probe.min.css")
		// `ProbeInline` is 15 bytes of javascript; the manifest pins it to 4.
		let pinned = Self.manifestJSON.replacingOccurrences(
			of: "\"contentType\": \"text/javascript\"",
			with: "\"contentType\": \"text/javascript\", \"ceilingBytes\": 4"
		)
		try writeAssetToolInput(pinned, to: assets + "/webui-assets.json")

		let result = try runAssetTool([
			"--embed-manifest", assets + "/webui-assets.json",
			"--output", dir + "/Embedded.swift",
		])
		#expect(result.status != 0, "an over-ceiling payload must not embed: \(result.out)")
		#expect(result.out.contains("ProbeInline"), "the failure names the entry: \(result.out)")
		#expect(result.out.contains("ceiling"), "the failure names the ceiling: \(result.out)")
	}
}