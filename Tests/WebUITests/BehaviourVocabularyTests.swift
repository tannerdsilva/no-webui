import Testing
import Foundation
import WebUICore

// the engine's markup contract, pinned.
//
// the engine applies consequences by reading `data-*` attributes; a behavior
// exists only because a typed Swift value serialized to one. that makes the
// attribute set a public API, and this suite is its gate: every `data-*` the
// engine mentions must be named in `Documentation/BEHAVIOUR.md`, and every
// canonical behavior name must be a `data-` attribute the document declares.
//
// prove-it-fails: deleting one row from BEHAVIOUR.md turns
// `engineAttributesAreDocumented` red naming exactly that attribute.

@Suite("behaviour vocabulary")
struct BehaviourVocabularyTests {
	private static let packageRoot = FrozenSurface.packageRoot()

	private static func read(_ relative: String) throws -> String {
		try String(
			contentsOf: packageRoot.appendingPathComponent(relative),
			encoding: .utf8
		)
	}

	private static func attributes(in text: String) -> Set<String> {
		let pattern = /data-[a-z][a-z0-9-]*/
		return Set(text.matches(of: pattern).map { String($0.output) })
	}

	/// the §22.5 canonical names. the document is normative over every other
	/// mention in the plan, so the gate pins the document against this list.
	private static let canonical: Set<String> = [
		"data-follow",
		"data-follow-state",
		"data-scroll-key",
		"data-scroll-to",
		"data-reading-keys",
		"data-draft-id",
		"data-focus-return",
		"data-dismiss",
		"data-reorder",
		"data-copy",
		"data-table-enhance",
		"data-skip-to",
		"data-reltime",
		"data-started",
		"data-elapsed",
		"data-preserve-open",
		"data-inline-edit",
		"data-roving",
		"data-scrollspy",
		"data-theme-choice",
		"data-autogrow",
		"data-submit-on-enter",
		"data-clear-on-submit",
		"data-clamp",
		"data-upload-into",
		"data-upload-name-template",
		"data-no-upload-pick",
		"data-filter-insert",
		"data-filter-template",
		"data-filter-clear",
		"data-open",
		"data-drawer-toggle",
	]

	// MARK: - the two assets

	/// the patch-survival core and the interaction extension are one vocabulary
	/// across two files: the engine ships the binders that must run before the
	/// first paint, the extension ships the rest behind one fetch at boot. both
	/// are read wherever the table is read.
	private static let assetPaths = [
		"designer/assets/webui-engine.js",
		"designer/assets/webui-engine-ext.js",
	]

	private static func assets() throws -> [String] {
		try assetPaths.map { try read($0) }
	}

