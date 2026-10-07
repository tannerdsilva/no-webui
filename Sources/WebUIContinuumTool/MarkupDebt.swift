import Foundation

// MARK: - markup-debt audit (MACRO_DX G3)
//
// the audit the migration lanes measure against, ADDITIVE to the one `lint`
// verb (never a second scanner). per file it counts five code-borne metrics:
//   rawTags        — distinct HTML element tags (`<div`, `</span>`, …) named
//                    by a closed element list, in code (comment-borne tags
//                    are stripped)
//   classLiterals  — `class="…"` attribute assignments (both the plain and
//                    the Swift-escaped `class=\"` spelling)
//   inlineStyles   — `style="…"` attribute assignments
//   literalColors  — `#hex` colour literals in code (the token-debt axis)
//   varRefs        — `var(--token)` css-variable references in code
//
// the framework allowlist (`Sources/WebUIDesignSystemCore/**` by default)
// separates legitimate framework emission — reported, never ratcheted — so a
// *consumer* sees its own number. the committed baseline
// (`designer/markup-debt.json`) freezes the starting point; `--fail-on-increase`
// turns any growth into an error. warn-only; numbers printed.

/// one file's debt counts. each field is an occurrence count, not a distinct
/// token count (a repeated tag on one line counts once per occurrence).
struct MarkupDebtMetrics: Codable, Equatable, Sendable {
	var rawTags: Int
	var classLiterals: Int
	var inlineStyles: Int
	var literalColors: Int
	var varRefs: Int

	static let zero = MarkupDebtMetrics(rawTags: 0, classLiterals: 0, inlineStyles: 0, literalColors: 0, varRefs: 0)

	static func + (lhs: MarkupDebtMetrics, rhs: MarkupDebtMetrics) -> MarkupDebtMetrics {
		MarkupDebtMetrics(
			rawTags: lhs.rawTags + rhs.rawTags,
			classLiterals: lhs.classLiterals + rhs.classLiterals,
			inlineStyles: lhs.inlineStyles + rhs.inlineStyles,
			literalColors: lhs.literalColors + rhs.literalColors,
			varRefs: lhs.varRefs + rhs.varRefs
		)
	}

	func hasAny() -> Bool {
		rawTags > 0 || classLiterals > 0 || inlineStyles > 0 || literalColors > 0 || varRefs > 0
	}

	/// the metrics that grew relative to `baseline` (nil when unchanged).
	func grown(over baseline: MarkupDebtMetrics) -> [String] {
		var names: [String] = []
		if rawTags > baseline.rawTags { names.append("tags \(baseline.rawTags) -> \(rawTags)") }
		if classLiterals > baseline.classLiterals { names.append("class \(baseline.classLiterals) -> \(classLiterals)") }
		if inlineStyles > baseline.inlineStyles { names.append("style \(baseline.inlineStyles) -> \(inlineStyles)") }
		if literalColors > baseline.literalColors { names.append("colors \(baseline.literalColors) -> \(literalColors)") }
		if varRefs > baseline.varRefs { names.append("var() \(baseline.varRefs) -> \(varRefs)") }
		return names
	}
}

/// the committed ratchet reference (`designer/markup-debt.json`).
struct MarkupDebtBaseline: Codable, Sendable {
	var version: Int
	var allowlistPrefixes: [String]
	var files: [String: MarkupDebtMetrics]

	static let currentVersion = 1

	static func load(_ path: String) throws -> MarkupDebtBaseline {
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		let baseline = try JSONDecoder().decode(MarkupDebtBaseline.self, from: data)
		guard baseline.version == currentVersion else {
			throw ToolError.unreadable("markup-debt baseline version \(baseline.version) != \(currentVersion) (at \(path))")
		}
		return baseline
	}
}

