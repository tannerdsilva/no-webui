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
		let html = ShowcasePage().render()
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
