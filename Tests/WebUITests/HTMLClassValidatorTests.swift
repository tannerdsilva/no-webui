import Foundation
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
import WebUIShowcaseContent

// MARK: - HTMLClassValidator

@Suite("HTMLClassValidator", .serialized)
struct HTMLClassValidatorTests {
	@Test("definedClasses parses component, modifier, and __body selectors")
	func definedClassesCore() {
		let defined = HTMLClassValidator.definedClasses()
		#expect(defined.contains("button"))
		#expect(defined.contains("button--primary"))
		#expect(defined.contains("card"))
		#expect(defined.contains("card__body"))
		#expect(defined.contains("input"))
	}

	@Test("parse skips decimal-number dots")
	func parseSkipsDecimals() {
		// `1.5rem`, `0.5`, and `.25` are values, not classes.
		let css = "a{width:1.5rem;line-height:0.5;opacity:.25}div.card{display:block}"
		let defined = HTMLClassValidator.definedClasses(css: css)
		#expect(defined.contains("card"))
		#expect(!defined.contains("5rem"))
		#expect(!defined.contains("25"))
	}

	@Test("undefinedClasses flags a bogus class but accepts real ones")
	func flagsBogusOnly() {
		let html = #"<div class="card card--elevated bogus-undefined-xyz"><button class="button button--primary">go</button></div>"#
		let undefined = HTMLClassValidator.undefinedClasses(in: html)
		#expect(undefined == ["bogus-undefined-xyz"])
	}

	@Test("extra silences page-scoped classes")
	func extraAllowsPageClasses() {
		let html = #"<div class="page-shell demo-card-body">x</div>"#
		let undefined = HTMLClassValidator.undefinedClasses(
			in: html,
			extra: ["page-shell", "demo-card-body"]
		)
		#expect(undefined.isEmpty)
	}

	@Test("report routes each undefined class through the hook once")
	func reportHooks() {
		let seen = LockedBox([String]())
		HTMLClassValidator.onUndefined = { seen.append($0) }
		defer { HTMLClassValidator.onUndefined = nil }

		let html = #"<div class="card nope-a nope-b"><button class="button">ok</button></div>"#
		let report = HTMLClassValidator.report(html: html, extra: ["ok"])
		#expect(report.undefined == ["nope-a", "nope-b"])
		#expect(seen.value.sorted() == ["nope-a", "nope-b"])
	}

	@Test("a clean component page produces no undefined classes")
	func cleanPageIsQuiet() {
		let seen = LockedBox([String]())
		HTMLClassValidator.onUndefined = { seen.append($0) }
		defer { HTMLClassValidator.onUndefined = nil }

		let body = VStack(spacing: 16) {
			WebUIButton("Go", variant: .primary)
			WebUICard { Text("card") }
			WebUIInput(placeholder: "type")
		}
		.padding(24)
		.render()

		let html = WebUIDocument(title: "Clean", body: body, checkClasses: true).render()
		#expect(seen.value.isEmpty)
		#expect(html.contains("<button"))
	}

	@Test("the showcase's only undefined classes are its documented page-scoped set")
	func showcaseHasNoStrayClasses() {
		// everything the showcase emits is either in the sheet, in the
		// inline-styled chart family (chart__* prefix), or this one page-scoped
		// structural wrapper. anything else is a typo that renders silently
		// unstyled — so the pin fails.
		let allowlist: Set<String> = ["demo-section"]
		let html = ShowcasePage(state: ShowcaseState()).render()
		let undefined = HTMLClassValidator.undefinedClasses(in: html, extra: allowlist)
		#expect(undefined.isEmpty, "undefined classes were: \(undefined)")
	}

	@Test("WebUIDocument.checkClasses flags an injected bogus class")
	func documentFlagsBogus() {
		let seen = LockedBox([String]())
		HTMLClassValidator.onUndefined = { seen.append($0) }
		defer { HTMLClassValidator.onUndefined = nil }

		let html = #"<div class="totally-bogus-42">x</div>"#
		let doc = WebUIDocument(title: "Bogus", body: html, checkClasses: true).render()
		#expect(seen.value == ["totally-bogus-42"])
		#expect(doc.contains("totally-bogus-42"))
	}

	// MARK: - orphan ratchet (the sheet's inverse check)

	/// class tokens only the client engine writes — `webui-engine.js` builds its
	/// own status element via `className = ...`, so these can never appear in a
	/// Swift render. every shipped js mutation was enumerated when this list was
	/// written; if the engine grows another className write, extend this set in
	/// the same commit or the ratchet will (correctly) flag the new token.
	private static let jsOnlyClasses: Set<String> = [
		"engine-status",
		"engine-status--visible",
		"engine-status__dot",
		"engine-status__text",
	]

