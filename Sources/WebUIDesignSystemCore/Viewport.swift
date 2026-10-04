import WebUICore

// MARK: - Viewport (DESKTOP_GRADE §t3.3)
//
// the windowing component the feed and grid share. this file owns the
// *consumer surface* of a windowed region: the DOM contract the engine's
// windowing reads (`continuum-notes/d-to-e.md`), the pure windowing math
// whose semantics the engine's JS twin must match, keyed identity over the
// rows (KeyedList semantics), scroll anchoring on patch, and the server
// degrade (the full list, paginated beyond the measured safe page size).
//
// placement of the windower: the engine windows a served region client-side
// (the d0 verdict — engine-local windowing is where a scroll frame inside the
// 20 ms budget lives). the server therefore renders the FULL list (or, past
// the safe page size, a server pager) and marks the contract the engine
// reads; a hot placement renders a window *slice* through the same id/key
// scheme so the two placements patch each other's rows interchangeably.

// MARK: - pure windowing math

/// The pure windowing spec (t3.3): window size from the viewport rect +
/// overscan, keyed identity over the items, scroll anchoring on patch.
///
/// Semantics (pinned by `ViewportTests`, and the contract the engine's JS
/// twin implements — see `continuum-notes/d-to-e.md`):
///
/// - `visibleCount`: how many whole rows a `viewportHeight` shows,
///   `ceil(height / rowHeight)`.
/// - `windowCount`: the render window = `visible × overscan` (overscan
///   default **2** — the window is twice the visible band: roughly one band
///   above the anchor + one below), clamped to the item count.
/// - `range`: the inclusive row-index band centered on an anchor row,
///   `[first, first + windowCount)` clamped to `[0, total)`.
public enum ViewportSizing {
	/// the default overscan factor: the render window is `visible × 2`.
	public static let defaultOverscan: Int = 2

	/// whole rows that fit a viewport of `viewportHeight` at `rowHeight`.
	/// non-positive inputs degrade to 0 (nothing visible → no window).
	public static func visibleCount(viewportHeight: Double, rowHeight: Double) -> Int {
		guard viewportHeight > 0, rowHeight > 0 else { return 0 }
		return Int((viewportHeight / rowHeight).rounded(.up))
	}

	/// the render-window row budget: `visible × overscan`, at most `total`.
	public static func windowCount(visible: Int, overscan: Int = ViewportSizing.defaultOverscan, total: Int) -> Int {
		guard visible > 0, overscan > 0, total > 0 else { return 0 }
		return Swift.min(visible * overscan, total)
	}

	/// the half-window depth above and below the anchor row. the split is
	/// even; an odd budget keeps the extra row below the anchor (the scroll
	/// direction a feed reads in).
	public static func leadingDepth(window: Int, visible: Int) -> Int {
		guard window > 0, visible > 0 else { return 0 }
		return Swift.max(window - visible, 0) / 2
	}

	/// the inclusive row-index band a windowed render covers, centered on
	/// `anchor`, clamped to the item count. `total == 0` yields an empty band.
	public static func range(anchor: Int, visible: Int, overscan: Int = ViewportSizing.defaultOverscan, total: Int) -> Range<Int> {
		guard total > 0 else { return 0..<0 }
		let window = windowCount(visible: visible, overscan: overscan, total: total)
		guard window > 0 else { return 0..<0 }
		let center = Swift.min(Swift.max(anchor, 0), Swift.max(total - 1, 0))
		var first = center - leadingDepth(window: window, visible: visible)
		first = Swift.min(Swift.max(first, 0), Swift.max(total - window, 0))
		return first..<(first + window)
	}
}

/// A concrete window — the value a windowed render (or the engine's JS twin)
/// computes. Equatable so a patch can diff the previous window against the
/// next and see exactly which rows enter and leave.
public struct ViewportWindow: Equatable, Sendable {
	/// the first rendered row index (inclusive).
	public let first: Int
	/// one past the last rendered row index.
	public let lastExclusive: Int

	public init(first: Int, lastExclusive: Int) {
		self.first = first
		self.lastExclusive = lastExclusive
	}

