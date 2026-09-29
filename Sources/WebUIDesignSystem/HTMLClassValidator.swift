import Foundation
import Synchronization

/// dev-time guardrail for the string seam. the framework renders raw html
/// strings, so an undefined design-system class silently renders unstyled and
/// no test catches it. this validator answers "which classes on a rendered
/// document are not defined in the shipped sheet" so hosts can log or fail
/// while iterating.
public struct HTMLClassReport: Sendable {
	/// classes found on rendered elements but absent from the shared sheet,
	/// sorted and deduplicated. page-scoped classes passed via `extra` are
	/// treated as known and never appear here.
	public let undefined: [String]
}

public enum HTMLClassValidator {
	/// called once per undefined class, in report order. nil (the default)
	/// silences validation entirely. hosts wire this to their logger or to a
	/// test assertion; the showcase hooks it in dev mode.
	public static var onUndefined: (@Sendable (String) -> Void)? {
		get { _hook.withLock { $0 } }
		set { _hook.withLock { $0 = newValue } }
	}

	private static let _hook = Mutex<(@Sendable (String) -> Void)?>(nil)
	private static let _defined = Mutex<Set<String>?>(nil)
	private static let _prefixes = Mutex<[String]>(["chart__"])

	/// register a class-name prefix as framework-defined (the toolkit's own
	/// inline-styled families — e.g. `WebUIChart`'s `chart__*` marks, which
	/// carry their presentation in `style=` attributes rather than sheet
	/// rules). classes matching a registered prefix are never flagged. the
	/// chart prefix is pre-registered; hosts with other inline-styled
	/// families add their own once at startup.
	public static func registerKnownPrefix(_ prefix: String) {
		_prefixes.withLock { values in
			if !values.contains(prefix) { values.append(prefix) }
		}
	}

	/// every class selector the shipped sheet declares, parsed once and
	/// cached. a best-effort scan: class tokens in compound selectors
	/// (`div.card`) count; decimal-number dots (`1.5rem`) do not. passing an
	/// explicit `css` bypasses the cache (used by tests and page-scoped
	/// sheets) — only the default full-sheet parse is memoised.
	public static func definedClasses(css: String? = nil) -> Set<String> {
		let source = css ?? DesignSystemAssets.minifiedCss
		if css == nil, let cached = _defined.withLock({ $0 }) { return cached }
		let parsed = parseClasses(in: source)
		if css == nil { _defined.withLock { $0 = parsed } }
		return parsed
	}

	/// class tokens present on `class="..."` attributes in `html` that are
	/// neither in the shipped sheet, nor matching a registered prefix, nor in
	/// `extra` (page-scoped classes).
	public static func undefinedClasses(in html: String, extra: Set<String> = []) -> [String] {
		let known = definedClasses().union(extra)
		let prefixes = _prefixes.withLock { $0 }
		var unknown = Set<String>()
		for name in classTokens(in: html) {
			if known.contains(name) { continue }
			if prefixes.contains(where: { name.hasPrefix($0) }) { continue }
			unknown.insert(name)
		}
		return unknown.sorted()
	}

	/// class tokens the sheet defines that no supplied html emits — the inverse
	/// of `undefinedClasses(in:)`. the forward check catches "styled nothing";
	/// this one catches "styled but unreachable from any api". `extra` carries
	/// js-toggled and page-scoped names so they never read as orphans.
	public static func orphanClasses(in htmls: [String], extra: Set<String> = []) -> [String] {
		var emitted = Set<String>()
		for html in htmls { emitted.formUnion(classTokens(in: html)) }
		return definedClasses().subtracting(emitted).subtracting(extra).sorted()
	}

	/// every class token appearing on a `class="..."` attribute in `html`.
	///
	/// a byte scanner, not `Swift Regex`: this runs over a whole rendered page
	/// (the showcase is ~166 KB), and the regex form cost ~42 ms per page — more
	/// than the page's own render. the scan below is a single pass with no
	/// backtracking and no per-match allocation beyond the token itself.
	private static func classTokens(in html: String) -> Set<String> {
		var tokens = Set<String>()
		let bytes = Array(html.utf8)
		let n = bytes.count
		// ascii codes
		let c: UInt8 = 0x63, l: UInt8 = 0x6C, a: UInt8 = 0x61, s: UInt8 = 0x73
		let eq: UInt8 = 0x3D, dq: UInt8 = 0x22, sq: UInt8 = 0x27
		var i = 0
		while i < n {
			guard bytes[i] == c else { i += 1; continue }
			// literal `class`
			guard i + 5 <= n, bytes[i + 1] == l, bytes[i + 2] == a,
				  bytes[i + 3] == s, bytes[i + 4] == s else { i += 1; continue }
			var j = i + 5
			while j < n, isASCIISpace(bytes[j]) { j += 1 }
			guard j < n, bytes[j] == eq else { i += 1; continue }
			j += 1
			while j < n, isASCIISpace(bytes[j]) { j += 1 }
			guard j < n, bytes[j] == dq || bytes[j] == sq else { i += 1; continue }
			let quote = bytes[j]
			j += 1
			let valueStart = j
			while j < n, bytes[j] != quote { j += 1 }
			// split the value on ascii whitespace
			var t = valueStart
			while t < j {
				while t < j, isASCIISpace(bytes[t]) { t += 1 }
				let tokenStart = t
				while t < j, !isASCIISpace(bytes[t]) { t += 1 }
				if t > tokenStart {
					tokens.insert(String(decoding: bytes[tokenStart..<t], as: UTF8.self))
				}
			}
			i = j
		}
		return tokens
	}

	private static func isASCIISpace(_ b: UInt8) -> Bool {
		b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0B || b == 0x0C
	}

	/// run a report and route each undefined class through `onUndefined` once.
	/// returns the report for hosts that want to fail hard on it.
	@discardableResult
	public static func report(html: String, extra: Set<String> = []) -> HTMLClassReport {
		let report = HTMLClassReport(undefined: undefinedClasses(in: html, extra: extra))
		if let hook = onUndefined {
			for name in report.undefined { hook(name) }
		}
		return report
	}

	// a class token must not follow a digit (`1.5rem`) or another dot, and
	// must itself start with a letter or underscore — number literals can
	// never be classes. swift regex has no lookbehind, so check the preceding
	// byte on each `.token` candidate directly.
	private static func parseClasses(in css: String) -> Set<String> {
		let candidate = /\.([A-Za-z_][A-Za-z0-9_-]*)/
		let bytes = Array(css.utf8)
		var classes = Set<String>()
		for match in css.matches(of: candidate) {
			// the match range is a character index into `css`, so the utf8 view
			// index init does not fail for this input — but skip the candidate
			// rather than trap if a future pattern breaks that assumption.
			guard let lower = String.UTF8View.Index(match.range.lowerBound, within: css) else { continue }
			let pos = css.utf8.distance(from: css.utf8.startIndex, to: lower)
			if pos > 0 {
				let prev = bytes[pos - 1]
				if prev == 46 || (prev >= 48 && prev <= 57) { continue }
			}
			classes.insert(String(match.output.1))
		}
		return classes
	}
}
