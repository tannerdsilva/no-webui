import Foundation
import Testing

// integration tests for `WebUIAssetTool` (the asset plugin's executable), ran as a
// subprocess: the flags, the counts reported into the build manifest, the exit code, and
// the real sheet. the pruner's parsing has unit tests in-process; what is asserted here is
// the contract the plugin and a consumer's build actually see.
//
// the 40-of-174 case is T9's own acceptance criterion, on the sheet this repo ships.
struct TokenPruningCLITests {

	/// the tool is a build product, so `swift test` without `swift build` legitimately
	/// leaves it absent. every test carries this as an `.enabled(if:)` trait, so a missing
	/// tool is a skip and never a Foundation trap inside `Process`.
	static var toolAvailable: Bool { toolURL() != nil }
	static let unavailable: Comment = "WebUIAssetTool not built — run `swift build` first"

	static func toolURL() -> URL? { assetToolURL() }

	func runTool(_ args: [String]) throws -> (status: Int32, out: String) {
		try runAssetTool(args)
	}

	/// a scratch directory that is removed when the test ends.
	func scratch() throws -> String { try assetToolScratch(prefix: "webui-pruning") }

	func write(_ text: String, to path: String) throws { try writeAssetToolInput(text, to: path) }

	/// the generated source, one `public static let <name>: String = """…"""` block,
	/// de-indented by the generator's four spaces.
	static func block(named name: String, in source: String) -> String? {
		let marker = "public static let \(name): String = \"\"\"\n"
		guard let start = source.range(of: marker) else { return nil }
		guard let end = source.range(of: "\n    \"\"\"", range: start.upperBound..<source.endIndex) else { return nil }
		return source[start.upperBound..<end.lowerBound]
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.hasPrefix("    ") ? String($0.dropFirst(4)) : String($0) }
			.joined(separator: "\n")
	}

	/// distinct `--name` declarations inside any `:root` block, at any nesting — the surface
	/// `DesignToken` enumerates, dark `@media { :root { … } }` pass included.
	///
	/// written here rather than reused from the tool on purpose: the CLI test should disagree
	/// with the tool when the tool is wrong. comments are stripped first, so a commented-out
	/// declaration is not counted as one.
	static func rootSurface(in css: String) -> [String] {
		var stripped = ""
		var inComment = false
		var chars = Array(css)
		var i = 0
		while i < chars.count {
			let c = chars[i]
			if inComment {
				if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
					inComment = false
					i += 2
					continue
				}
				i += 1
				continue
			}
			if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
				inComment = true
				i += 2
				continue
			}
			stripped.append(c)
			i += 1
		}
		chars = Array(stripped)

		var names: [String] = []
		// a `:root` block is collected wherever it sits — at the top level, or
		// nested in the `@layer webui { … }` wrapper the shipped composition uses.
		// a layer is a nesting level like any other; a parser that only reads depth
		// 0 would "prove" the surface empty. selector text and declaration text
		// both accumulate in `pending`, which is consumed at each brace: what
		// precedes a `{` is that block's selector, what precedes its `}` is its
		// body (`:root` blocks nest nothing, so this is exact for them).
		var selectors: [String] = []
		var pending = ""
		i = 0
		while i < chars.count {
			let c = chars[i]
			if c == "{" {
				selectors.append(pending.trimmingCharacters(in: .whitespacesAndNewlines))
				pending = ""
			} else if c == "}" {
				let selector = selectors.popLast() ?? ""
				if selector == ":root" {
					for part in pending.split(separator: ";") {
						let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
						guard text.hasPrefix("--"), let colon = text.firstIndex(of: ":") else { continue }
						let name = String(text[text.startIndex..<colon])
						if !names.contains(name) { names.append(name) }
					}
				}
				pending = ""
			} else {
				pending.append(c)
			}
			i += 1
		}
		return names
	}

	static func manifest(at path: String) throws -> [String: Any] {
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
		return json["served"] as? [String: Any] ?? [:]
	}

	@Test("without --used-tokens the sheet ships whole — there is no oracle and no pruning",
	      .enabled(if: toolAvailable))
	func noOracleNoPruning() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let css = ":root {\n\t--alpha: 1;\n\t--beta: 2;\n}\n.rule { color: var(--beta); }\n"
		try write(css, to: dir + "/in.css")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--output", dir + "/out.swift",
			"--manifest-output", dir + "/manifest.json",
		])
		#expect(result.status == 0, "\(result.out)")

		let source = try String(contentsOfFile: dir + "/out.swift", encoding: .utf8)
		let emitted = try #require(Self.block(named: "css", in: source))
		#expect(emitted.contains("--alpha: 1;"))
		#expect(emitted.contains("--beta: 2;"))
		let served = try Self.manifest(at: dir + "/manifest.json")
		#expect(served["tokens"] == nil, "no pruning happened, so the manifest records none")
	}

	@Test("40 of 174: the emitted :root carries exactly the reachable set",
	      .enabled(if: toolAvailable))
	func fortyOfOneSeventyFour() throws {
		let sheet = "designer/assets/design-system.css"
		let realCSS = try String(contentsOfFile: sheet, encoding: .utf8)
		let vocabulary = Self.rootSurface(in: realCSS)
		#expect(vocabulary.count > 100, "the shipped sheet declares a large :root surface")

		let keep = Array(vocabulary.prefix(40))
		let dropped = Array(vocabulary.dropFirst(40)).first

		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		try write(keep.joined(separator: "\n") + "\n", to: dir + "/used.txt")

		let result = try runTool([
			"--css-input", sheet,
			"--used-tokens", dir + "/used.txt",
			"--output", dir + "/out.swift",
			"--manifest-output", dir + "/manifest.json",
		])
		#expect(result.status == 0, "\(result.out)")

		let emitted = try #require(Self.block(named: "css", in: try String(contentsOfFile: dir + "/out.swift", encoding: .utf8)))
		let emittedRoot = Self.rootSurface(in: emitted)
		#expect(Set(emittedRoot) == Set(keep), "the :root surface is exactly what the oracle resolved")
		#expect(emittedRoot.count == 40)
		if let dropped {
			#expect(!emittedRoot.contains(dropped), "an unreachable token is gone from the surface")
		}

		let served = try Self.manifest(at: dir + "/manifest.json")
		let tokens = try #require(served["tokens"] as? [String: Any])
		#expect(tokens["emitted"] as? Int == 40)
		#expect(tokens["pruned"] as? Int == vocabulary.count - 40)
		#expect(tokens["declarations"] as? Int == vocabulary.count,
		        "every token on the surface was considered")

		// everything that is not a token declaration is still there: this is an edit, not a rewrite.
		#expect(emitted.contains(".button"), "component rules survive")
		#expect(emitted.count > realCSS.count / 2)
	}

	@Test("the minified sheet agrees with the working sheet",
	      .enabled(if: toolAvailable))
	func minifiedAgrees() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let css = ":root {\n\t--alpha: 1;\n\t--beta: 2;\n}\n"
		try write(css, to: dir + "/in.css")
		try write("alpha\n", to: dir + "/used.txt")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--used-tokens", dir + "/used.txt",
			"--output", dir + "/out.swift",
		])
		#expect(result.status == 0, "\(result.out)")

		let source = try String(contentsOfFile: dir + "/out.swift", encoding: .utf8)
		let working = try #require(Self.block(named: "css", in: source))
		let minified = try #require(Self.block(named: "cssMinified", in: source))
		#expect(working.contains("--alpha: 1"))
		#expect(minified.contains("--alpha: 1"), "the minifier strips comments and blank lines, not intra-line spacing")
		#expect(!working.contains("--beta"))
		#expect(!minified.contains("--beta"), "a pruned token must not survive minification")
	}

	@Test("a guarded reference survives even when the oracle omitted it",
	      .enabled(if: toolAvailable))
	func guardKeepsToken() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		let css = ":root {\n\t--alpha: 1;\n\t--beta: 2;\n\t--gamma: 3;\n}\n"
		try write(css, to: dir + "/in.css")
		try write("alpha\n", to: dir + "/used.txt")
		try write(".app { color: var(--beta); }\n", to: dir + "/app.css")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--used-tokens", dir + "/used.txt",
			"--guard-css", dir + "/app.css",
			"--output", dir + "/out.swift",
		])
		#expect(result.status == 0, "\(result.out)")

		let emitted = try #require(Self.block(named: "css", in: try String(contentsOfFile: dir + "/out.swift", encoding: .utf8)))
		#expect(emitted.contains("--alpha: 1;"))
		#expect(emitted.contains("--beta: 2;"), "the guard keeps what the app's own css resolves")
		#expect(!emitted.contains("--gamma"))
	}

	@Test("a name the sheet does not declare fails the build and names itself",
	      .enabled(if: toolAvailable))
	func unknownNameFails() throws {
		let dir = try scratch()
		defer { try? FileManager.default.removeItem(atPath: dir) }
		try write(":root {\n\t--alpha: 1;\n}\n", to: dir + "/in.css")
		try write("--alpha\n--does-not-exist\n", to: dir + "/used.txt")

		let result = try runTool([
			"--css-input", dir + "/in.css",
			"--used-tokens", dir + "/used.txt",
			"--output", dir + "/out.swift",
		])
		#expect(result.status != 0, "a token this build will not ship must not pass quietly")
		#expect(result.out.contains("--does-not-exist"), "the failure names the token: \(result.out)")
	}
}