	public var count: Int { Swift.max(lastExclusive - first, 0) }

	/// the rows this window has that `previous` does not — the `insert` set a
	/// windowing patch must add. `i` is the row index in the full list.
	public func entering(previous: ViewportWindow?) -> [Int] {
		guard let previous else { return Array(first..<lastExclusive) }
		return (first..<lastExclusive).filter { !($0 >= previous.first && $0 < previous.lastExclusive) }
	}

	/// the rows `previous` has that this window does not — the `remove` set.
	public func leaving(previous: ViewportWindow?) -> [Int] {
		guard let previous else { return [] }
		return (previous.first..<previous.lastExclusive).filter { !($0 >= first && $0 < lastExclusive) }
	}

	/// the row that visually anchors the window's top edge after the patch:
	/// the first row still present that sits at or above the previous first
	/// row. this is what "scroll anchoring on patch" preserves.
	public func anchorRow(previous: ViewportWindow?) -> Int? {
		guard let previous else { return first }
		let survivors = (first..<lastExclusive).filter { $0 >= previous.first && $0 < previous.lastExclusive }
		return survivors.first ?? (first < previous.first ? first : nil)
	}
}

/// Scroll anchoring on patch — the generalization of the engine's landed
/// scroll survival. when a windowing patch removes rows *above* the visible
/// band (or inserts them), the DOM scroll position must be corrected by the
/// displaced height so the anchor row stays visually put.
public enum ViewportAnchor {
	/// the scrollTop correction for a window shift: `(oldFirst − newFirst) ×
	/// rowHeight`. positive = rows left from the top → scroll up; negative =
	/// rows appeared above → scroll down. the engine's JS twin applies this
	/// to its scroll container after applying a window patch.
	public static func scrollDelta(oldFirst: Int, newFirst: Int, rowHeight: Double) -> Double {
		Double(oldFirst - newFirst) * rowHeight
	}

	/// which row's top edge is at `scrollTop`. the engine re-windows around
	/// this row when it drifts out of the visible band.
	public static func anchorRow(scrollTop: Double, rowHeight: Double) -> Int {
		guard rowHeight > 0 else { return 0 }
		return Int((scrollTop / rowHeight).rounded(.down))
	}
}

/// the Viewport's configurable defaults, in a namespace (generic types cannot
/// own static stored properties).
public enum ViewportDefaults {
	/// the safe server-render page size: rows rendered in one degrade page
	/// before the server paginates. derived from the d0 measurement — 10k
	/// full-DOM rows render acceptably (p95 scroll 62 ms ≈ 4 fps) and are the
	/// measured ceiling the plan's windowing case starts from; pagination
	/// keeps an engine-less page under it.
	public static let pageSizeLimit = 10_000

	/// the designed virtual-list row height the CSS `.list--virtual` pins
	/// (3.25rem at a 16 px root) — the windower's rowsize default, and the
	/// single source of truth the engine reads from `data-viewport-rowsize`.
	public static let designedRowHeightPx = 52
}

// MARK: - the Viewport component

