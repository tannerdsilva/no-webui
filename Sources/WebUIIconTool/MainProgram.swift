import Foundation

// MARK: - Entry

@main
enum WebUIIconTool {
	static func main() {
		let argv = Array(CommandLine.arguments.dropFirst())
		guard !argv.isEmpty else {
			printSelf()
			exit(1)
		}
		let verb = argv[0]
		let rest = Array(argv.dropFirst())
		do {
			switch verb {
			case "generate": try Run.generate(rest)
			case "lint": try Run.lint(rest)
			case "list": try Run.list(rest)
			case "stats": try Run.stats(rest)
			case "render-preview": try Run.renderPreview(rest)
			case "self", "--self", "-h", "--help", "help": printSelf()
			default:
				FileHandle.standardError.write(Data("unknown verb '\(verb)'\n".utf8))
				printSelf()
				exit(2)
			}
		} catch {
			FileHandle.standardError.write(Data("error: \(error)\n".utf8))
			exit(1)
		}
	}

	static func printSelf() {
		print("""
		webui-icons -- the svg iconography toolset for swiftui-for-web

		usage: webui-icons <verb> [options]

		verbs:
		  generate       manifest -> IconLibrary.swift (the build path)
		               --manifest <path> --swift-output <path>
		  lint           validate the manifest + report issues (CI gate)
		               --manifest <path>
		  list           print the catalog (human / agent discovery)
		               --manifest <path> [--grep <s>] [--category <c>] [--json]
		  stats          coverage + payload report
		               --manifest <path> [--json]
		  render-preview emit a self-contained visual QA page (all icons, sizes, themes)
		               --manifest <path> --output <file.html>
		""")
	}
}

// MARK: - Model

struct IconMeta: Equatable {
	let name: String
	let title: String
	let category: String
	let tags: [String]
	let viewBox: String
	let body: String
}

struct Manifest {
	var version: String = ""
	var license: String = ""
	var grid: Int = 24
	var strokeWidth: Double = 2
	var categories: [String] = []
	var icons: [IconMeta] = []
}

struct LintIssue: CustomStringConvertible {
	enum Severity: String { case error, warning }
	let severity: Severity
	let message: String
	var description: String { "[\(severity.rawValue.uppercased())] \(message)" }
}

// MARK: - Errors

enum ToolError: LocalizedError {
	case missingOption(String)
	case missingManifest
	case invalidManifest(String)
	case writeFailed(String)
	case noIcons

	var errorDescription: String? {
		switch self {
		case .missingOption(let o): return "missing value for \(o)"
		case .missingManifest: return "no manifest (use --manifest <path>)"
		case .invalidManifest(let m): return "invalid manifest: \(m)"
		case .writeFailed(let m): return "write failed: \(m)"
		case .noIcons: return "manifest contains no icons"
		}
	}
}

// MARK: - Argument parsing

enum Args {
	static func option(_ argv: [String], _ flag: String) -> String? {
		guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
		return argv[i + 1]
	}
	static func has(_ argv: [String], _ flag: String) -> Bool { argv.contains(flag) }
	static func require(_ argv: [String], _ flag: String) throws -> String {
		guard let v = option(argv, flag) else { throw ToolError.missingOption(flag) }
		return v
	}
}

// MARK: - Parser

