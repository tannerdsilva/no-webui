import Foundation
import WebUIBuild

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
// wave 2 (d2 t2.6): the `lint` verb also checks the capability grants — it
// reads `@HotView` descriptors for their `imports:` list, compares against
// the host grant list (a `ContinuumGrants` constant in the scanned sources,
// or `--grants`, or the framework default), and a mismatch is a BUILD ERROR
// with the parent plan's exact message shape:
//   island "feed" imports "surface_acquire" — not granted by the host
//   manifest (add it to ContinuumGrants or drop the import)
//
// verbs (mirroring `WebUIIconTool`'s verb dispatch and `WebUIAssetTool`'s
// output style):
//   generate    -- sources -> Continuum+Generated.swift
//   lint        -- re-scan sources; warn on literals the generated inventory
//                  does not claim (warn-only in d1) AND fail the build on a
//                  capability-import mismatch against the host grants
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

// MARK: - capability grants (d2 t2.6)

/// one `@HotView` declaration as the capability lint reads it: the island name
/// and its declared `imports:` list (normalized to wire names).
struct HotViewMarker: Equatable {
	let name: String
	let imports: [String]
	/// the declared `budget: IslandBudget(...)` pin, if any (t4.2).
	let pin: IslandPin?
}

/// a per-island budget pin declared by a `@HotView(..., budget: IslandBudget(...))`
/// marker (parent §1.3.5 `IslandBudget`, §t4.2). the plugin enforces these
/// against the built `.wasm`; islands without a pin ride the global ceiling.
struct IslandPin: Equatable {
	let name: String
	let maxBytes: Int
	let maxGzipBytes: Int?
}

/// the canonical capability table (parent §1.3.4): type name -> wire name.
/// the scanner accepts capability *types* (`SurfaceAcquisition.self`), dot
/// cases (`.surface_acquire`) and bare wire-name strings; every form is
/// normalized to the wire name the host manifest grants by.
let capabilityWireNames: [(type: String, wire: String)] = [
	("FrameSchedule", "frame_schedule"),
	("InputSubscription", "input_subscribe"),
	("SurfaceAcquisition", "surface_acquire"),
	("StatePersistence", "state_persist"),
	("ClockCapability", "clock"),
	("LogCapability", "log"),
]

/// the framework's default host grant list, parent §1.3.4: every capability
/// the engine implements today is granted by default. an app narrows the set
/// with a `ContinuumGrants` constant or `--grants`.
let defaultHostGrants: [String] = [
	"frame_schedule", "input_subscribe", "surface_acquire",
	"state_persist", "clock", "log",
]

/// strip the casing/noise from a capability token to its wire name:
/// `SurfaceAcquisition.self` -> `surface_acquire`, `.surface_acquire` ->
/// `surface_acquire`, `"surface_acquire"` -> `surface_acquire`, `clock` ->
/// `clock`. an unrecognized token is kept verbatim (the caller decides
/// whether that is a grantable name).
func normalizeCapabilityToken(_ raw: String) -> String {
	var t = raw.trimmingCharacters(in: .whitespaces)
	t = t.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
	if t.hasPrefix(".") { t = String(t.dropFirst()) }
	if t.hasSuffix(".self") { t = String(t.dropLast(".self".count)) }
	if let cap = capabilityWireNames.first(where: { $0.type == t }) { return cap.wire }
	return t
}

/// find every `@HotView(...)` marker in `source`. the body is scanned with a
/// balanced-paren walk so a `budget: IslandBudget(...)` nested call does not
/// truncate the marker. the marker form is the plan's contract (§1.4): a name
/// plus optional `imports:`/`budget:` labeled arguments.
func hotViewMarkers(in source: String) -> [HotViewMarker] {
	var markers: [HotViewMarker] = []
	var index = source.startIndex
	while index < source.endIndex {
		guard let markerStart = source[index...].range(of: "@HotView") else { break }
		let afterAttr = markerStart.upperBound
		guard let open = source[afterAttr...].firstIndex(of: "(") else {
			index = afterAttr
			continue
		}
		// balanced paren scan from `open` to its matching close.
		var depth = 0
		var cursor = open
		var close: String.Index? = nil
		while cursor < source.endIndex {
			let c = source[cursor]
			if c == "(" { depth += 1 }
			else if c == ")" {
				depth -= 1
				if depth == 0 { close = cursor; break }
			}
			cursor = source.index(after: cursor)
		}
		guard let close else {
			index = afterAttr
			continue
		}
		let body = String(source[source.index(after: open)..<close])
		if let marker = parseHotViewBody(body) {
			markers.append(marker)
		}
		index = source.index(close, offsetBy: 1)
	}
	return markers
}

