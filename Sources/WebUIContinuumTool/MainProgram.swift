import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - WebUIContinuumTool
//
// the static half of the continuum class machinery (plan d1 t1.3): scans the
// design-system core sources as TEXT and emits the generated class inventory
// (`Continuum+Generated.swift`) — per-component class sets, the union, and
// the attribute allowlist — plus a `lint` verb that warns on a class literal
// no inventory claims (WARN-ONLY in d1; the error level stays the landed
// orphan ratchet, `HTMLClassValidator` + `orphan-class-baseline.txt`).
//
// verbs (mirroring `WebUIIconTool`'s verb dispatch and `WebUIAssetTool`'s
// output style):
//   generate    -- sources -> Continuum+Generated.swift
//   lint        -- re-scan sources; warn on literals the generated inventory
//                  does not claim; exit 0 (warn-only in d1)
//   self/help
//
// the scanner reads sources as text on purpose (the plan's marker forms are
// strict and greppable); unknown constructs are reported, never guessed.

// MARK: - model

/// one component's claimed class vocabulary plus any `@HotClass` declarations.
struct ComponentInventory: Equatable {
	let name: String
	var literalClasses: [String] // class="..." literals inside this component
	var hotClasses: [String]     // @HotClass("a", "b") declarations
	var allClasses: [String] {
		Array(Set(literalClasses + hotClasses)).sorted()
	}
}

/// the full scan result for one run: components, union, unclaimed literals.
struct ScanResult: Equatable {
	var components: [ComponentInventory] = []
	var unclaimed: [String] = []
	var union: [String] {
		Array(Set(components.flatMap { $0.allClasses })).sorted()
	}
}

// MARK: - argument plumbing (same shape as WebUIIconTool.Args)

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

enum ToolError: LocalizedError {
	case missingOption(String)
	case missingSources
	case unreadable(String)

	var errorDescription: String? {
		switch self {
		case .missingOption(let o): return "missing value for \(o)"
		case .missingSources: return "no sources dir (use --sources <dir>)"
		case .unreadable(let m): return "unreadable: \(m)"
		}
	}
}

// MARK: - the scanner (text-level, strict markers)

/// find every `class="…"` literal and its enclosing component across the
/// design-system core sources.
func scanSources(_ dir: String) throws -> ScanResult {
	guard FileManager.default.fileExists(atPath: dir) else {
		throw ToolError.unreadable("sources dir not found: \(dir)")
	}
	let files: [String]
	do {
		files = try FileManager.default.contentsOfDirectory(atPath: dir)
			.filter { $0.hasSuffix(".swift") }
			.map { (dir as NSString).appendingPathComponent($0) }
			.sorted()
	} catch {
		throw ToolError.unreadable("cannot list \(dir): \(error)")
	}
	guard !files.isEmpty else { throw ToolError.missingSources }

	var result = ScanResult()
	for file in files {
		let source: String
		do { source = try String(contentsOfFile: file, encoding: .utf8) }
		catch { throw ToolError.unreadable("\(file): \(error.localizedDescription)") }
		scanFile(source, into: &result, fileName: (file as NSString).lastPathComponent)
	}
	return result
}

/// one line-oriented pass over a source file:
/// - attributes `class="…"` literals to the nearest enclosing top-level
///   `public struct WebUI…` (components open at brace depth 0; closures and
///   string interpolation inside bodies are the documented limits of a text
///   scanner);
/// - collects `@HotClass("a", "b")` declarations onto that component;
/// - literals found outside any component land in `unclaimed` (the lint warn).
func scanFile(_ source: String, into result: inout ScanResult, fileName: String) {
	var currentComponent: String? = nil
	var pendingHeader: String? = nil // header seen; its `{` not yet counted
	var depth = 0

	for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
		let text = String(rawLine)
		let trimmed = text.trimmingCharacters(in: .whitespaces)

		// a top-level component header names the region a `{` then opens.
		if depth == 0, let m = componentHeader(in: trimmed) {
			pendingHeader = m
		}

		// attribute `class="…"` tokens on this line (literals only — the
		// `class="\(var)"` interpolation form is out of the static scan).
		for token in classLiterals(in: text) {
			let owning = currentComponent ?? pendingHeader
			if let owning {
				appendUniqueClass(token, to: &result, component: owning)
			} else if !result.unclaimed.contains(token) {
				result.unclaimed.append(token)
			}
		}

		// `@HotClass("a", "b")` declarations attach to the current component.
		if let hot = hotClassMarker(in: text) {
			let owning = currentComponent ?? pendingHeader
			if let owning {
				appendHot(classes: hot, to: &result, component: owning)
			} else if !hot.isEmpty {
				// a marker outside any component is a strict-marker violation.
				for c in hot where !result.unclaimed.contains(c) { result.unclaimed.append(c) }
			}
		}

		// brace-depth bookkeeping after the line is scanned: a header's `{`
		// makes it the current component; a return to depth 0 closes it.
		let opens = numBraces(text, char: "{")
		let closes = numBraces(text, char: "}")
		if depth == 0, opens > 0, pendingHeader != nil {
			if currentComponent == nil, let h = pendingHeader {
				currentComponent = h
			}
		}
		depth += opens - closes
		if depth <= 0 {
			depth = 0
			currentComponent = nil
			pendingHeader = nil
		}
	}
	_ = fileName
}