/// the closed list of real HTML/SVG elements a tag can name — a whitelist so
/// Swift generics (`<T>`, `<Div>`) can never be counted as markup.
let markupElementNames: Set<String> = [
	"a", "abbr", "address", "article", "aside", "audio", "b", "blockquote",
	"body", "br", "button", "canvas", "caption", "cite", "code", "col",
	"colgroup", "dd", "defs", "details", "dialog", "div", "dl", "dt", "em",
	"embed", "fieldset", "figcaption", "figure", "footer", "form", "g", "h1",
	"h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "i", "iframe",
	"img", "input", "label", "legend", "li", "line", "link", "main", "meta",
	"nav", "noscript", "object", "ol", "optgroup", "option", "p", "path",
	"picture", "polygon", "polyline", "pre", "rect", "script", "section",
	"select", "small", "source", "span", "strong", "style", "summary", "svg",
	"symbol", "table", "tbody", "td", "textarea", "tfoot", "th", "thead",
	"title", "tr", "track", "ul", "use", "video",
]

/// strip `//` line and `/* */` block comments so only CODE-BORNE markup counts,
/// honoring double-quoted string literals (so `"https://host/path"` survives a
/// `//` inside it) and newlines. a text scanner's documented limits: swift's
/// NESTED block comments are closed at depth (tracked), and single-line strings
/// only — the `"""` multiline form with an interior `//` is not special-cased.
func strippingComments(_ source: String) -> String {
	var out = [Character]()
	out.reserveCapacity(source.count)
	let chars = Array(source)
	var i = 0
	var inString = false
	var blockDepth = 0
	while i < chars.count {
		let c = chars[i]
		let next = i + 1 < chars.count ? chars[i + 1] : nil
		if blockDepth > 0 {
			if c == "/", next == "*" {
				blockDepth += 1
				i += 2
				continue
			}
			if c == "*", next == "/" {
				blockDepth -= 1
				i += 2
				continue
			}
			if c == "\n" { out.append(c) }
			i += 1
			continue
		}
		if inString {
			out.append(c)
			if c == "\\", let next {
				out.append(next)
				i += 2
				continue
			}
			// a single-line string literal cannot contain a raw newline, so an
			// UNTERMINATED quote must not swallow the following lines — that is
			// how a regex literal's character class (an odd number of quotes on
			// one line) used to make the next doc comment count as code
			// (MACRO_DX i2; found by lane G's re-pin).
			if c == "\n" {
				inString = false
				i += 1
				continue
			}
			if c == "\"" { inString = false }
			i += 1
			continue
		}
		if c == "\"" {
			inString = true
			out.append(c)
			i += 1
			continue
		}
		if c == "/", next == "*" {
			blockDepth = 1
			i += 2
			continue
		}
		if c == "/", next == "/" {
			// drop to end of line, keeping the newline itself.
			while i < chars.count, chars[i] != "\n" { i += 1 }
			continue
		}
		out.append(c)
		i += 1
	}
	return String(out)
}

/// the five debt metrics of one swift source (comment-stripped).
func markupDebtMetrics(in source: String) -> MarkupDebtMetrics {
	let text = strippingComments(source)
	let tagPattern = /<(\/?)([a-z][a-z0-9]*)(\s|\/?>|$)/
	var rawTags = 0
	for m in text.matches(of: tagPattern) {
		if markupElementNames.contains(String(m.2).lowercased()) { rawTags += 1 }
	}
	let classPattern = /class\s*=\\?"/
	let stylePattern = /style\s*=\\?"/
	let colorPattern = /#[0-9a-fA-F]{3,8}\b/
	let varPattern = /var\(\s*--[a-zA-Z0-9_-]+\s*\)/
	return MarkupDebtMetrics(
		rawTags: rawTags,
		classLiterals: text.matches(of: classPattern).count,
		inlineStyles: text.matches(of: stylePattern).count,
		literalColors: text.matches(of: colorPattern).count,
		varRefs: text.matches(of: varPattern).count
	)
}

/// one scanned tree: per-file metrics (keyed by the path as passed, so a
/// baseline generated from the package root compares against the same keys).
struct MarkupDebtScan {
	var files: [String: MarkupDebtMetrics]