	@Test("every attribute the engine reads is named in BEHAVIOUR.md")
	func engineAttributesAreDocumented() throws {
		let doc = try Self.read("Documentation/BEHAVIOUR.md")
		let documented = Self.attributes(in: doc)
		for (path, source) in zip(Self.assetPaths, try Self.assets()) {
			let engineAttributes = Self.attributes(in: source)
			#expect(!engineAttributes.isEmpty, "\(path) read as empty — the gate would pass vacuously")
			let missing = engineAttributes.subtracting(documented).sorted()
			#expect(
				missing.isEmpty,
				"\(path) reads attributes BEHAVIOUR.md does not name: \(missing.joined(separator: ", "))"
			)
		}
	}

	@Test("the document declares every canonical behavior attribute")
	func canonicalAttributesAreDeclared() throws {
		let doc = try Self.read("Documentation/BEHAVIOUR.md")
		let documented = Self.attributes(in: doc)
		let missing = Self.canonical.subtracting(documented).sorted()
		#expect(
			missing.isEmpty,
			"BEHAVIOUR.md is missing canonical attributes: \(missing.joined(separator: ", "))"
		)
	}

	@Test("a behavior serializes through one escaped attribute door")
	func behaviorSerializesThroughOneDoor() {
		struct FixtureAttribute: AttributeRepresentable {
			static let name = "data-fixture"
			let value: String
		}
		struct FixtureBehavior: Behavior {
			let value: String
			func attribute() -> FixtureAttribute { FixtureAttribute(value: value) }
		}

		let html = Element(.div) { Text("x") }
			.behavior(FixtureBehavior(value: "a\"b&c"))
			.markup
			.html
		#expect(html.contains("data-fixture=\"a&quot;b&amp;c\""), "attribute was not escaped: \(html)")
		#expect(!html.contains("data-fixture='"), "attribute used the wrong quoting: \(html)")
	}

	@Test("an escaping behavior value cannot break out of the attribute")
	func behaviorValueCannotBreakOut() {
		struct FixtureAttribute: AttributeRepresentable {
			static let name = "data-fixture"
			let value: String
		}
		struct FixtureBehavior: Behavior {
			let value: String
			func attribute() -> FixtureAttribute { FixtureAttribute(value: value) }
		}

		let html = Element(.div) { Text("x") }
			.behavior(FixtureBehavior(value: "\" onmouseover=\"alert(1)"))
			.markup
			.html
		#expect(!html.contains("onmouseover=\"alert(1)\""), "attribute value escaped its quotes: \(html)")
	}

	// MARK: - the dispatch table's structural pins (S3)

	/// the keys of the engine's dispatch table, in register order. the table
	/// is keyed by the exact attribute names the register fixes; a key here that
	/// the document does not name, or a register row missing from the table, is
	/// a dead control.
	private static let dispatched: Set<String> = [
		"data-follow",
		"data-reading-keys",
		"data-scroll-key",
		"data-scroll-to",
		"data-draft-id",
		"data-focus-return",
		"data-dismiss",
		"data-reorder",
		"data-copy",
		"data-table-enhance",
		"data-skip-to",
		"data-reltime",
		"data-started",
		"data-preserve-open",
		"data-inline-edit",
		"data-roving",
		"data-scrollspy",
		"data-autogrow",
		"data-submit-on-enter",
		"data-clear-on-submit",
		"data-clamp",
		"data-theme-choice",
		"data-filter-list",
		"data-upload-into",
		"data-drawer-toggle",
	]

	enum EngineSourceError: Error, CustomStringConvertible {
		case missing(String)

		var description: String {
			switch self {
				case .missing(let what): return "the engine source is missing \(what)"
			}
		}
	}

	/// the keys of one asset's `BEHAVIORS` object: every `BEHAVIORS['data-…']`
	/// assignment after the table is opened. the engine closes the block with
	/// `function init(opts)`; the extension has no init, so it reads to the end
	/// (registration there is a `register(name, …)` loop, never a literal key).
	private static func dispatchTableKeys(in asset: String) throws -> Set<String> {
		guard let start = asset.range(of: "var BEHAVIORS = {};") else {
			throw EngineSourceError.missing("the BEHAVIORS dispatch table")
		}
		let end = asset.range(of: "function init(opts)", range: start.upperBound..<asset.endIndex)?.lowerBound
			?? asset.endIndex
		let block = asset[start.upperBound..<end]
		let pattern = /BEHAVIORS\['(data-[a-z-]+)'\]/
		return Set(block.matches(of: pattern).map { String($0.output.1) })
	}

	/// the body of a top-level `function <name>(…)` in the engine, by brace
	/// counting from its opening brace. quotes are skipped so a `{` or `}` in a
	/// string literal cannot move the depth.
	private static func functionBody(named name: String, in source: String) throws -> String {
		guard let declaration = source.range(of: "function \(name)(") else {
			throw EngineSourceError.missing("`function \(name)`")
		}
		guard let open = source[declaration.upperBound...].firstIndex(of: "{") else {
			throw EngineSourceError.missing("the body of `\(name)`")
		}
		var depth = 0
		var quote: Character? = nil
		var index = open
		while index < source.endIndex {
			let character = source[index]
			if let active = quote {
				if character == "\\" {
					index = source.index(after: index)
					if index < source.endIndex { index = source.index(after: index) }
					continue
				}
				if character == active { quote = nil }
			} else if character == "\"" || character == "'" || character == "`" {
				quote = character
			} else if character == "{" {
				depth += 1
			} else if character == "}" {
				depth -= 1
				if depth == 0 { return String(source[source.index(after: open)..<index]) }
			}
			index = source.index(after: index)
		}
		throw EngineSourceError.missing("the closing brace of `\(name)`")
	}

	@Test("islandRender never runs patch hooks (islands are behavior-free)")
	func islandRenderIsBehaviorFree() throws {
		let engine = try Self.read("designer/assets/webui-engine.js")
		let body = try Self.functionBody(named: "islandRender", in: engine)
		#expect(!body.contains("runHooks("), "islandRender calls runHooks( — island html must stay behavior-free (plan §19.1)")
		#expect(body.contains("webui_render_region"), "the extracted islandRender body does not look like islandRender — the pin would pass vacuously")
	}

	@Test("the dispatch table's keys are exactly the documented behavior attributes")
	func dispatchTableMatchesDocument() throws {
		let sources = try Self.assets()
		let core = try Self.dispatchTableKeys(in: sources[0])
		let ext = try Self.dispatchTableKeys(in: sources[1])
		let keys = core.union(ext)
		#expect(keys.count >= 23, "the dispatch table read as \(keys.count) keys — the gate would pass vacuously")
		// the split is a checked property, not a memory: nine patch-survival
		// consequences in the engine, sixteen interaction consequences behind
		// the extension's fetch (the upload transport is the fifteenth, the
		// drawer toggle the sixteenth), and no key registered twice (a
		// duplicate binder is a dead copy of a consequence).
		#expect(core.count == 9, "the engine's table read as \(core.count) keys, expected the 9 patch-survival consequences")
		#expect(ext.count == 16, "the extension's table read as \(ext.count) keys, expected the 16 interaction consequences")
		#expect(
			core.intersection(ext).isEmpty,
			"a consequence is registered in both assets: \(core.intersection(ext).sorted().joined(separator: ", "))"
		)
		let doc = try Self.read("Documentation/BEHAVIOUR.md")
		let documented = Self.attributes(in: doc)
		let undocumented = keys.subtracting(documented).sorted()
		#expect(
			undocumented.isEmpty,
			"the dispatch table reads attributes BEHAVIOUR.md does not name: \(undocumented.joined(separator: ", "))"
		)
		#expect(
			keys == Self.dispatched,
			"the dispatch table keys drifted from the register — missing: \((Self.dispatched.subtracting(keys)).sorted().joined(separator: ", ")); extra: \((keys.subtracting(Self.dispatched)).sorted().joined(separator: ", "))"
		)
	}
}
