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
		let attr = /class\s*=\s*["']([^"']*)["']/
		for match in html.matches(of: attr) {
			for token in match.output.1.split(whereSeparator: \.isWhitespace) {
				let name = String(token)
				if known.contains(name) { continue }
				if prefixes.contains(where: { name.hasPrefix($0) }) { continue }
				unknown.insert(name)
			}
		}
		return unknown.sorted()
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
			// index init cannot fail (structurally guaranteed) — unwrap.
			let lower = String.UTF8View.Index(match.range.lowerBound, within: css)!
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