/// parse one `@HotView` body into a marker. the body is split into top-level
/// comma-separated arguments at paren/bracket depth 0; the quoted name is the
/// first argument, and the `imports:` argument's tokens become the import
/// list (any list bracketed in `[...]` is expanded).
func parseHotViewBody(_ body: String) -> HotViewMarker? {
	let args = topLevelCommaSplit(body)
	guard let first = args.first else { return nil }
	// the island name is the first double-quoted string literal.
	guard let nameMatch = first.firstMatch(of: /"((?:[^"\\]|\\.)*)"/) else { return nil }
	let name = String(nameMatch.1)

	var imports: [String] = []
	var pin: IslandPin? = nil
	for arg in args.dropFirst() {
		let trimmed = arg.trimmingCharacters(in: .whitespaces)
		guard let label = trimmed.firstMatch(of: /^([A-Za-z_][A-Za-z0-9_]*)\s*:/) else { continue }
		let labelName = String(label.1)
		var value = String(trimmed[label.range.upperBound...]).trimmingCharacters(in: .whitespaces)
		if labelName == "imports" {
			if value.hasPrefix("[") {
				value.removeFirst()
				if value.hasSuffix("]") { value.removeLast() }
			}
			for token in topLevelCommaSplit(value) {
				let wire = normalizeCapabilityToken(token)
				guard !wire.isEmpty else { continue }
				if !imports.contains(wire) { imports.append(wire) }
			}
		} else if labelName == "budget" {
			pin = islandBudget(from: value, islandName: name)
		}
	}
	imports.sort()
	return HotViewMarker(name: name, imports: imports, pin: pin)
}

/// parse an `IslandBudget(...)` expression into a pin (t4.2): required
/// `maxBytes:` and optional `maxGzipBytes:` (default nil).
func islandBudget(from value: String, islandName: String) -> IslandPin? {
	guard let maxMatch = value.firstMatch(of: /maxBytes\s*:\s*(\d+)/) else { return nil }
	let maxBytes = Int(maxMatch.1) ?? 0
	let gz: Int?
	if let gzMatch = value.firstMatch(of: /maxGzipBytes\s*:\s*(\d+)/) {
		gz = Int(gzMatch.1)
	} else {
		gz = nil
	}
	return IslandPin(name: islandName, maxBytes: maxBytes, maxGzipBytes: gz)
}

/// every distinct island pin across the marker-bearing source dirs.
func islandPins(in sourceDirs: [String]) -> [IslandPin] {
	var pins: [IslandPin] = []
	for dir in sourceDirs {
		guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
		for file in files where file.hasSuffix(".swift") {
			let path = (dir as NSString).appendingPathComponent(file)
			guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
			for marker in hotViewMarkers(in: source) {
				guard let pin = marker.pin else { continue }
				if !pins.contains(where: { $0.name == pin.name }) { pins.append(pin) }
			}
		}
	}
	return pins.sorted { $0.name < $1.name }
}

/// split `text` on commas at paren/bracket/quote depth 0.
func topLevelCommaSplit(_ text: String) -> [String] {
	var parts: [String] = []
	var depth = 0
	var current = ""
	var quote: Character? = nil
	var escaped = false
	for c in text {
		if let q = quote {
			current.append(c)
			if escaped { escaped = false }
			else if c == "\\" { escaped = true }
			else if c == q { quote = nil }
		} else if c == "\"" || c == "'" {
			quote = c
			current.append(c)
		} else if c == "(" || c == "[" {
			depth += 1
			current.append(c)
		} else if c == ")" || c == "]" {
			depth -= 1
			current.append(c)
		} else if c == "," && depth == 0 {
			parts.append(current)
			current = ""
		} else {
			current.append(c)
		}
	}
	parts.append(current)
	return parts
}

