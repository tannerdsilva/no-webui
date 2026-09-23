import Testing
import WebUI
import WebUIShowcaseContent

// pins the showcase's live interactive surface. if a wiring migration (like
// the WebUIButton onTap flip, or a component dropping its typed handler)
// leaves a demo presentational again, this fails. the showcase previously had
// no such pin — the smoke page is a different surface with its own count.
@Suite(.serialized)
struct ShowcaseWiringTests {
	@Test func showcaseInteractiveControlsAreWired() {
		let router = EventRouter()
		let html = RenderContext.$current.withValue(RenderContext(router: router)) {
			ShowcasePage(state: ShowcaseState()).render()
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
		let emitted = html.components(separatedBy: "data-component-id=").count - 1
		#expect(emitted == expectedIds.count + 7, "data-component-id count drifted: \(emitted)")
		#expect(router.handlerCount == expectedIds.count + 7,
			"handler count drifted: \(router.handlerCount)")
	}
}
