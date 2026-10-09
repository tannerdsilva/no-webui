import Foundation
import Testing
import WebUI
import WebUICore
import WebUIDesignSystem

// MARK: - W3.6 capability islands: the typed declaration surface
//
// declaring an island is the whole wiring: `IslandRegion<I>` renders the
// engine's mount point, and `WebUIDocument` collects the capability name out
// of the body and folds it into the emitted `RuntimeConfig` — no manual
// `capabilities` entry.

/// a conformer whose capability has no artifact: the collector grants it and
/// the engine degrades an absent fetch to the server-rendered fallback.
struct GreetingIsland: Island {
	static let name = "greeting"
	static func render(_ input: String) -> String {
		"<span>hi \(htmlEscape(input))</span>"
	}
}

/// a second, distinct capability for merge tests.
struct GreetingPingIsland: Island {
	static let name = "ping"
	static func render(_ input: String) -> String { "<span>\(input)</span>" }
}

/// a degenerate conformer used to prove the collector never grants an empty
/// name.
struct NamelessIsland: Island {
	static let name = ""
	static func render(_ input: String) -> String { "" }
}

// MARK: - the mount point

@Suite("capability islands")
struct IslandTests {

	@Test("IslandRegion renders the engine's mount point with the declared capability")
	func mountPointAttributes() {
		let html = IslandRegion<GreetingIsland>("world").renderThroughBuffer()
		#expect(html.hasPrefix("<div "))
		#expect(html.contains("data-webui-island=\"greeting\""))
		#expect(html.hasSuffix("</div>"))
	}

	@Test("the mount args are the engine's json envelope with the input under 'input'")
	func mountArgsEnvelope() throws {
		let html = IslandRegion<GreetingIsland>("hello world").renderThroughBuffer()
		let decoded = try #require(Self.decodedArgs(from: html))
		let object = try #require(
			try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: String]
		)
		#expect(object == ["input": "hello world"])
	}

	@Test("a hostile input cannot break the single-quoted args attribute")
	func mountInputEscaping() throws {
		let input = "say \"hi\" \\ <>&' \u{2028}"
		let html = IslandRegion<GreetingIsland>(input).renderThroughBuffer()
		let rawArgs = try #require(Self.rawArgs(from: html))
		// the attribute is single-quoted: no raw single quote may ride inside
		#expect(!rawArgs.contains("'"))
		let decoded = try #require(Self.decodedArgs(from: html))
		let object = try #require(
			try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: String]
		)
		#expect(object == ["input": input])
	}

	@Test("the region renders its server-side fallback inside the mount point")
	func ssrFallbackRenders() {
		let html = IslandRegion<GreetingIsland>("dolly").renderThroughBuffer()
		#expect(html.contains("<span>hi dolly</span>"))
	}

	// MARK: - the collector

	@Test("declaring an island wires the capability into the emitted config")
	func bareDeclarationGrants() throws {
		let body = IslandRegion<GreetingIsland>("world").renderThroughBuffer()
		let html = WebUIDocument(title: "Islands", body: body).renderThroughBuffer()
		let config = try #require(Self.decodedConfig(from: html))
		#expect(config.contains(#""capabilities":["greeting"]"#))
		#expect(html.contains("data-webui-island=\"greeting\""))
		#expect(html.contains(#"webui-config"#))
	}

	@Test("a body with no islands leaves the emitted config untouched")
	func noIslandsNoCapabilities() {
		let html = WebUIDocument(title: "t", body: "just text").renderThroughBuffer()
		#expect(html.contains("webui-config"))
		#expect(!html.contains("capabilities"))
	}

	@Test("declared islands merge into an explicit runtimeConfig without duplicating")
	func explicitConfigMergesDeclared() throws {
		let body = IslandRegion<GreetingIsland>("a").renderThroughBuffer()
			+ IslandRegion<GreetingPingIsland>("b").renderThroughBuffer()
		let config = RuntimeConfig(capabilities: ["greeting"])
		let html = WebUIDocument(title: "t", body: body, runtimeConfig: config).renderThroughBuffer()
		// caller order first, then the new declaration; greeting not duplicated
		let decoded = try #require(Self.decodedConfig(from: html))
		#expect(decoded.contains(#""capabilities":["greeting","ping"]"#))
	}

	@Test("declared islands merge into a clientMode config too (the smoke-page shape)")
	func clientModeMergesDeclared() throws {
		let body = IslandRegion<GreetingIsland>("a").renderThroughBuffer()
		let boot = ClientBoot(config: RuntimeConfig(capabilities: ["offline", "never-built"]))
		let html = WebUIDocument(title: "t", body: body, clientMode: boot).renderThroughBuffer()
		let decoded = try #require(Self.decodedConfig(from: html))
		#expect(decoded.contains(#""capabilities":["offline","never-built","greeting"]"#))
	}

	@Test("the collector scans first-seen order and dedupes repeated declarations")
	func collectorOrderAndDedupe() {
		let names = WebUIDocument.declaredIslandNames(
			in: #"<div data-webui-island="a"></div><div data-webui-island="b"></div><div data-webui-island="a"></div>"#
		)
		#expect(names == ["a", "b"])
		#expect(WebUIDocument.declaredIslandNames(in: "nothing here").isEmpty)
	}

	@Test("an empty island name is never granted")
	func emptyNameNotGranted() {
		let body = IslandRegion<NamelessIsland>("x").renderThroughBuffer()
		let html = WebUIDocument(title: "t", body: body).renderThroughBuffer()
		#expect(html.contains("data-webui-island=\"\""))
		#expect(!html.contains("capabilities"))
	}

	@Test("addingCapabilities folds names after the caller's list, deduped, immutably")
	func addingCapabilitiesFolds() {
		let config = RuntimeConfig(capabilities: ["a"])
		let merged = config.addingCapabilities(["b", "a", "c"])
		#expect(merged.capabilities == ["a", "b", "c"])
		#expect(config.capabilities == ["a"])
	}

	// MARK: - helpers

	/// the raw (still entity-escaped) text inside the single-quoted
	/// `data-webui-args` attribute.
	static func rawArgs(from html: String) -> String? {
		guard let start = html.range(of: "data-webui-args='")?.upperBound,
		      let end = html[start...].range(of: "'>") else { return nil }
		return String(html[start..<end.lowerBound])
	}

	/// the same text with html entities decoded — what `getAttribute` returns
	/// to the engine before it `JSON.parse`s it. `&amp;` decodes last so
	/// `&amp;quot;` cannot double-decode.
	static func decodedArgs(from html: String) -> String? {
		guard let raw = rawArgs(from: html) else { return nil }
		return raw
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&amp;", with: "&")
	}

	/// the decoded `webui-config` meta content — what the engine reads from
	/// the served document.
	static func decodedConfig(from html: String) -> String? {
		guard let start = html.range(of: #"name="webui-config" content=""#)?.upperBound,
		      let end = html[start...].range(of: #"">"#) else { return nil }
		let raw = String(html[start..<end.lowerBound])
		return raw
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">")
			.replacingOccurrences(of: "&amp;", with: "&")
	}
}
