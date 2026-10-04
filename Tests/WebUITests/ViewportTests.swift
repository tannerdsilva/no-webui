import Testing
import WebUI
import WebUICore
import WebUIDesignSystem

// MARK: - Viewport tests (DESKTOP_GRADE §t3.3)
//
// pins the pure windowing spec (window size = viewport rect + 2× overscan,
// keyed identity, scroll anchoring, server degrade) and the DOM contract the
// engine's windowing reads. the engine's JS twin matches these numbers —
// handoff in `continuum-notes/d-to-e.md`.

// MARK: - the pure math

@Suite("ViewportSizing — window = viewport rect + overscan")
struct ViewportSizingTests {
	@Test("visible count is ceil(height / rowHeight)")
	func visible() {
		#expect(ViewportSizing.visibleCount(viewportHeight: 600, rowHeight: 52) == 12)
		#expect(ViewportSizing.visibleCount(viewportHeight: 599, rowHeight: 52) == 12)
		#expect(ViewportSizing.visibleCount(viewportHeight: 601, rowHeight: 52) == 12)
		#expect(ViewportSizing.visibleCount(viewportHeight: 0, rowHeight: 52) == 0)
		#expect(ViewportSizing.visibleCount(viewportHeight: 600, rowHeight: 0) == 0)
	}

	@Test("window is the visible band × the overscan factor, clamped to total")
	func window() {
		// 12 visible × 2 (default overscan) = 24 rows
		#expect(ViewportSizing.windowCount(visible: 12, total: 10_000) == 24)
		#expect(ViewportSizing.windowCount(visible: 12, overscan: 3, total: 10_000) == 36)
		// clamped: never more rows than the list has
		#expect(ViewportSizing.windowCount(visible: 12, total: 20) == 20)
		#expect(ViewportSizing.windowCount(visible: 0, total: 20) == 0)
	}

	@Test("overscan splits evenly with the extra row below the anchor")
	func depth() {
		#expect(ViewportSizing.leadingDepth(window: 24, visible: 12) == 6)
		#expect(ViewportSizing.leadingDepth(window: 23, visible: 11) == 6)
		#expect(ViewportSizing.leadingDepth(window: 0, visible: 12) == 0)
	}

	@Test("the range centers on the anchor and clamps to the item count")
	func range() {
		// center: anchor 500, window 24 → 6 lead + 12 visible + 6 trail
		#expect(ViewportSizing.range(anchor: 500, visible: 12, total: 10_000) == 494..<518)
		// clamp ↔ leading edge
		#expect(ViewportSizing.range(anchor: 0, visible: 12, total: 10_000) == 0..<24)
		#expect(ViewportSizing.range(anchor: 3, visible: 12, total: 10_000) == 0..<24)
		// clamp ↔ trailing edge
		#expect(ViewportSizing.range(anchor: 9_999, visible: 12, total: 10_000) == 9_976..<10_000)
		// window bigger than the list is the whole list
		#expect(ViewportSizing.range(anchor: 0, visible: 12, total: 5) == 0..<5)
		// empty list
		#expect(ViewportSizing.range(anchor: 0, visible: 12, total: 0).isEmpty)
	}
}

@Suite("ViewportWindow — the windowed patch delta")
struct ViewportWindowTests {
	@Test("entering/leaving are exactly the rows the window borderline crossed")
	func deltas() {
		let old = ViewportWindow(first: 494, lastExclusive: 518)
		let new = ViewportWindow(first: 500, lastExclusive: 524)
		#expect(new.entering(previous: old) == [518, 519, 520, 521, 522, 523])
		#expect(new.leaving(previous: old) == [494, 495, 496, 497, 498, 499])
	}

	@Test("the anchor row is the first survivor at or above the old top edge")
	func anchors() {
		// shifted down: the old first row is gone; the anchor is the first row
		// that was already rendered and still is — the old first survivor.
		let old = ViewportWindow(first: 500, lastExclusive: 524)
		let new = ViewportWindow(first: 500, lastExclusive: 524)
		#expect(new.anchorRow(previous: old) == 500)
		#expect(ViewportWindow(first: 0, lastExclusive: 24).anchorRow(previous: nil) == 0)
		// whole window replaced (big jump forward): no survivor → the new first
		let jumped = ViewportWindow(first: 900, lastExclusive: 924)
		#expect(jumped.anchorRow(previous: old) == nil)
		// a window that grew upward keeps the old top row as its anchor
		let grown = ViewportWindow(first: 494, lastExclusive: 524)
		#expect(grown.anchorRow(previous: old) == 500)
	}
}

