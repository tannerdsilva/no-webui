import Foundation

// MARK: - the DX-15b shadow check (additive; lane T)
//
// the anti-shadow policy leg: a CONSUMER's theme/chrome sheet must not restyle
// a class the design system ships under that exact name. chrome historically
// re-skinned widgets by shadowing 9 DS classes (`chip`, `kv`, `toast`,
// `modal-overlay`, `log-line`, `md`, `swatch`, `inline-edit`, `tool-btn`);
// DX-15b makes that a build-time warning.
//
// the existing `lint`/`generate` scans only `class="..."` attribute literals —
// invisible to string-sheet CSS and to `CSSRule("...")` selectors (and, being
// text scans, they also miss the DS's own escaped `class=\"` forms). this verb
// adds the SELECTOR-EXTRACTION leg over CONSUMER sources:
//   (1) Swift string-literal CSS    — `.chip { … }` inside `"..."`
//   (2) `CSSRule("...", …)` args    — the first argument's class selectors
//   (3) `class="..."` literals      — the existing leg, kept for completeness
// intersected with the DS class union. each hit warns NAMING the owning
// component. the check NEVER runs over DS sources — it is pointed at consumer
// source dirs only, and it REFUSES paths under the framework's own trees.
//
// the DS class union is built from REAL artifacts (never invented):
//   - the shipped sheet's class selectors (`--ds-css design-system.css`);
//   - the DS component sources' claimed classes (`--ds-sources …Core`,
//     scanned with an EXTENDED matcher that also reads the escaped
//     `class=\"…"` string-literal form the inventory scanner misses),
//     which supplies the class→owner mapping;
//   - the generated inventory's union (`--inventory Continuum+Generated.swift`),
//     when present.
// a run with none of those flags still checks the contract's nine shadowed
// classes against a minimal built-in reference, so the deep default is
// deterministic.

extension WebUIContinuumTool.Run {

	// MARK: - the shadow verb

	/// `shadow --sources <dir> [--ds-css <css>] [--ds-sources <core>]
	///        [--inventory <generated>] [--fail] [--demo]`
	///
	/// extract exact class tokens from consumer sources (string-literal CSS,
	/// `CSSRule("…")` args, `class="…"` literals), intersect with the DS class
	/// union, warn naming the owning component. never scans the DS sources
	/// themselves — the caller points it at the consumer/chrome tree.
	///
	/// exit: 0 when clean (or warn-only), 1 when `--fail` and any collision is
	/// found. `--demo` prints a one-line verdict for gate embedding.
	static func shadow(_ argv: [String]) throws {
		let sources = try Args.require(argv, "--sources")
		let fail = Args.has(argv, "--fail")
		let demo = Args.has(argv, "--demo")

		// 1. the DS class union: real artifacts only.
		let union = try buildDSUnion(
			dsCSS: Args.option(argv, "--ds-css"),
			dsSources: Args.option(argv, "--ds-sources"),
			inventory: Args.option(argv, "--inventory")
		)

		// 2. scan the consumer sources (never the DS sources — a path
		//    literally under a DS dir is refused, not silently scanned).
		let files = try consumerSwiftFiles(in: sources)
		var collisions: [ShadowHit] = []
		for file in files {
			guard !isDesignSystemSource(file) else {
				print("warning: shadow: skipping \(file) — the check never runs over design-system sources")
				continue
			}
			let text = try String(contentsOfFile: file, encoding: .utf8)
			let tokens = extractClassTokens(from: text)
			for token in tokens where union[token] != nil {
				collisions.append(ShadowHit(
					className: token,
					owner: union[token] ?? "design-system",
					file: file
				))
			}
		}

		// 3. report, deduped by (class, owner) across files.
		var seen: Set<String> = []
		var count = 0
		for hit in collisions.sorted(by: { $0.className < $1.className }) {
			let key = "\(hit.className)|\(hit.owner)"
			guard seen.insert(key).inserted else { continue }
			count += 1
			print("warning: class '\(hit.className)' shadows design-system class '\(hit.className)' (owned by \(hit.owner)) at \(abbreviate(hit.file, from: sources))")
		}

		if demo {
			print("[WebUIContinuumTool] shadow: \(count) collision(s) against the DS class union")
		}
		if fail && count > 0 {
			WebUIContinuumTool.writeError("WebUIContinuumTool: shadow check found \(count) class(es) shadowing the design system — use token substitution or a namespaced class")
			exit(1)
		}
	}

	// MARK: - model

	struct ShadowHit: Equatable {
		let className: String
		let owner: String
		let file: String
	}

	// MARK: - the DS class union (built from real artifacts)