	private static let baselinePath = "Tests/WebUITests/orphan-class-baseline.txt"

	/// the growth direction's census: what the sheet defines and *nothing* can
	/// reach. a class that a component *can* emit but the showcase never demos
	/// also reads as an orphan — add the demo, or accept it into the baseline and
	/// keep the count honest.
	///
	/// reachability has two signals, unioned on purpose:
	///   1. the class name appears anywhere in the swift sources — a
	///      deliberately lenient floor, and a *floor only*: a token collision (the
	///      english word `comment`, an unrelated message string) can only *under*-
	///      report an orphan, it can never invent one;
	///   2. the class is actually emitted by a rendered page (catches names
	///      composed at render time, which a source scan cannot see).
	///
	/// signal 1 must not be used in the other direction — see `measuredUnemitted()`.
	private func measuredOrphans() throws -> Set<String> {
		let html = ShowcasePage(state: ShowcaseState()).render()
		let extra = try swiftTokens().union(Self.jsOnlyClasses)
		return Set(HTMLClassValidator.orphanClasses(in: [html], extra: extra))
	}

	/// the tightness direction's census: what the sheet defines and no rendered
	/// page emits. the mention signal is *excluded* here, and the asymmetry is the
	/// point.
	///
	/// measured, not argued: the word "comment" reaching any swift source — a
	/// prose note, or a message string such as "would ship N comment(s) to
	/// clients" — made the tightness ratchet declare the sheet's genuinely
	/// orphaned `.comment` class reachable and demand its removal from the
	/// baseline. deleting it would have rotted the ratchet *on the strength of a
	/// mention*, which is the exact rot this pair of tests exists to prevent. a
	/// mention is not an emitter, so tightness measures emissions: rendered pages,
	/// plus the js-only names the engine writes.
	private func measuredUnemitted() throws -> Set<String> {
		let html = ShowcasePage(state: ShowcaseState()).render()
		return Set(HTMLClassValidator.orphanClasses(in: [html], extra: Self.jsOnlyClasses))
	}

	/// every word token across `Sources/**/*.swift` — the growth direction's
	/// lenient floor, never an evictor (`measuredUnemitted()` is what tightness
	/// measures against; see its note).
	private func swiftTokens() throws -> Set<String> {
		var tokens = Set<String>()
		let root = "Sources"
		guard let walker = FileManager.default.enumerator(atPath: root) else { return tokens }
		for case let path as String in walker where path.hasSuffix(".swift") {
			let text = (try? String(contentsOfFile: "\(root)/\(path)", encoding: .utf8)) ?? ""
			for match in text.matches(of: /[A-Za-z0-9_-]+/) {
				tokens.insert(String(match.output))
			}
		}
		return tokens
	}

	private func baselineClasses() -> Set<String> {
		// the baseline ships as a test resource (declared in Package.swift); the
		// package-root path is a fallback for runners that do not vend Bundle.module.
		var text = ""
		if let url = Bundle.module.url(forResource: "orphan-class-baseline", withExtension: "txt"),
		   let bundled = try? String(contentsOf: url, encoding: .utf8) {
			text = bundled
		} else {
			text = (try? String(contentsOfFile: Self.baselinePath, encoding: .utf8)) ?? ""
		}
		return Set(text.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty && !$0.hasPrefix("#") })
	}

	@Test("orphan classes do not grow: every class the sheet defines is reachable")
	func orphanRatchet() throws {
		let grown = try measuredOrphans().subtracting(baselineClasses())
		#expect(grown.isEmpty, """
			orphan classes with no emitter in swift and none on a rendered page — wire a \
			component that emits them, or record them in \(Self.baselinePath) in the same commit:
			ORPHANS-BEGIN
			\(grown.sorted().joined(separator: "\n"))
			ORPHANS-END
			""")
	}

	@Test("the orphan baseline is tight: no entry lingers once a rendered page emits its class")
	func orphanBaselineIsTight() throws {
		let stale = baselineClasses().subtracting(try measuredUnemitted())
		#expect(stale.isEmpty, """
			these classes are now emitted by a rendered page — delete them from \(Self.baselinePath) \
			so the ratchet cannot silently rot (a mention in swift is not an emission, so it never \
			retires a baseline entry):
			\(stale.sorted().joined(separator: "\n"))
			""")
	}
}

/// tiny test-side thread-safe accumulator (validator callbacks fire from
/// whatever thread renders, which in the test suite is the task's thread).
private final class LockedBox<Value: Sendable>: @unchecked Sendable {
	private let lock: Mutex<Value>
	init(_ initial: Value) { lock = Mutex(initial) }
	var value: Value { lock.withLock { $0 } }
	func append(_ item: Value.Element) where Value: RangeReplaceableCollection {
		lock.withLock { $0.append(item) }
	}
}