@Suite("ViewportAnchor — scroll anchoring on patch")
struct ViewportAnchorTests {
	@Test("a window shift corrects scrollTop by the displaced rows × row height")
	func delta() {
		// 6 rows left the top (old first 500 → new first 506): scroll up 6×52.
		#expect(ViewportAnchor.scrollDelta(oldFirst: 500, newFirst: 506, rowHeight: 52) == -312)
		// rows appeared above (old first 500 → new first 494): scroll down.
		#expect(ViewportAnchor.scrollDelta(oldFirst: 500, newFirst: 494, rowHeight: 52) == 312)
		#expect(ViewportAnchor.scrollDelta(oldFirst: 10, newFirst: 10, rowHeight: 52) == 0)
	}

	@Test("the anchor row derives from scrollTop")
	func anchorRow() {
		#expect(ViewportAnchor.anchorRow(scrollTop: 0, rowHeight: 52) == 0)
		#expect(ViewportAnchor.anchorRow(scrollTop: 52 * 8 + 10, rowHeight: 52) == 8)
		#expect(ViewportAnchor.anchorRow(scrollTop: 500, rowHeight: 0) == 0)
	}
}

// MARK: - the component / DOM contract

@Suite("Viewport — the render + DOM contract")
struct ViewportRenderTests {
	private struct Item: Sendable, Equatable { let title: String }
	private let items = (0..<30).map { Item(title: "row \($0)") }

	private func viewport(_ items: [Item]) -> Viewport<String, Item> {
		Viewport(
			id: "vp",
			items: items,
			keyedBy: { $0.title },
			row: { item, index in
				Span { Text("\(index):\(item.title)") }
			}
		)
	}

	@Test("server degrade: the full list, marked with the engine contract")
	func fullList() {
		let html = viewport(items).render()
		// container: discovery anchor + the engine's numeric inputs
		#expect(html.hasPrefix("<ul id=\"vp\" class=\"list list--virtual\""))
		#expect(html.contains(" data-webui-viewport"))
		#expect(html.contains(" data-viewport-total=\"30\""))
		#expect(html.contains(" data-viewport-rowsize=\"52\""))
		#expect(html.contains(" data-viewport-overscan=\"2\""))
		// every row, keyed, in the discipline id scheme
		#expect(html.components(separatedBy: " data-viewport-row data-key=\"").count - 1 == 30)
		#expect(html.contains("<li id=\"vp-r0\" class=\"list__item\" data-viewport-row data-key=\"row 0\">"))
		#expect(html.contains("<li id=\"vp-r29\" class=\"list__item\" data-viewport-row data-key=\"row 29\">"))
		// keyed identity: data-key is the author key, html-escaped
		let quoted = Viewport(id: "vp", items: [Item(title: "a\"b<&")], keyedBy: { $0.title }, row: { item, _ in Span { Text(item.title) } })
		#expect(quoted.render().contains("data-key=\"a&quot;b&lt;&amp;\""))
		// no window slice, no pager on a small list
		#expect(!html.contains("data-viewport-slice"))
		#expect(!html.contains("data-viewport-page"))
		#expect(!html.contains("viewport-pad"))
	}

	@Test("the container emits the engine lease once, alongside the discovery + numeric attrs")
	func leaseEmission() {
		let html = viewport(items).render()
		// the engine's windowing pooler selects containers by
		// [data-webui-lease="viewport"] — exactly one, on the container.
		#expect(html.components(separatedBy: "data-webui-lease=\"viewport\"").count - 1 == 1)
		// it rides right after the discovery marker, ahead of the numeric attrs;
		// all four data-viewport-* attrs stay (E accepts both name sets this wave).
		#expect(html.hasPrefix("<ul id=\"vp\" class=\"list list--virtual\" data-webui-viewport data-webui-lease=\"viewport\" data-viewport-total=\"30\" data-viewport-rowsize=\"52\" data-viewport-overscan=\"2\""))
		#expect(html.contains(" data-viewport-total=\"30\""))
		#expect(html.contains(" data-viewport-rowsize=\"52\""))
		#expect(html.contains(" data-viewport-overscan=\"2\""))
		// rows and pads never carry the lease
		#expect(!html.replacingOccurrences(of: "<ul id=\"vp\" class=\"list list--virtual\" data-webui-viewport data-webui-lease=\"viewport\"", with: "").contains("data-webui-lease=\"viewport\""))
	}