	/// class → owning component. the owner map comes from the DS component
	/// scan; classes found only in the shipped sheet get the literal owner
	/// "design-system.css".
	struct DSUnion {
		var byName: [String: String] = [:]
		func owner(for name: String) -> String? { byName[name] }
	}

	static func buildDSUnion(dsCSS: String?, dsSources: String?, inventory: String?) throws -> [String: String] {
		var union: [String: String] = builtInDSUnion
		var owners = builtInDSUnion

		// the generated inventory's union (attribute-literal classes).
		if let inventory, FileManager.default.fileExists(atPath: inventory) {
			let generated = try String(contentsOfFile: inventory, encoding: .utf8)
			for token in unionTokens(in: generated) { union[token] = union[token] ?? "design-system" }
		}

		// the DS component sources: claims with owners + the escaped literal
		// forms the inventory scanner misses.
		if let dsSources {
			for (component, classes) in try dsComponentClaims(in: dsSources) {
				for name in classes {
					union[name] = component
					owners[name] = component
				}
			}
		}

		// the shipped sheet's selectors: every class the DS styles is a DS
		// class. owner defaults to a known component or the stylesheet itself.
		if let dsCSS, FileManager.default.fileExists(atPath: dsCSS) {
			let css = try String(contentsOfFile: dsCSS, encoding: .utf8)
			for token in classTokens(inCSS: css) {
				union[token] = owners[token] ?? "design-system.css"
			}
		}

		return union
	}

