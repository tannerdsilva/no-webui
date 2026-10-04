import Testing
@testable import WebUI
@testable import WebUIDesignSystem
@testable import WebUIChart

// MARK: - DX-11a — the table/pagination id-key contract (byte-diff gate)
//
// the typed per-control id vocabulary that lets WebUITable / WebUIPagination
// (and chart marks) expose stable ids for op-emitting handlers (DX-11b, W3).
// this gate byte-diffs the rendered markup for the contract's canonical
// instances:
//
//   | control | id | notes |
//   |---|---|---|
//   | table root | `{id}` | existing |
//   | sort control | `{id}-sort-{col}` | existing (the clickable span) |
//   | sortable `<th>` | `{id}-th-{col}` | NEW — the `aria-sort` state carrier |
//   | row slot | `{id}-r{i}` | NEW — positional slot, stable across shifts |
//   | row key | `data-key="{rowId}"` | NEW — keyed identity channel |
//   | select/expand | `{id}-select-{rowId}` / `{id}-expand-{rowId}` | existing |
//   | pagination | `{id}-prev` / `{id}-page-{n}` / `{id}-next` / `{id}-rows` | existing |
//   | chart mark | `{chartID}-mark-{category}-{series}` | existing |
//
// the new identity attributes land on **addressed** tables only (a typed
// handler requires a caller `id:`), so un-addressed tables stay
// byte-identical — pinned both ways below. content-pin note: the smoke page's
// addressed table changes bytes (the sanctioned DX-11a migration).

@Suite("DX-11a table/pagination id-key contract (byte-diff)")
struct TableIDContractTests {

	@Test("an addressed table emits the row slot ids + data-key, byte-exact")
	func addressedRows() {
		let html = WebUITable(
			headers: ["Name", "Age"],
			rows: [[Text("A"), Text("1")], [Text("B"), Text("2")]],
			id: "grid"
		).render()
		// positional slot id + keyed identity; `row-{i}` is the identity a
		// row without a caller-supplied rowId carries (the same value the
		// select/expand controls use).
		#expect(html.contains("<tr id=\"grid-r0\" data-key=\"row-0\">"), "emitted: \(html)")
		#expect(html.contains("<tr id=\"grid-r1\" data-key=\"row-1\">"), "emitted: \(html)")
		// exactly two rows carry the key channel
		#expect(html.components(separatedBy: "data-key=").count - 1 == 2)
	}

	@Test("rowIds feed data-key; a selected row keeps class order id→class→data-key")
	func rowsFromRowIds() {
		let html = WebUITable(
			headers: ["Name"],
			rows: [[Text("A")], [Text("B")]],
			id: "staff",
			selectable: true,
			rowIds: ["a", "b"],
			selectedRows: ["b"]
		).render()
		#expect(html.contains("<tr id=\"staff-r0\" data-key=\"a\">"), "emitted: \(html)")
		#expect(html.contains("<tr id=\"staff-r1\" class=\"tr--selected\" data-key=\"b\">"), "emitted: \(html)")
	}

	@Test("row keys are escaped in data-key (attribute boundary)")
	func dataKeyEscaping() {
		let html = WebUITable(
			headers: ["Name"],
			rows: [[Text("A")]],
			id: "esc",
			selectable: true,
			rowIds: ["a\"<&"]
		).render()
		#expect(html.contains("id=\"esc-r0\" class=\"") == false) // no spurious class
		#expect(html.contains("data-key=\"a&quot;&lt;&amp;\""), "emitted: \(html)")
	}

	@Test("a sortable th carries its own id; the active th keeps aria-sort, byte-exact")
	func sortableHeaderIDs() {
		let html = WebUITable(
			headers: ["Name", "Age"],
			rows: [[Text("A"), Text("1")]],
			id: "grid",
			sortableColumns: [0, 1],
			sort: (column: 0, direction: .ascending)
		).render()
		#expect(html.contains("<th id=\"grid-th-0\" class=\"sort-cell\" aria-sort=\"ascending\">"), "emitted: \(html)")
		#expect(html.contains("<th id=\"grid-th-1\" class=\"sort-cell\">"), "emitted: \(html)")
		// non-sortable columns carry no th id
		#expect(html.components(separatedBy: "-th-").count - 1 == 2)
	}

	@Test("an un-addressed table stays byte-identical (no new identity attributes)")
	func unaddressedUnchanged() {
		let html = WebUITable(
			headers: ["Name"],
			rows: [[Text("A")]],
			sortableColumns: [0]
		).render()
		// rows keep the bare tag; the sort span keeps its existing fallback
		// id; no data-key channel and no th id appear.
		#expect(html.contains("<tr>"), "emitted: \(html)")
		#expect(!html.contains("data-key"))
		#expect(html.contains("<th class=\"sort-cell\">"), "emitted: \(html)")
		#expect(html.contains("<span class=\"sort\" id=\"webui-table-sort-0\">"))
		#expect(!html.contains("\"webui-table-th-0\""))
	}

	@Test("pagination id vocabulary — full-string byte pin")
	func paginationBytes() {
		let html = WebUIPagination(page: 2, pages: 3, id: "pg").render()
		let expected = "<nav class=\"pagination\" aria-label=\"Pagination\">"
			+ "<button class=\"pagination__btn\" id=\"pg-prev\" type=\"button\" aria-label=\"Previous page\">&#8249;</button>"
			+ "<button class=\"pagination__btn\" id=\"pg-page-1\" type=\"button\">1</button>"
			+ "<button class=\"pagination__btn pagination__btn--active\" id=\"pg-page-2\" type=\"button\" aria-current=\"page\">2</button>"
			+ "<button class=\"pagination__btn\" id=\"pg-page-3\" type=\"button\">3</button>"
			+ "<button class=\"pagination__btn\" id=\"pg-next\" type=\"button\" aria-label=\"Next page\">&#8250;</button>"
			+ "</nav>"
		#expect(html == expected, "emitted: \(html)")
	}

	@Test("pagination rows-per-page select keeps its stable id — byte-exact")
	func paginationRowsSelect() {
		let html = WebUIPagination(page: 1, pages: 4, id: "pg", rowsPerPage: 25).render()
		#expect(html.contains("<span class=\"pagination__meta\"><label>Rows per page</label><select class=\"select\" id=\"pg-rows\">"))
		#expect(html.contains("<option value=\"10\">10</option><option value=\"25\" selected>25</option><option value=\"50\">50</option><option value=\"100\">100</option></select></span>"))
		#expect(html.contains("<button class=\"pagination__btn\" id=\"pg-prev\" type=\"button\" aria-label=\"Previous page\" disabled>&#8249;</button>"))
	}

	@Test("chart marks keep the {chartID}-mark-{category}-{series} identity")
	func chartMarkIDs() {
		let bars = [
			BarMark(x: .value("Month", "Jan"), y: .value("Sales", 12)).foregroundStyle(by: "A").makeMark(),
			BarMark(x: .value("Month", "Feb"), y: .value("Sales", 20)).foregroundStyle(by: "A").makeMark(),
		]
		let html = Chart(bars).chartID("chart-1").render()
		#expect(html.contains("id=\"chart-1-mark-Jan-A\""), "emitted: \(html)")
		#expect(html.contains("id=\"chart-1-mark-Feb-A\""), "emitted: \(html)")
	}
}