	/// every `.swift` file under `dir`, recursively (hidden and `.build` trees
	/// skipped), so a consumer can point `--debt-sources` at a whole app
	/// `Sources/` tree. unlike the class-inventory scan, which is flat by
	/// contract, the audit walks the tree — a per-file report is meaningless
	/// if nested files are silently invisible.
	static func scanning(_ dir: String) throws -> MarkupDebtScan {
		guard FileManager.default.fileExists(atPath: dir) else {
			throw ToolError.unreadable("markup-debt sources dir not found: \(dir)")
		}
		var walk: [String] = []
		var pending = [dir]
		while let current = pending.popLast() {
			let entries: [String]
			do { entries = try FileManager.default.contentsOfDirectory(atPath: current) }
			catch { continue }
			for entry in entries.sorted() {
				if entry.hasPrefix(".") || entry == ".build" { continue }
				let path = (current as NSString).appendingPathComponent(entry)
				var isDir: ObjCBool = false
				FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
				if isDir.boolValue {
					pending.append(path)
				} else if entry.hasSuffix(".swift") {
					walk.append(path)
				}
			}
		}
		var out: [String: MarkupDebtMetrics] = [:]
		for file in walk.sorted() {
			let source = try String(contentsOfFile: file, encoding: .utf8)
			let metrics = markupDebtMetrics(in: source)
			if metrics.hasAny() { out[file] = metrics }
		}
		return MarkupDebtScan(files: out)
	}
}

/// print the per-file debt report for a list of scanned dirs.
func printMarkupDebt(dirs: [String], allowlistPrefixes: [String], baseline: MarkupDebtBaseline?, failOnIncrease: Bool) throws {
	var allFiles: [String: MarkupDebtMetrics] = [:]
	for dir in dirs {
		let scan = try MarkupDebtScan.scanning(dir)
		for (file, metrics) in scan.files { allFiles[file] = metrics }
	}
	let isAllowlisted = { (file: String) in allowlistPrefixes.contains { file.hasPrefix($0) } }

	var totals = MarkupDebtMetrics.zero
	var allowlistedTotals = MarkupDebtMetrics.zero
	var allowlistedCount = 0
	for (file, metrics) in allFiles.sorted(by: { $0.key < $1.key }) {
		totals = totals + metrics
		if isAllowlisted(file) {
			allowlistedCount += 1
			allowlistedTotals = allowlistedTotals + metrics
		}
	}

	print("[WebUIContinuumTool] markup debt (\(dirs.joined(separator: ", "))):")
	for (file, metrics) in allFiles.sorted(by: { $0.key < $1.key }) {
		let suffix = isAllowlisted(file) ? "  (framework allowlist — reported, not ratcheted)" : ""
		print("  \(file): tags=\(metrics.rawTags) class=\(metrics.classLiterals) style=\(metrics.inlineStyles) colors=\(metrics.literalColors) var=\(metrics.varRefs)\(suffix)")
	}
	print("  totals: tags=\(totals.rawTags) class=\(totals.classLiterals) style=\(totals.inlineStyles) colors=\(totals.literalColors) var=\(totals.varRefs)")
	if allowlistedCount > 0 {
		print("  allowlisted: \(allowlistedCount) file(s) — tags=\(allowlistedTotals.rawTags) class=\(allowlistedTotals.classLiterals) style=\(allowlistedTotals.inlineStyles) colors=\(allowlistedTotals.literalColors) var=\(allowlistedTotals.varRefs)")
	}

	guard let baseline else { return }

	var increases: [(file: String, details: [String])] = []
	for (file, metrics) in allFiles.sorted(by: { $0.key < $1.key }) {
		guard !isAllowlisted(file) else { continue }
		let reference = baseline.files[file] ?? .zero
		let grown = metrics.grown(over: reference)
		if !grown.isEmpty { increases.append((file, grown)) }
	}
	for entry in increases {
		print("warning: markup debt grew in \(entry.file): \(entry.details.joined(separator: ", "))")
	}
	print("  baseline: \(baseline.files.count) file(s) committed (allowlist: \(baseline.allowlistPrefixes.joined(separator: ", "))) — increases: \(increases.count)")
	if failOnIncrease, !increases.isEmpty {
		WebUIContinuumTool.writeError("WebUIContinuumTool: \\(increases.count) markup-debt increase(s) against the committed baseline (--fail-on-increase)")
		exit(1)
	}
}