	/// scan DS component sources with the EXTENDED matcher: `class="…"`,
	/// escaped `class=\"…"` string-literal forms, `CSSRule("…", …)` and
	/// `@HotClass("…")` — attributing each class to the enclosing top-level
	/// `public struct WebUI…` (the same structural attribution the inventory
	/// scanner uses, plus the forms it misses).
	static func dsComponentClaims(in dir: String) throws -> [String: [String]] {
		var claims: [String: [String]] = [:]
		let files = try consumerSwiftFiles(in: dir)
		for file in files {
			let text = try String(contentsOfFile: file, encoding: .utf8)
			var current: String? = nil
			var pending: String? = nil
			var depth = 0
			for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
				let line = String(rawLine)
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if depth == 0, let m = componentHeader(in: trimmed) {
					pending = m
				}
				// class tokens on this line — all four extractions.
				var tokens: [String] = []
				tokens += classLiterals(in: line)
				tokens += escapedClassLiterals(in: line)
				tokens += cssRuleSelectors(in: line)
				tokens += hotClassTokens(in: line)
				tokens += tagEmissionTokens(in: line)
				let owner = current ?? pending
				if let owner {
					for t in tokens where !claims[owner, default: []].contains(t) {
						claims[owner, default: []].append(t)
					}
				}
				let opens = numBraces(line, char: "{")
				let closes = numBraces(line, char: "}")
				if depth == 0, opens > 0, pending != nil, current == nil {
					current = pending
				}
				depth += opens - closes
				if depth <= 0 {
					depth = 0
					current = nil
					pending = nil
				}
			}
		}
		// drop the DSL's own struct names from the value set (they are
		// components, not class claims) — the union stores CLASS names.
		var cleaned: [String: [String]] = [:]
		for (component, classes) in claims {
			cleaned[component] = Array(Set(classes)).sorted()
		}
		return cleaned
	}

	/// `class=\"…"` inside a Swift string literal (the escaped attribute form
	/// DS components actually emit: `" class=\"toast …\""`).
	static func escapedClassLiterals(in line: String) -> [String] {
		let pattern = /class=\\"([^"\\]*)/
		var out: [String] = []
		for m in line.matches(of: pattern) {
			out += String(m.1).split(separator: " ").map(String.init)
		}
		return out
	}

	/// `@HotClass("a", "b")` tokens.
	static func hotClassTokens(in line: String) -> [String] {
		guard let m = line.firstMatch(of: /@HotClass\s*\((.*?)\)/) else { return [] }
		let stringLit = /"((?:[^"\\]|\\.)*)"/
		return m.1.matches(of: stringLit).map { String($0.1) }
	}

	/// class tokens from the centralized `Tag` emission (feature G4): DS
	/// components now name classes as `Tag.classes(["toast", " toast--info"])`
	/// string literals instead of `class="…"` attribute spells. same
	/// ownership claim, new leg — the escaped-literal leg above is what the
	/// previous form fed, and the helper form is what lane R's rewrite left.
	static func tagEmissionTokens(in line: String) -> [String] {
		let call = /Tag\.classes\s*\(\s*\[(.*?)\]/
		let stringLit = /"((?:[^"\\]|\\.)*)"/
		var out: [String] = []
		for m in line.matches(of: call) {
			for s in m.1.matches(of: stringLit) {
				out += String(s.1).split(separator: " ").map(String.init)
			}
		}
		return out
	}

	// MARK: - the contract's built-in reference (9 shadowed classes)

	/// the minimal built-in reference: the nine classes arc's chrome sheet
	/// shadowed (CONTINUUM_DX §1.5's shadow policy), mapped to the DS side
	/// that owns them. with `--ds-sources`/`--ds-css` supplied these are
	/// replaced by the REAL owners from the scan/sheet; the built-in names are
	/// the honest, observable owners for the in-repo DS.
	static let builtInDSUnion: [String: String] = [
		"chip": "WebUIChip",
		"kv": "design-system.css",
		"toast": "WebUIToast",
		"modal-overlay": "WebUIModal",
		"log-line": "design-system.css",
		"md": "WebUIDesignSystemCore.markdownBody",
		"swatch": "design-system.css",
		"inline-edit": "WebUIInlineEdit",
		"tool-btn": "design-system.css",
	]

	// MARK: - the selector-extraction leg (consumer side)

	/// every exact class token a consumer sheet names, through all three legs.
	static func extractClassTokens(from text: String) -> [String] {
		var tokens: Set<String> = []
		for token in cssSelectors(in: text) { tokens.insert(token) }
		for token in cssRuleSelectors(in: text) { tokens.insert(token) }
		for token in classLiterals(in: text) { tokens.insert(token) }
		for token in escapedClassLiterals(in: text) { tokens.insert(token) }
		return Array(tokens).sorted()
	}

	/// class tokens from CSS selectors inside Swift string literals. a selector
	/// token is exact: `.chip` → `chip`, `.chip--primary` → `chip--primary`.
	static func cssSelectors(in text: String) -> [String] {
		var out: [String] = []
		let double = /"([^"\\\n]|\\.)*"/
		let triple = /"""[\s\S]*?"""/
		var literals: [String] = []
		for m in text.matches(of: triple) { literals.append(String(m.0)) }
		var singlePass = text
		for m in text.matches(of: triple) {
			singlePass = singlePass.replacingOccurrences(of: String(m.0), with: " ")
		}
		for m in singlePass.matches(of: double) { literals.append(String(m.0)) }
		for literal in literals {
			out += classTokens(inCSS: literal)
		}
		return Array(Set(out)).sorted()
	}

	/// class tokens from `CSSRule("…", …)` first-argument selectors.
	static func cssRuleSelectors(in text: String) -> [String] {
		let pattern = /CSSRule\s*\(\s*"([^"]*)"/
		var out: [String] = []
		for m in text.matches(of: pattern) {
			out += classTokens(inCSS: String(m.1))
		}
		return Array(Set(out)).sorted()
	}

	/// exact class tokens inside one CSS selector body
	/// (`.chip, .chip--primary:hover` → both).
	static func classTokens(inCSS css: String) -> [String] {
		var out: [String] = []
		// capture the identifier after a `.` (a lookbehind is not supported by
		// this SwiftPM regex engine — a capture is the portable form).
		let pattern = /\.([A-Za-z_][A-Za-z0-9_-]*)/
		for m in css.matches(of: pattern) {
			out.append(String(m.1))
		}
		return Array(Set(out)).sorted()
	}

	// MARK: - file discovery

	static func consumerSwiftFiles(in dir: String) throws -> [String] {
		guard FileManager.default.fileExists(atPath: dir) else {
			throw ToolError.unreadable("sources dir not found: \(dir)")
		}
		guard let enumerator = FileManager.default.enumerator(atPath: dir) else {
			throw ToolError.unreadable("cannot enumerate \(dir)")
		}
		var files: [String] = []
		while let relative = enumerator.nextObject() as? String {
			guard relative.hasSuffix(".swift") else { continue }
			guard !relative.contains("/.build/"), !relative.contains("/.git/") else { continue }
			files.append((dir as NSString).appendingPathComponent(relative))
		}
		return files.sorted()
	}

	/// the check never runs over DS sources: refuse paths that point into the
	/// framework's own component/style trees.
	static func isDesignSystemSource(_ path: String) -> Bool {
		let markers = [
			"/WebUIDesignSystemCore/", "/WebUIDesignSystem/", "/WebUI/",
			"/WebUIChart/", "/design-system", "/designer/assets/",
		]
		return markers.contains { path.contains($0) }
	}

	static func abbreviate(_ full: String, from root: String) -> String {
		guard full.hasPrefix(root) else { return full }
		return String(full.dropFirst(root.count + 1))
	}
}