func numBraces(_ text: String, char: Character) -> Int {
	text.reduce(0) { $0 + ($1 == char ? 1 : 0) }
}

// MARK: - text extractors

/// `public struct WebUI<Name>` (the component marker contract).
func componentHeader(in trimmed: String) -> String? {
	let pattern = /^public struct (WebUI[A-Za-z0-9_]+)(?::|\s*\{|\s*$)/
	guard let m = trimmed.firstMatch(of: pattern) else { return nil }
	return String(m.1)
}

/// every distinct literal class token on a line: `class="a b c"`.
func classLiterals(in text: String) -> [String] {
	let pattern = /class="([^"]*)"/
	var tokens: [String] = []
	for m in text.matches(of: pattern) {
		tokens.append(contentsOf: m.1.split(separator: " ").map(String.init))
	}
	// de-dupe per line (a class repeated on one line is one occurrence).
	return Array(Set(tokens)).sorted()
}

/// `@HotClass("a", "b")` — the d3 marker form the scanner must recognize
/// today (the macro lands later; the marker is the contract).
func hotClassMarker(in text: String) -> [String]? {
	let pattern = /@HotClass\s*\((.*?)\)/
	guard let m = text.firstMatch(of: pattern) else { return nil }
	let inner = String(m.1)
	let stringPattern = /"((?:[^"\\]|\\.)*)"/
	var out: [String] = []
	for sm in inner.matches(of: stringPattern) {
		out.append(String(sm.1))
	}
	return out
}

// MARK: - accumulation

func appendUniqueClass(_ token: String, to result: inout ScanResult, component: String) {
	if let idx = result.components.firstIndex(where: { $0.name == component }) {
		if !result.components[idx].literalClasses.contains(token) {
			result.components[idx].literalClasses.append(token)
		}
	} else {
		result.components.append(ComponentInventory(name: component, literalClasses: [token], hotClasses: []))
	}
}

func appendHot(classes: [String], to result: inout ScanResult, component: String) {
	if let idx = result.components.firstIndex(where: { $0.name == component }) {
		for c in classes where !result.components[idx].hotClasses.contains(c) {
			result.components[idx].hotClasses.append(c)
		}
	} else {
		result.components.append(ComponentInventory(name: component, literalClasses: [], hotClasses: classes))
	}
}

// MARK: - emission

/// the generated file: a self-describing value the WebUI target compiles.
func emitGenerated(_ scan: ScanResult) -> String {
	let components = scan.components
		.sorted { $0.name < $1.name }
		.map { c in
			"\t\t\t/// classes claimed by \(c.name)\n"
			+ "\t\t\t\"\(c.name)\": [\n"
			+ c.allClasses.map { "\t\t\t\t\"\($0)\"," }.joined(separator: "\n")
			+ "\n\t\t\t],"
		}
		.joined(separator: "\n")
	let union = scan.union.map { "\t\t\"\($0)\"," }.joined(separator: "\n")
	let unclaimed = scan.unclaimed.map { "\t\t\"\($0)\"," }.joined(separator: "\n")
	return """
// GENERATED FILE — do not edit. this is the static class inventory for the
// continuum (plan d1 t1.3): per-component class sets, the union, and the
// attribute allowlist. the build-tool plugin (`WebUIContinuumPlugin`) emits
// this from `Sources/WebUIDesignSystemCore/*.swift` on every build; the
// engine consumes the attr allowlist, and the landed orphan ratchet
// (`HTMLClassValidator`) consumes the rest as its static half.
//
// generated at build time by WebUIContinuumTool (never hand-edited).

/// the generated continuum class inventory.
public enum ContinuumClassInventory {
	/// per-component claimed class vocabularies (keys are component names).
	public static let components: [String: [String]] = [
\(components)
	]

	/// the union of every claimed class (per-component + @HotClass).
	public static let union: [String] = [
\(union)
	]

	/// attribute allowlist for the attr op (the generated base: class,
	/// aria-*, data-* — component-declared names extend it).
	public static let attributeAllowlist: [String] = [
		"class",
		"aria-*",
		"data-*",
	]

	/// literals the inventory does NOT claim (the lint warn source; warn-only
	/// in d1 — the error level stays the landed orphan ratchet).
	public static let unclaimedLiterals: [String] = [
\(unclaimed)
	]
}
"""
}