enum ManifestParser {
	/// Load + parse the manifest JSON file into a `Manifest`.
	static func load(path: String) throws -> Manifest {
		guard FileManager.default.fileExists(atPath: path) else {
			throw ToolError.invalidManifest("file not found: \(path)")
		}
		let data: Data
		do { data = try Data(contentsOf: URL(fileURLWithPath: path)) }
		catch { throw ToolError.invalidManifest("unreadable: \(error.localizedDescription)") }

		let obj: [String: Any]
		do {
			let parsed = try JSONSerialization.jsonObject(with: data, options: [])
			guard let d = parsed as? [String: Any] else {
				throw ToolError.invalidManifest("top-level is not an object")
			}
			obj = d
		} catch {
			throw ToolError.invalidManifest("json parse: \(error.localizedDescription)")
		}

		var m = Manifest()
		if let meta = (obj["_meta"] as? [String: Any]) {
			m.version = (meta["version"] as? String) ?? m.version
			m.license = (meta["license"] as? String) ?? m.license
			m.grid = (meta["grid"] as? Int) ?? m.grid
			m.strokeWidth = (meta["strokeWidth"] as? Double) ?? Double((meta["strokeWidth"] as? Int) ?? 2)
			m.categories = (meta["categories"] as? [String]) ?? m.categories
		}

		guard let rawIcons = obj["icons"] as? [[String: Any]] else {
			throw ToolError.invalidManifest("'icons' must be an array of objects")
		}
		var icons: [IconMeta] = []
		for (idx, raw) in rawIcons.enumerated() {
			guard
				let name = raw["name"] as? String, !name.isEmpty,
				let title = raw["title"] as? String,
				let category = raw["category"] as? String,
				let elements = raw["elements"] as? [String]
			else {
				throw ToolError.invalidManifest("icon #\(idx) missing required fields (name/title/category/elements)")
			}
			let tags = (raw["tags"] as? [String]) ?? []
			let viewBox = (raw["viewBox"] as? String) ?? "0 0 \(m.grid) \(m.grid)"
			let body = elements.joined()
			icons.append(IconMeta(name: name, title: title, category: category, tags: tags, viewBox: viewBox, body: body))
		}
		m.icons = icons
		return m
	}

	/// Structural + geometric validation. Errors block the build; warnings don't.
	static func validate(_ m: Manifest) -> [LintIssue] {
		var issues: [LintIssue] = []
		if m.icons.isEmpty { issues.append(.init(severity: .error, message: "no icons present")) }

		var seen = Set<String>()
		for icon in m.icons {
			// 1. name charset (identifier-safe: lowercase letters, digits, hyphen)
			if !IconUtils.isValidName(icon.name) {
				issues.append(.init(severity: .error, message: "name '\(icon.name)' is not identifier-safe (use lowercase a-z0-9 and -)"))
			}
			// 2. uniqueness
			if seen.contains(icon.name) {
				issues.append(.init(severity: .error, message: "duplicate icon name '\(icon.name)'"))
			} else { seen.insert(icon.name) }
			// 3. body non-empty
			if icon.body.isEmpty {
				issues.append(.init(severity: .error, message: "'\(icon.name)' has no geometry (empty elements)"))
			}
			// 4. only allowed svg elements
			for el in IconUtils.splitElements(icon.body) where !IconUtils.isAllowedElement(el) {
				issues.append(.init(severity: .error, message: "'\(icon.name)' uses a disallowed element: \(el.prefix(40))..."))
				break
			}
			// 5. every element self-closes (balanced)
			for el in IconUtils.splitElements(icon.body) where !el.hasSuffix("/>") {
				issues.append(.init(severity: .error, message: "'\(icon.name)' has an unbalanced element: \(el.prefix(40))..."))
				break
			}
			// 6. no raw html / event handlers / scripts in the geometry
			if icon.body.contains("<script") || icon.body.range(of: #"on[a-z]+=""#, options: .regularExpression) != nil {
				issues.append(.init(severity: .error, message: "'\(icon.name)' body contains forbidden markup (script / on* handler)"))
			}
			// 7. coordinate sanity: all numeric literals within [0, grid]
			if let maxCoord = maxCoordinate(icon.body), maxCoord > Double(m.grid) + 0.5 {
				issues.append(.init(severity: .error, message: "'\(icon.name)' has a coordinate \(maxCoord) outside the \(m.grid)-unit viewBox"))
			}
			// 8. empty title
			if icon.title.trimmingCharacters(in: .whitespaces).isEmpty {
				issues.append(.init(severity: .warning, message: "'\(icon.name)' has an empty title"))
			}
			// 9. unknown category
			if !m.categories.isEmpty && !m.categories.contains(icon.category) {
				issues.append(.init(severity: .warning, message: "'\(icon.name)' uses undeclared category '\(icon.category)'"))
			}
		}
		return issues
	}

