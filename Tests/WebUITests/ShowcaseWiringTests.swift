import Testing
import WebUI
import WebUIDesignSystem
import WebUIShowcaseContent

// the showcase artifact's byte count, pinned in one place. this is the single
// constant for the whole repo's showcase byte gate — it must never be
// duplicated in another file. `Documentation/STABILITY.md` documents when it
// may move: a legitimate change to the served page's byte count, justified in
// the commit that updates it here. the gate asserts the byte COUNT, never a
// hash of the raw bytes: `JSONValue.serialize()` emits object keys by direct
// dictionary iteration and swift dictionary order is per-process randomized,
// so the raw bytes are not stable run-to-run — only their count is.
private let showcaseBytePin = 168671

// pins the showcase's live interactive surface. if a wiring migration (like
// the WebUIButton onTap flip, or a component dropping its typed handler)
// leaves a demo presentational again, this fails. the showcase previously had
// no such pin — the smoke page is a different surface with its own count.
@Suite(.serialized)
struct ShowcaseWiringTests {
	@Test func showcaseInteractiveControlsAreWired() {
		let router = EventRouter()
		let html = RenderContext.$current.withValue(RenderContext(router: router)) {
			ShowcasePage(state: ShowcaseState()).renderedString()
		}

		// stable control ids: typed self-wired controls (WebUIButton onTap,
		// WebUITabs onSelect, table/pagination typed handlers, tree, modal)
		// emit their caller-chosen id in data-component-id.
		let expectedIds: [String] = [
			"btn-decrement", "btn-increment",
			"content-tabs-tab-info", "content-tabs-tab-stats", "content-tabs-tab-log",
			"demo-interactive-sort-0", "demo-interactive-sort-1", "demo-interactive-sort-2",
			"demo-interactive-select-all",
			"demo-interactive-select-web", "demo-interactive-select-api", "demo-interactive-select-search",
			"demo-interactive-expand-web", "demo-interactive-expand-api", "demo-interactive-expand-search",
			"demo-pagination-prev", "demo-pagination-next",
			"demo-pagination-page-1", "demo-pagination-page-2", "demo-pagination-page-4",
			"demo-pagination-page-5", "demo-pagination-page-6", "demo-pagination-page-11",
			"demo-pagination-page-12", "demo-pagination-rows",
			"demo-tree", "modal-close",
			"column-menu",
		]
		for id in expectedIds {
			#expect(html.contains("data-component-id=\"\(id)\""), "missing wiring for \(id)")
		}

		// modifier-wired demos mint their component ids at render (cN) — pin
		// the DOM anchor + the emitted event declaration instead.
		#expect(html.contains("id=\"btn-reset\""))
		#expect(html.contains("id=\"echo-form\""))
		#expect(html.contains("data-event=\"submit\""))
		#expect(html.contains("id=\"preview-input\""))
		#expect(html.contains("data-event=\"input\""))

		// exact pins: every wired control emits one data-component-id and
		// registers one handler at page build. dump the counts on drift.
		//
		// render-time controls are the ones minted as `cN` rather than carrying a
		// caller id: btn-reset, echo-form, preview-input, toast-dismiss,
		// modal-dismiss, banner-dismiss (p1 sweep), chat-form and the
		// attachment remove (p2), the card/item/scroll-top demo buttons (p3),
		// theme toggle, engine status.
		let renderTimeControls = 10
		let emitted = html.components(separatedBy: "data-component-id=").count - 1
		#expect(emitted == expectedIds.count + renderTimeControls,
			"data-component-id count drifted: \(emitted)")
		#expect(router.handlerCount == expectedIds.count + renderTimeControls,
			"handler count drifted: \(router.handlerCount)")
	}

	// the showcase byte pin: the exact artifact `swift run WebUIShowcase
	// --generate` produces, rendered in-process through the same path
	// (`RenderContext.$current` snapshot + `WebUIDocument(title:body:
	// includeRuntime:false)`), asserted to be `showcaseBytePin` bytes.
	// drift here is a regression or a deliberate change — the latter is a
	// justified update to the single constant above, not a silent pass.
	@Test func showcaseArtifactByteCountIsPinned() {
		let snapshot = RenderContext.$current.withValue(RenderContext(router: EventRouter())) {
			ShowcasePage(state: ShowcaseState()).renderedString()
		}
		let doc = WebUIDocument(title: "WebUI Showcase", body: snapshot, includeRuntime: false)
		let html = doc.renderThroughBuffer()
		#expect(html.utf8.count == showcaseBytePin,
			"showcase artifact drifted: \(html.utf8.count) bytes, pinned \(showcaseBytePin). a legitimate move is one justified commit updating this single constant.")
	}
}