// MARK: - entry

@main
enum WebUIContinuumTool {
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
			case "self", "--self", "-h", "--help", "help": printSelf()
			default:
				writeError("unknown verb '\(verb)'")
				printSelf()
				exit(2)
			}
		} catch {
			writeError("error: \(error)")
			exit(1)
		}
	}

	private static func writeError(_ message: String) {
		let bytes = [UInt8]((message + "\n").utf8)
		bytes.withUnsafeBytes { buffer in
#if os(Linux)
			_ = Glibc.write(STDERR_FILENO, buffer.baseAddress, buffer.count)
#else
			_ = Darwin.write(STDERR_FILENO, buffer.baseAddress, buffer.count)
#endif
		}
	}

	static func printSelf() {
		print("""
		webui-continuum — the class inventory / build tooling for the continuum

		usage: webui-continuum <verb> [options]

		verbs:
		  generate       scan design-system core -> Continuum+Generated.swift
		                 --sources <dir> --output <path>
		  lint           re-scan sources; warn on class literals the generated
		                 inventory does not claim (warn-only in d1)
		                 --sources <dir> [--inventory <path>]
		""")
	}

	enum Run {
		static func generate(_ argv: [String]) throws {
			let sources = try Args.require(argv, "--sources")
			let output = try Args.require(argv, "--output")
			let scan = try scanSources(sources)
			// warn-only in d1: unclaimed literals are reported, never a
			// build failure (the error level stays the landed orphan ratchet).
			for name in scan.unclaimed.sorted() {
				print("warning: class literal '\(name)' is not claimed by any component inventory (add it to the owning component or an @HotClass vocabulary)")
			}
			let text = emitGenerated(scan)
			try text.write(toFile: output, atomically: true, encoding: .utf8)
			let n = scan.components.count
			let m = scan.union.count
			let k = scan.unclaimed.count
			// the build line the plugin reports.
			print("[WebUIContinuumPlugin] inventory: \(n) components, \(m) classes, \(k) unclaimed (warn)")
		}

		static func lint(_ argv: [String]) throws {
			let sources = try Args.require(argv, "--sources")
			let inventoryPath = Args.option(argv, "--inventory")
			let scan = try scanSources(sources)

			// the authoritative claim set: the union emitted into an existing
			// generated inventory (or, absent one, the fresh scan's union).
			var claimed = Set(scan.union)
			if let inventoryPath, FileManager.default.fileExists(atPath: inventoryPath) {
				let generated = try String(contentsOfFile: inventoryPath, encoding: .utf8)
				for token in unionTokens(in: generated) { claimed.insert(token) }
			}

			let warns = scan.unclaimed.filter { !claimed.contains($0) }
			for name in warns {
				print("warning: class literal '\(name)' is not claimed by any component inventory (add it to the owning component or an @HotClass vocabulary)")
			}
			let n = scan.components.count
			let m = scan.union.count
			print("[WebUIContinuumPlugin] inventory: \(n) components, \(m) classes, \(warns.count) unclaimed (warn)")
			// warn-only in d1: lint always exits 0 (the orphan ratchet owns the
			// error level).
		}

		/// the class tokens a generated inventory's `union` array owns.
		static func unionTokens(in generated: String) -> [String] {
			let pattern = /public static let union: \[String\] = \[(.*?)\]/
			guard let m = generated.firstMatch(of: pattern) else { return [] }
			let body = String(m.1)
			let token = /"([^"]*)"/
			var out: [String] = []
			for t in body.matches(of: token) { out.append(String(t.1)) }
			return out
		}
	}
}