	/// Largest numeric literal in the body (bounds-checking the geometry).
	/// Numbers are tokenized per the SVG path grammar, so leading-decimal
	/// coordinates (".45" == 0.45) are read correctly and adjacent numbers are
	/// never concatenated into a spurious value (e.g. "0 .33", ".06.06").
	static func maxCoordinate(_ body: String) -> Double? {
		var maxV: Double?
		for token in tokenizeNumbers(body) {
			if let v = Double(token) { maxV = Swift.max(v, maxV ?? -.infinity) }
		}
		return maxV
	}

	/// Extract the signed numeric literals from an SVG path/attribute string.
	/// A number is an optional sign followed by digits with at most one dot. A new
	/// number begins -- even without a separator -- on a sign, or on a dot when the
	/// active number already carries one ("-.35-3.83" -> "-.35","-3.83"). Any other
	/// character ends the active number. Leading decimals are kept as-is (".83").
	static func tokenizeNumbers(_ s: String) -> [String] {
		var out: [String] = []
		var cur = ""
		var active = false
		var dotUsed = false
		var hasDigit = false

		func flush() {
			if active && hasDigit { out.append(cur) }
			cur = ""; active = false; dotUsed = false; hasDigit = false
		}

		for ch in s {
			switch ch {
			case "+", "-":
				flush()
				cur = String(ch); active = true
			case ".":
				if active && dotUsed {
					flush()
					cur = "."; active = true; dotUsed = true
				} else if active {
					cur.append("."); dotUsed = true
				} else {
					cur = "."; active = true; dotUsed = true
				}
			default:
				if ch.isNumber {
					if !active { cur = ""; active = true }
					cur.append(ch); hasDigit = true
				} else {
					flush()
				}
			}
		}
		flush()
		return out
	}
}

// MARK: - Icon utilities

enum IconUtils {
	static let allowedTags: Set<String> = ["circle", "line", "rect", "path", "polygon", "polyline", "ellipse"]

	static func isValidName(_ s: String) -> Bool {
		guard let first = s.first else { return false }
		if first.isNumber || first == "-" { return false }
		return s.allSatisfy { $0.isLetter && $0.isLowercase || $0.isNumber || $0 == "-" }
	}

	static func isAllowedElement(_ el: String) -> Bool {
		guard el.hasPrefix("<") else { return false }
		let tag = el.dropFirst().prefix(while: { $0.isLetter }).lowercased()
		return allowedTags.contains(String(tag))
	}

	/// Split a packed element string back into individual `<.../>` tokens.
	static func splitElements(_ body: String) -> [String] {
		var out: [String] = []
		var current = ""
		for ch in body {
			if ch == "<" && !current.isEmpty { out.append(current); current = "" }
			current.append(ch)
		}
		if !current.isEmpty { out.append(current) }
		return out
	}

	/// snake_case / kebab -> camelCase (first word lowercase). "git-pull-request" -> "gitPullRequest".
	static func camelCase(_ raw: String) -> String {
		let parts = raw.split(separator: "-").map(String.init)
		guard let first = parts.first else { return raw }
		let head = first.lowercased()
		let tail = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
		return (head + tail.joined())
	}

	/// A valid Swift case identifier for this icon name; reserved words are
	/// backtick-escaped (e.g. "repeat" -> `repeat`).
	static func swiftCaseName(_ raw: String) -> String {
		let camel = camelCase(raw)
		return reservedWords.contains(camel) ? "`\(camel)`" : camel
	}

	static let reservedWords: Set<String> = [
		"repeat", "default", "super", "self", "Self", "Type", "Protocol",
		"Any", "in", "out", "inout", "var", "let", "func", "init", "class",
		"struct", "enum", "import", "return", "switch", "case", "where",
		"as", "is", "throw", "try", "catch", "guard", "if", "else", "while",
		"for", "do", "defer", "await", "yield", "resume", "borrow", "consume",
		"open", "internal", "public", "private", "fileprivate", "static",
		"final", "override", "lazy", "weak", "unowned", "mutating",
		"nonmutating", "indirect", "optional", "associatedtype", "deinit",
		"extension", "precedencegroup", "pound",
	]
}