/// The windowing region (t3.3) — the consumer surface a feed or grid renders
/// once and the engine windows thereafter.
///
/// DOM contract (the engine's handoff — `continuum-notes/d-to-e.md`):
///
/// | element | contract |
/// |---|---|
/// | container | `<ul id="<id>" class="list list--virtual" … data-webui-viewport data-viewport-total data-viewport-rowsize data-viewport-overscan>` — the discovery anchor the engine finds the region by |
/// | rows | `<li id="<id>-r<i>" class="list__item" data-viewport-row data-key="<key>">` — `i` is the row's GLOBAL index (stable across window shifts), `data-key` its keyed identity (`<key>` is the author key rendered through `keyString`) |
/// | slice | when the server renders a window (`window:` set), a leading + trailing `<li class="list__item viewport-pad">` carries the unrendered height and the container adds `data-viewport-slice="<first>..<last>"` |
/// | pager | server degrade beyond the safe page size: `<nav class="pagination pagination--compact" data-viewport-page data-viewport-pages>` with `[data-viewport-goto]` controls |
///
/// behaviors:
///
/// - **keyed identity**: rows carry their list key in `data-key`; a windowing
///   patch reconciles by key, never by position (KeyedList semantics). keys
///   must be unique within a list — the windower's identity map is keyed by
///   them.
/// - **window size = viewport rect + overscan (2×)**: `ViewportSizing` above
///   is the reference math the engine's JS twin matches.
/// - **scroll anchoring on patch**: `ViewportAnchor.scrollDelta` is the
///   correction the engine applies when the window shifts (rows leaving/
///   entering above the visible band).
/// - **server degrade**: the default render is the FULL list (today's bytes
///   for any count ≤ `pageSizeLimit`). beyond it, the server paginates:
///   `page`/`pageSize` select a page slice and a pager nav is emitted — an
///   engine-less page never unbounded-renders. `data-viewport-safe` names the
///   cut that was made.
public struct Viewport<ID: Hashable & Sendable, Item: Sendable>: View {
	/// the stable container id — also the fragment-patch routing anchor and
	/// the prefix every row id derives from.
	public let id: String
	public let items: [Item]
	public let keyedBy: @Sendable (Item) -> ID
	public let keyString: @Sendable (ID) -> String
	public let rowHeightPx: Int
	/// a windowed render: when set, the server renders only `window` (with
	/// height pads) instead of the full list — the hot/window-fetch path.
	public let window: ViewportWindow?
	/// server-degrade pagination: the requested page (0-based) and the page
	/// size. nil page = full render (paginated automatically past
	/// `pageSizeLimit`).
	public let page: Int?
	public let pageSize: Int
	public let onPageChange: EventHandler?

	/// the per-row body. `index` is the row's GLOBAL index in `items`, so an
	/// author's derived child ids are stable across window shifts.
	public let row: @Sendable (Item, Int) -> [any View]

	public init(
		id: String,
		items: [Item],
		keyedBy: @escaping @Sendable (Item) -> ID,
		rowHeightPx: Int = ViewportDefaults.designedRowHeightPx,
		keyString: @escaping @Sendable (ID) -> String = { String(describing: $0) },
		window: ViewportWindow? = nil,
		page: Int? = nil,
		pageSize: Int = ViewportDefaults.pageSizeLimit,
		onPageChange: EventHandler? = nil,
		@ViewBuilder row: @escaping @Sendable (Item, Int) -> [any View]
	) {
		self.id = id
		self.items = items
		self.keyedBy = keyedBy
		self.keyString = keyString
		self.rowHeightPx = rowHeightPx
		self.window = window
		self.page = page
		self.pageSize = pageSize
		self.onPageChange = onPageChange
		self.row = row
	}

	// MARK: render

	public func render() -> String {
		var html = ""
		let total = items.count
		let paged = viewportPageSizeLimit(total: total)

		// degrade: beyond the safe page size the server paginates (a pager
		// page), unless the author explicitly rendered a window slice (the
		// hot/window-fetch path, which is bounded by construction).
		if let windowSlice = window {
			html += container(open: true, total: total, extra: sliceAttribute(windowSlice))
			renderPad(into: &html, rows: windowSlice.first)
			for index in windowSlice.first..<windowSlice.lastExclusive {
				html += rowMarkup(index)
			}
			renderPad(into: &html, rows: total - windowSlice.lastExclusive)
			html += containerClose()
			return html
		}

		guard let paged else {
			html += container(open: true, total: total, extra: "")
			for index in 0..<total {
				html += rowMarkup(index)
			}
			html += containerClose()
			return html
		}

		let pageCount = paged.pageCount
		let current = Swift.min(Swift.max(page ?? 0, 0), Swift.max(pageCount - 1, 0))
		let first = current * paged.pageSize
		let last = Swift.min(first + paged.pageSize, total)
		html += container(open: true, total: total, extra: safeAttribute(paged.pageSizeLimit))
		for index in first..<last {
			html += rowMarkup(index)
		}
		html += containerClose()
		html += pager(page: current, pageCount: pageCount)
		return html
	}

	// MARK: building blocks