/// the host grant list for a lint run: `--grants` wins; else a known
/// `ContinuumGrants` constant declaration in the scanned sources; else the
/// framework default (every engine capability).
func hostGrants(cli: String?, sourceDirs: [String]) -> [String] {
	if let cli {
		return cli.split(separator: ",").map(String.init).map(normalizeCapabilityToken)
			.filter { !$0.isEmpty }
	}
	for dir in sourceDirs {
		guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
		for file in files where file.hasSuffix(".swift") {
			let path = (dir as NSString).appendingPathComponent(file)
			guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
			// a `ContinuumGrants` constant: `ContinuumGrants = [...]` or a
			// `static let granted: [String] = [...]` inside a ContinuumGrants
			// enum/struct — grab the bracketed string literals.
			let marker = /ContinuumGrants[^\n]*\[\s*([^\]]*)\]/
			guard let m = source.firstMatch(of: marker) else { continue }
			let body = String(m.1)
			let token = /"((?:[^"\\]|\\.)*)"/
			var grants: [String] = []
			for t in body.matches(of: token) {
				let name = normalizeCapabilityToken(String(t.1))
				if !name.isEmpty, !grants.contains(name) { grants.append(name) }
			}
			if !grants.isEmpty { return grants.sorted() }
			break // a ContinuumGrants declaration was found; one per run
		}
	}
	return defaultHostGrants
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
			case "wasm-cross": try Run.wasmCross(rest)
			case "measure": try Run.measure(rest)
			case "scaffold": try Run.scaffold(rest)
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

	static func writeError(_ message: String) {
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
		                 [--engine-manifest <path>]  served content-addressed slice
		                 [--manifest <json>]         raw manifest (budget plugin)
		                 [--hotview-sources <dir>]   marker dirs for pins
		  lint           re-scan sources; warn on class literals the generated
		                 inventory does not claim (warn-only in d1) AND fail on
		                 capability-import mismatches against the host grants
		                 --sources <dir> [--inventory <path>]
		                 [--grants a,b,c] [--hotview-sources <dir>]...
		  wasm-cross     DX-5 autobuild: direct two-stage swiftc cross-compile of
		                 the island graph (island main -> WebUIIslandCore ->
		                 WebUISharedCore) for wasm32 with the embedded wasm sdk.
		                 emitted by WebUIAutobuildPlugin; no nested SwiftPM.
		                 --graph <pkg root> --product <Island> --obj <dir>
		                 --out <artifact.wasm> [--sdk <id>] [--swiftc <path>]
		                 [--mod-cache <dir>] [--no-strip]
		  measure        DX-3 auto-pin: scan the autobuild work dir for the
		                 cross-built island artifacts, emit the measured rows
		                 (sha/raw/gz + the pins maxBytes=ceil(raw*1.05) /
		                 maxGzipBytes=ceil(gz*1.05)) into the work-dir
		                 ContinuumManifest.json islands[] — the pin keys are
		                 EXACTLY the schema WebUIBudgetPlugin reads
		                 --work-dir <dir> --manifest <out.json>
		                 (emitted by WebUIAutobuildPlugin as its own llbuild
		                 command: artifact inputs -> manifest output)
		  scaffold      DX-2 onboarding verb: --add-island <Name> appends the
		                 two Package entries (product + executableTarget,
		                 append-only anchors) and generates Sources/<Name>/
		                 main.swift — the 3-line runtime form naming the
		                 macro-produced adapter <Name>.<Name>Island.
		                 --bootstrap --name <App> --framework <no-webui path>
		                 inserts the once-per-app inert continuum block (path
		                 dep + WebUIAutobuildPlugin on the app target).
		                 --print previews without writing; --package overrides
		                 the product-dep package name (default no-webui).
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

			// per-island budget pins ride the same scan (t4.2): `@HotView(..., budget:
			// IslandBudget(...))` markers anywhere in the marker-bearing sources.
			var sourceDirs = [sources]
			if let extra = Args.option(argv, "--hotview-sources") {
				sourceDirs += extra.split(separator: ",").map(String.init)
			}
			let pins = islandPins(in: sourceDirs)

			// the raw manifest: the same payload the served slice embeds, written
			// as plain json so the budget plugin reads the pins without decoding
			// the generated conformance.
			if let manifestPath = Args.option(argv, "--manifest") {
				let payload = manifestJSON(scan, pins: pins)
				try payload.write(toFile: manifestPath, atomically: true, encoding: .utf8)
			}

			// d2 §1.5: the engine-facing slice. the engine cannot read swift —
			// it receives its attr allowlist (and the class inventory) as a
			// served, content-addressed manifest, emitted through the same
			// WebUIAssetBuilder machinery as the css/js: one stamp (sha256
			// prefix), one gzip variant, one WebUIShippedAsset conformance the
			// host registers at a content-addressed url. this closes lane E's
			// wave-1 static-allowlist seed handoff (reconcile wires the fetch
			// at i2; the engine stays conservative until then).
			if let manifestPath = Args.option(argv, "--engine-manifest") {
				let payload = engineSliceJSON(scan, pins: pins)
				let receipt = try WebUIAssetBuilder.emit(
					shipped: payload,
					typeName: "ContinuumEngineManifest",
					options: WebUIAssetBuilder.Options(
						prose: .off,
						contentType: "application/json; charset=utf-8"
					),
					to: URL(fileURLWithPath: manifestPath)
				)
				print("[WebUIContinuumPlugin] engine slice: \(receipt.bytes) bytes, sha \(receipt.stamp), served at /ui/continuum-manifest.json?v=\(receipt.stamp)")
			}
		}

		/// the engine-facing manifest payload (parent §1.5): the attr allowlist
		/// the engine enforces on `attr` ops, the class inventory, and the
		/// per-island budget pins (t4.2). flat and self-describing so the
		/// reconciler wires the fetch without negotiation.
		static func engineSliceJSON(_ scan: ScanResult, pins: [IslandPin]) -> String {
			let components = scan.components
				.sorted { $0.name < $1.name }
				.map { c in
					"\"\(c.name)\":"
						+ "[\n"
						+ c.allClasses.map { "\t\t\t\"\($0)\"" }.joined(separator: ",\n")
						+ "\n\t\t]"
				}
				.joined(separator: ",\n")
			let union = scan.union.map { "\"\($0)\"" }.joined(separator: ",")
			let allowlist = ["\"class\"", "\"aria-*\"", "\"data-*\""].joined(separator: ",")
			let islands = pins.map { p in
				"{\"name\":\"\(p.name)\",\"maxBytes\":\(p.maxBytes)\(p.maxGzipBytes.map { ",\"maxGzipBytes\":\($0)" } ?? "")}"
			}.joined(separator: ",")
			return """
			{
			  "kind": "continuum-engine-slice",
			  "version": 1,
			  "attributeAllowlist": [\(allowlist)],
			  "components": {
			\(components)
			  },
			  "union": [\(union)],
			  "islands": [\(islands)]
			}
			"""
		}

		/// the same payload as the served slice, as plain json (the budget
		/// plugin reads this file — no conformance decoding needed).
		static func manifestJSON(_ scan: ScanResult, pins: [IslandPin]) -> String {
			engineSliceJSON(scan, pins: pins)
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

			// d2 t2.6: the capability-grants check. each `@HotView` marker's
			// `imports:` is compared against the host grant list; a mismatch is
			// a BUILD ERROR with the parent plan's exact message shape.
			var sourceDirs = [sources]
			if let extra = Args.option(argv, "--hotview-sources") {
				sourceDirs += extra.split(separator: ",").map(String.init)
			}
			let grants = Set(hostGrants(cli: Args.option(argv, "--grants"), sourceDirs: sourceDirs))
			var violations: [String] = []
			for dir in sourceDirs {
				guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
				for file in files where file.hasSuffix(".swift") {
					let path = (dir as NSString).appendingPathComponent(file)
					guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
					for marker in hotViewMarkers(in: source) {
						for importName in marker.imports where !grants.contains(importName) {
							violations.append("island \"\(marker.name)\" imports \"\(importName)\" — not granted by the host manifest (add it to ContinuumGrants or drop the import)")
						}
					}
				}
			}
			for violation in violations.sorted() {
				writeError(violation)
			}
			if !violations.isEmpty {
				writeError("WebUIContinuumTool: \(violations.count) capability-import violation(s) against the host grants (add the capabilities to ContinuumGrants or drop the imports)")
				exit(1)
			}
			// the build-tool plugin declares a cache stamp; only a clean scan
			// writes it, so a clean result is cached and a violation fails the
			// build (the stamp never lands). optional — direct `lint` runs
			// without the plugin skip the touch.
			if let touch = Args.option(argv, "--touch") {
				FileManager.default.createFile(atPath: touch, contents: Data("ok\n".utf8))
			}
			// warn-only in d1: class lint always exits 0 (the orphan ratchet
			// owns the class-error level); the capability check above is the
			// error level t2.6 adds.
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