// MARK: - Swift generator

enum SwiftGenerator {
	/// Emit the full `IconLibrary.swift` source (deterministic; no timestamps).
	static func iconLibrary(_ m: Manifest) -> String {
		let icons = m.icons.sorted { $0.name < $1.name }
		var s = ""
		s += "// generated by webui-icons -- do not edit.\n"
		s += "// source: designer/icons/icon-manifest.json (version \(m.version), grid \(m.grid), stroke \(fmt(m.strokeWidth)))\n"
		s += "// license: \(m.license)\n"
		s += "import Foundation\n\n"

		// MARK: IconName
		s += "// MARK: - IconName\n"
		s += "/// A typed icon identifier resolved against the generated catalog.\n"
		s += "public enum IconName: String, CaseIterable, Sendable, Comparable {\n"
		for icon in icons {
			s += "\tcase \(IconUtils.swiftCaseName(icon.name)) = \"\(icon.name)\"\n"
		}
		s += "\n"
		s += "\tpublic static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }\n"
		s += "\tpublic var title: String { WebUIIcons.meta(for: self)?.title ?? rawValue }\n"
		s += "\tpublic var category: WebUIIcons.Category { WebUIIcons.meta(for: self)?.category ?? .other }\n"
		s += "\tpublic var tags: [String] { WebUIIcons.meta(for: self)?.tags ?? [] }\n"
		s += "\tpublic var viewBox: String { WebUIIcons.meta(for: self)?.viewBox ?? \"0 0 24 24\" }\n"
		s += "\tpublic var body: String { WebUIIcons.meta(for: self)?.body ?? \"\" }\n"
		s += "}\n\n"

		// MARK: WebUIIcons catalog
		s += "// MARK: - WebUIIcons catalog\n"
		s += "/// The generated icon catalog: typed metadata for every icon in the manifest.\n"
		s += "public enum WebUIIcons {\n"
		s += "\tpublic enum Category: String, CaseIterable, Sendable {\n"
		for c in m.categories.sorted() {
			s += "\t\tcase \(IconUtils.camelCase(c)) = \"\(c)\"\n"
		}
		s += "\t\tcase other = \"other\"\n"
		s += "\t}\n"
		s += "\n"
		s += "\tpublic struct Meta: Sendable, Equatable {\n"
		s += "\t\tpublic let name: String\n"
		s += "\t\tpublic let title: String\n"
		s += "\t\tpublic let category: Category\n"
		s += "\t\tpublic let tags: [String]\n"
		s += "\t\tpublic let viewBox: String\n"
		s += "\t\tpublic let body: String\n"
		s += "\t}\n"
		s += "\n"
		s += "\tpublic static let all: [Meta] = [\n"
		for icon in icons {
			let cat = m.categories.contains(icon.category) ? ".\(IconUtils.camelCase(icon.category))" : ".other"
			s += "\t\tMeta(name: \(str(icon.name)), title: \(str(icon.title)), category: \(cat), tags: [\(icon.tags.map(str).joined(separator: ", "))], viewBox: \(str(icon.viewBox)), body: \(str(icon.body))),\n"
		}
		s += "\t]\n"
		s += "\n"
		s += "\tprivate static let byName: [String: Meta] = { var d: [String: Meta] = [:]; for m in all { d[m.name] = m }; return d }()\n"
		s += "\n"
		s += "\tpublic static func meta(for name: IconName) -> Meta? { byName[name.rawValue] }\n"
		s += "\tpublic static func meta(named raw: String) -> Meta? { byName[raw] }\n"
		s += "\tpublic static func byCategory(_ c: Category) -> [Meta] { all.filter { $0.category == c } }\n"
		s += "\tpublic static var count: Int { all.count }\n"
		s += "}\n"
		return s
	}

	static func str(_ v: String) -> String { "\"" + escape(v) + "\"" }
	static func fmt(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v) }
	static func escape(_ s: String) -> String {
		s.replacingOccurrences(of: "\\", with: "\\\\")
		 .replacingOccurrences(of: "\"", with: "\\\"")
	}
}

