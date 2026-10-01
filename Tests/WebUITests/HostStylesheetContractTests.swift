import Testing
import WebUI
import WebUIDesignSystem

// MARK: - the host stylesheet contract (NW-1, NW-6)
//
// the failure this file pins, measured on the arc-agent consumer: a page that
// renders framework icons but links only its own chrome sheet. every `svg.icon`
// resolves `width:auto` to its container, so the glyphs rendered at 240-718 px
// where 10.9-19 px was intended (`.lr-name svg` 22x, `.detail-title svg` 38x).
//
// the repair is a *fallback*: `WebUIIcon` now emits the size it already carries
// (`IconSize.em`) as presentation attributes. presentation attributes sit at
// specificity 0 in the author origin, so every existing css rule — the
// `.icon--*` sizing, consumer overrides, `.fill-slot > svg.icon { width:100% }`
// — still wins. an icon can no longer render at container width on a page that
// forgot a stylesheet.

@Suite("host stylesheet contract")
struct HostStylesheetContractTests {

	@Test("an icon carries a fallback size without any stylesheet")
	func iconCarriesFallbackSize() {
		let html = WebUIIcon(.check, size: .large).render()
		#expect(html.contains("width=\"1.25em\""), "no fallback width: \(html)")
		#expect(html.contains("height=\"1.25em\""), "no fallback height: \(html)")
		#expect(html.contains("class=\"icon icon--lg\""), "the class contract must survive")
	}

	@Test("every non-slot size emits its own em dimensions")
	func sizeTable() {
		let expected: [(IconSize, String)] = [
			(.small, "0.75em"), (.medium, "1em"), (.large, "1.25em"), (.extraLarge, "1.5em"),
		]
		for (size, em) in expected {
			let html = WebUIIcon(.check, size: size).render()
			#expect(
				html.contains("width=\"\(em)\" height=\"\(em)\""),
				"\(size) should emit \(em) twice: \(html)"
			)
		}
	}

	@Test("slot icons stay container-sized")
	func slotIconEmitsNoDimension() {
		let html = WebUIIcon(.check, size: .slot).render()
		// ` width="` is space-anchored so the root `stroke-width="2"` never matches
		#expect(!html.contains(" width=\""), "a slot icon must not name its own width")
		#expect(!html.contains(" height=\""), "a slot icon must not name its own height")
	}

	@Test("a custom icon carries the fallback too")
	func customIconCarriesFallback() {
		let html = WebUIIconCustom(name: "ok", body: "<path d=\"M1 1h10\"/>", size: .small).render()
		#expect(html.contains("width=\"0.75em\" height=\"0.75em\""), "no fallback on custom geometry: \(html)")
	}

	@Test("iconSize retargets the fallback dimensions with the class")
	func iconSizeRetargetsDimensions() {
		// the modifier is part of the size contract: a retargeted class with a
		// stale attribute is exactly the mismatch the fallback exists to bound.
		let shrunk = WebUIIcon(.heart).iconSize(.small).render()
		#expect(shrunk.contains("class=\"icon icon--sm\""))
		#expect(shrunk.contains("width=\"0.75em\" height=\"0.75em\""), "stale fallback: \(shrunk)")
		#expect(!shrunk.contains("width=\"1em\""), "the old size lingers: \(shrunk)")

		let slotted = WebUIIcon(.heart, size: .large).iconSize(.slot).render()
		#expect(!slotted.contains(" width=\"") && !slotted.contains(" height=\""), "slot keeps no dimension: \(slotted)")

		let grown = WebUIIcon(.heart, size: .slot).iconSize(.large).render()
		#expect(grown.contains("width=\"1.25em\" height=\"1.25em\""), "no dimension added: \(grown)")
	}

	@Test("the fallback is a presentation attribute, never a style attribute")
	func fallbackIsAPresentationAttribute() {
		// the property the repair relies on: specificity 0 loses to every rule.
		// a `style="width:…"` would win against them and break consumer css.
		let html = WebUIIcon(.check, size: .large).render()
		#expect(html.contains("\"0 0 24 24\" width=\"1.25em\" height=\"1.25em\" fill=\"none\""), "unexpected emission shape: \(html)")
		#expect(!html.contains("style=\""), "a style attribute outranks author css")
	}

	@Test("a core document with no stylesheet still renders bounded icons (the shipped bug)")
	func coreDocumentWithoutSheetKeepsIconsBounded() {
		// the exact configuration that shipped broken: a core `HTMLDocument`
		// whose body carries framework icons and no `stylesheetURL`. this is the
		// test whose absence let 55 oversized glyphs reach a live page.
		let body = WebUIIcon(.search, size: .small).render()
			+ WebUIIcon(.trash, size: .large).render()
			+ VStack(spacing: 8) { Text("hi"); WebUIIcon(.inbox, size: .extraLarge) }.render()
		let doc = HTMLDocument(title: "no sheet", body: body).render()
		let icons = doc.components(separatedBy: "<svg class=\"icon").count - 1
		let bounded = doc.components(separatedBy: "\"0 0 24 24\" width=\"").count - 1
		#expect(icons == 3, "expected 3 icons in the fixture, saw \(icons)")
		#expect(bounded == icons, "\(icons - bounded) icon(s) could size to their container")
	}
}

// MARK: - the engine's own DOM (NW-2, NW-2b, NW-3)
//
// the engine injects a status chip on every boot, and both its visibility and
// its text lived only in the design-system sheet: a page that never links the
// sheet showed a permanently visible "reconnecting…" chip on a healthy socket.
// the engine now owns both — the hidden default rides an inline cssom write (a
// `<style>` injection needs `style-src 'unsafe-inline'`, which a strict host
// policy may not grant; cssom writes are not csp-governed), and
// `updateStatusMirrors` keeps the chip text equal to the real socket state.

@Suite("engine status chip contract")
struct EngineStatusChipContractTests {

	private static let injectedClasses = [
		"engine-status", "engine-status--visible", "engine-status__dot", "engine-status__text",
	]

	@Test("every class the engine injects is defined by the shipped sheet")
	func injectedClassesAreDefined() {
		let defined = HTMLClassValidator.definedClasses()
		for name in Self.injectedClasses {
			#expect(defined.contains(name), "\(name) is emitted by the engine but defined by no stylesheet")
		}
	}

	@Test("the engine owns the chip's visibility, so it stays hidden without any sheet")
	func chipVisibilityIsEngineOwned() {
		let engine = WebUIAssets.engine
		// hidden at creation, before any stylesheet has a say
		#expect(engine.contains("_statusEl.style.display = 'none'"), "the chip is not hidden by the engine itself")
		// shown on disconnect, hidden again on reconnect — by cssom
		#expect(engine.contains("_statusEl.style.display = 'inline-flex'"))
		#expect(!engine.contains("<style>"), "an injected sheet needs style-src unsafe-inline, which a host may not grant")
		#expect(!engine.contains("createElement('style')"), "cssom writes are not csp-governed; an injected sheet is")
		// the class toggles the browser gate drives stay intact
		#expect(engine.contains("_statusEl.className = 'engine-status engine-status--visible'"))
	}

	@Test("the chip text tracks the state, so it can never contradict the socket")
	func chipTextTracksState() {
		let engine = WebUIAssets.engine
		#expect(engine.contains("_statusText"), "the chip text node is not tracked")
		#expect(engine.contains("_statusText.textContent = state === 'connected' ? 'connected' : 'reconnecting\\u2026'"))
	}
}