	private func container(open: Bool, total: Int, extra: String) -> String {
		"<ul id=\"\(htmlEscape(id))\" class=\"list list--virtual\""
			+ " data-webui-viewport"
			+ " data-viewport-total=\"\(total)\""
			+ " data-viewport-rowsize=\"\(rowHeightPx)\""
			+ " data-viewport-overscan=\"\(ViewportSizing.defaultOverscan)\""
			+ extra + ">"
	}

	private func containerClose() -> String { "</ul>" }

	private func sliceAttribute(_ windowSlice: ViewportWindow) -> String {
		" data-viewport-slice=\"\(windowSlice.first)..\(windowSlice.lastExclusive - 1)\""
	}

	private func safeAttribute(_ limit: Int) -> String {
		" data-viewport-safe=\"\(limit)\""
	}

	private func rowMarkup(_ index: Int) -> String {
		guard index >= 0, index < items.count else { return "" }
		let item = items[index]
		let key = keyString(keyedBy(item))
		var html = "<li id=\"\(htmlEscape(id))-r\(index)\" class=\"list__item\""
			+ " data-viewport-row data-key=\"\(htmlEscape(key))\">"
		for child in row(item, index) {
			html += child.render()
		}
		html += "</li>"
		return html
	}

	/// the unrendered-height spacer a windowed render emits above/below its
	/// row slice, so the scrollbar still spans the full list while only the
	/// window is in the DOM. `aria-hidden` + `visibility:hidden` keep it out
	/// of the accessibility tree and the paint; `border:none;padding:0` strip
	/// the `.list__item` chrome so the inline height is the exact displaced
	/// height (the engine's scroll-height math is raw pixels).
	private func renderPad(into html: inout String, rows: Int) {
		guard rows > 0 else { return }
		let pixels = rows * rowHeightPx
		html += "<li class=\"list__item viewport-pad\" aria-hidden=\"true\""
			+ " style=\"height:\(pixels)px;border:none;padding:0;visibility:hidden\"></li>"
	}

	// MARK: server-degrade pagination

	/// the degrade page decision: nil = render the full list; non-nil =
	/// paginate (item count exceeded the page size limit). a page size above
	/// the limit is clamped to the limit (a page is a bounded server render).
	private func viewportPageSizeLimit(total: Int) -> (pageSize: Int, pageCount: Int, pageSizeLimit: Int)? {
		let limit = Swift.max(pageSize, 1)
		let safeLimit = Swift.min(limit, ViewportDefaults.pageSizeLimit)
		guard total > safeLimit else { return nil }
		let pageCount = (total + safeLimit - 1) / safeLimit
		return (safeLimit, pageCount, safeLimit)
	}

	private func pager(page: Int, pageCount: Int) -> String {
		let attrs = controlAttributes(id: id + "-pager", event: .click, handler: onPageChange)
		var html = "<nav class=\"pagination pagination--compact\""
			+ " id=\"\(htmlEscape(id))-pager\""
			+ " data-viewport-page=\"\(page)\" data-viewport-pages=\"\(pageCount)\""
			+ attrs + ">"
		html += pagerButton(id: id + "-pager-prev", goto: "prev", label: "Previous",
			disabled: page <= 0, enabled: onPageChange != nil)
		html += "<span class=\"pagination__meta\">Page \(page + 1)\u{2009}/\u{2009}\(pageCount)</span>"
		html += pagerButton(id: id + "-pager-next", goto: "next", label: "Next",
			disabled: page >= pageCount - 1, enabled: onPageChange != nil)
		html += "</nav>"
		return html
	}

	private func pagerButton(id: String, goto: String, label: String, disabled: Bool, enabled: Bool) -> String {
		let attrs = enabled
			? controlAttributes(id: id, event: .click, handler: onPageChange)
			: ""
		let disabledAttr = disabled ? " disabled" : ""
		return "<button class=\"pagination__btn\" type=\"button\""
			+ " id=\"\(htmlEscape(id))\" data-viewport-goto=\"\(goto)\""
			+ attrs + disabledAttr + ">\(htmlEscape(label))</button>"
	}
}