// MARK: - Preview generator

enum PreviewGenerator {
	/// A self-contained HTML page that renders every icon at three sizes in both themes.
	static func html(_ m: Manifest) -> String {
		let icons = m.icons.sorted { $0.name < $1.name }
		var s = ""
		s += "<!doctype html>\n<html lang=\"en\"><head>\n<meta charset=\"utf-8\">\n"
		s += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
		s += "<title>webui-icons -- preview</title>\n"
		s += "<style>\n"
		s += "*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}\n"
		s += ":root{--bg:#f4f6f8;--card:#ffffff;--text:#0f172a;--muted:#5f6f86;--border:#d4dbe3;--accent:#6366f1;--shadow:0 1px 2px rgba(15,23,42,.06),0 1px 3px rgba(15,23,42,.1)}\n"
		s += "@media(prefers-color-scheme:dark){:root{--bg:#060910;--card:#0c111c;--text:#e7ecf5;--muted:#8494ab;--border:#1e293b;--shadow:0 1px 2px rgba(0,0,0,.4)}}\n"
		s += "body{font:15px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);padding:32px;max-width:1200px;margin:0 auto}\n"
		s += "h1{font-size:1.5rem;font-weight:700;letter-spacing:-.02em}\n"
		s += ".sub{color:var(--muted);margin-top:4px;margin-bottom:28px;font-size:.9rem}\n"
		s += ".cat{margin-bottom:28px}\n"
		s += ".cat h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted);margin-bottom:10px;padding-bottom:6px;border-bottom:1px solid var(--border)}\n"
		s += ".grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:8px}\n"
		s += ".cell{display:flex;align-items:center;gap:10px;background:var(--card);border:1px solid var(--border);border-radius:8px;padding:10px;box-shadow:var(--shadow)}\n"
		s += ".cell .sizes{display:flex;align-items:center;gap:8px;color:var(--accent)}\n"
		s += ".cell .name{font-family:ui-monospace,Menlo,monospace;font-size:.72rem;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}\n"
		s += ".count{font-variant-numeric:tabular-nums}\n"
		s += "</style>\n</head>\n<body>\n"
		s += "<h1>webui-icons -- preview</h1>\n"
		s += "<p class=\"sub\"><span class=\"count\">\(icons.count)</span> icons | grid \(m.grid) | stroke \(SwiftGenerator.fmt(m.strokeWidth)) | \(m.license)</p>\n"
		for cat in m.categories.sorted() {
			let group = icons.filter { $0.category == cat }.sorted { $0.name < $1.name }
			s += "<div class=\"cat\"><h2>\(cat) <span class=\"count\">(\(group.count))</span></h2><div class=\"grid\">\n"
			for icon in group {
				s += "<div class=\"cell\"><div class=\"sizes\">\(svg(icon, w: 16, h: 16))\(svg(icon, w: 24, h: 24))\(svg(icon, w: 32, h: 32))</div><div class=\"name\" title=\"\(icon.title)\">\(icon.name)</div></div>\n"
			}
			s += "</div></div>\n"
		}
		s += "</body>\n</html>\n"
		return s
	}

	static func svg(_ icon: IconMeta, w: Int, h: Int) -> String {
		"<svg viewBox=\"\(icon.viewBox)\" width=\"\(w)\" height=\"\(h)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"butt\" stroke-linejoin=\"miter\" aria-hidden=\"true\">\(icon.body)</svg>"
	}
}

// MARK: - Runners

enum Run {
	static func manifest(_ argv: [String]) throws -> Manifest {
		guard let path = Args.option(argv, "--manifest") else { throw ToolError.missingManifest }
		return try ManifestParser.load(path: path)
	}

	static func generate(_ argv: [String]) throws {
		guard let out = Args.option(argv, "--swift-output") else { throw ToolError.missingOption("--swift-output") }
		let m = try manifest(argv)
		let issues = ManifestParser.validate(m)
		for e in issues where e.severity == .error {
			throw ToolError.invalidManifest(e.message)
		}
		let src = SwiftGenerator.iconLibrary(m)
		try src.write(toFile: out, atomically: true, encoding: .utf8)
		print("webui-icons: generated \(m.icons.count) icons -> \(out) (\(src.utf8.count) bytes)")
	}