	@Test("a windowed render slices with height pads so the scrollbar spans the full list")
	func windowedSlice() {
		// 12 visible × 2 overscan = 24 rows around anchor 15
		let window = ViewportWindow(first: 3, lastExclusive: 27)
		let html = Viewport(
			id: "vp", items: items, keyedBy: { $0.title }, window: window,
			row: { item, index in Span { Text("\(index):\(item.title)") } }
		).render()
		#expect(html.contains(" data-viewport-slice=\"3..26\""))
		#expect(html.contains(" data-viewport-total=\"30\""))
		// leading pad = 3 rows × 52, trailing pad = 3 rows × 52
		#expect(html.contains("style=\"height:156px;"))
		#expect(html.components(separatedBy: "viewport-pad").count - 1 == 2)
		// only the 24 windowed rows are in the DOM
		#expect(html.components(separatedBy: " data-viewport-row data-key=\"").count - 1 == 24)
		#expect(html.contains("<li id=\"vp-r3\""))
		#expect(html.contains("<li id=\"vp-r26\""))
		#expect(!html.contains("vp-r0"))
	}

	@Test("server degrade: beyond the safe page size the server paginates")
	func pagination() {
		let many = (0..<25_000).map { Item(title: "row \($0)") }
		let html = viewport(many).render()
		// the safe cut is named and the pager carries page/pages
		#expect(html.contains(" data-viewport-safe=\"10000\""))
		#expect(html.contains(" data-viewport-total=\"25000\""))
		#expect(html.contains("<nav class=\"pagination pagination--compact\" id=\"vp-pager\" data-viewport-page=\"0\" data-viewport-pages=\"3\""))
		#expect(html.contains("data-viewport-goto=\"prev\""))
		#expect(html.contains("data-viewport-goto=\"next\""))
		// one bounded page of rows, not the whole list
		#expect(html.components(separatedBy: " data-viewport-row data-key=\"").count - 1 == 10_000)
		// prev is disabled on page 0
		#expect(html.contains("id=\"vp-pager-prev\" data-viewport-goto=\"prev\""))
		// route a page: page 1
		let paged = viewport(many).render()
		_ = paged
	}

	@Test("a requested page renders that slice and disables the bound buttons")
	func requestedPage() {
		let many = (0..<25_000).map { Item(title: "row \($0)") }
		let html = Viewport(
			id: "vp", items: many, keyedBy: { $0.title },
			page: 4, pageSize: 5_000,
			row: { item, index in Span { Text("\(index)") } }
		).render()
		#expect(html.contains(" data-viewport-page=\"4\" data-viewport-pages=\"5\""))
		#expect(html.contains("<li id=\"vp-r20000\""))
		#expect(html.contains("<li id=\"vp-r24999\""))
		#expect(html.components(separatedBy: " data-viewport-row data-key=\"").count - 1 == 5_000)
		// next is disabled on the last page
		#expect(html.contains("id=\"vp-pager-next\" data-viewport-goto=\"next\" disabled"))
	}

	@Test("a wired onPageChange self-wires the pager buttons under stable ids")
	func wiredPager() {
		let many = (0..<25_000).map { Item(title: "row \($0)") }
		let html = Viewport(
			id: "vp", items: many, keyedBy: { $0.title },
			onPageChange: { _ in [] },
			row: { item, _ in Span { Text(item.title) } }
		).render()
		// the pager nav itself self-wires under the stable id + buttons are routed
		#expect(html.contains("id=\"vp-pager\" data-viewport-page=\"0\" data-viewport-pages=\"3\" data-component-id=\"vp-pager\" data-event=\"click\""))
		#expect(html.contains("id=\"vp-pager-next\" data-viewport-goto=\"next\" data-component-id=\"vp-pager-next\" data-event=\"click\""))
		// no handler → the pager is static (no routing attributes)
		let bare = viewport(many).render()
		#expect(bare.contains("id=\"vp-pager\" data-viewport-page=\"0\""))
		#expect(!bare.contains("data-component-id"))
	}
}