	static func lint(_ argv: [String]) throws {
		let m = try manifest(argv)
		let issues = ManifestParser.validate(m)
		let errors = issues.filter { $0.severity == .error }
		let warnings = issues.filter { $0.severity == .warning }
		for i in issues { print(i) }
		print("\(m.icons.count) icons | \(errors.count) error(s) | \(warnings.count) warning(s)")
		if !errors.isEmpty { throw ToolError.invalidManifest("\(errors.count) error(s)") }
	}

	static func list(_ argv: [String]) throws {
		let m = try manifest(argv)
		var icons = m.icons.sorted { $0.name < $1.name }
		if let g = Args.option(argv, "--grep") {
			let q = g.lowercased()
			icons = icons.filter { $0.name.contains(q) || $0.title.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }
		}
		if let c = Args.option(argv, "--category") {
			icons = icons.filter { $0.category == c }
		}
		if Args.has(argv, "--json") {
			let arr: [[String: Any]] = icons.map {
				["name": $0.name, "title": $0.title, "category": $0.category, "tags": $0.tags, "viewBox": $0.viewBox]
			}
			let data = try JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys, .prettyPrinted])
			FileHandle.standardOutput.write(data)
			print("")
			return
		}
		for icon in icons {
			print(pad(icon.name, 24) + "  " + pad(icon.category, 4) + "  " + icon.title)
		}
		print("\n\(icons.count) of \(m.icons.count) icons")
	}

	static func pad(_ s: String, _ width: Int) -> String {
		s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
	}

	static func stats(_ argv: [String]) throws {
		let m = try manifest(argv)
		let byCat = Dictionary(grouping: m.icons, by: { $0.category }).mapValues { $0.count }
		let totalBytes = m.icons.reduce(0) { $0 + $1.body.utf8.count }
		let totalElems = m.icons.reduce(0) { $0 + IconUtils.splitElements($1.body).count }
		let maxIcon = m.icons.max { $0.body.utf8.count < $1.body.utf8.count }
		if Args.has(argv, "--json") {
			let obj: [String: Any] = [
				"icons": m.icons.count,
				"categories": byCat,
				"totalBodyBytes": totalBytes,
				"avgBodyBytes": m.icons.isEmpty ? 0 : totalBytes / m.icons.count,
				"avgElements": m.icons.isEmpty ? 0.0 : Double(totalElems) / Double(m.icons.count),
				"largest": maxIcon.map { ["name": $0.name, "bytes": $0.body.utf8.count] } ?? [:],
				"grid": m.grid,
				"strokeWidth": m.strokeWidth,
			]
			let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted])
			FileHandle.standardOutput.write(data)
			print("")
			return
		}
		print("icons:        \(m.icons.count)")
		print("grid:         \(m.grid)   stroke: \(SwiftGenerator.fmt(m.strokeWidth))")
		print("body payload: \(totalBytes) bytes   (avg \(m.icons.isEmpty ? 0 : totalBytes / m.icons.count)/icon)")
		print("elements:     \(totalElems)   (avg \(String(format: "%.1f", totalElems == 0 ? 0 : Double(totalElems) / Double(m.icons.count)))/icon)")
		if let maxIcon { print("largest:      \(maxIcon.name) (\(maxIcon.body.utf8.count) bytes)") }
		print("\nby category:")
		for (c, n) in byCat.sorted(by: { $0.key < $1.key }) {
			print("  " + pad(c, 14) + " " + String(n))
		}
	}

	static func renderPreview(_ argv: [String]) throws {
		guard let out = Args.option(argv, "--output") else { throw ToolError.missingOption("--output") }
		let m = try manifest(argv)
		try PreviewGenerator.html(m).write(toFile: out, atomically: true, encoding: .utf8)
		print("webui-icons: rendered preview for \(m.icons.count) icons -> \(out)")
	}
}
