import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIChart

// MARK: - DX-11b — op-emitting handlers (CONTINUUM_DX §2.11, lane D)
//
// pins the op-emitting helpers' contract: every op targets a DX-11a id that
// the matching component actually renders (vocabulary cross-check), every op
// value is the exact string the component renders for that state, every op is
// a REAL op (never a whole-region replace), and each composed helper equals a
// hand-written literal op dictionary (anti-shackle: the host could write these
// by hand and get the identical bytes).

private func wiredTableHTML() -> String {
	let router = EventRouter()
	return RenderContext.$current.withValue(RenderContext(router: router)) {
		WebUITable(
			headers: ["Name", "Age"],
			rows: [[Text("Alice"), Text("30")], [Text("Bob"), Text("25")]],
			id: "tbl",
			sortableColumns: [0, 1],
			selectable: true,
			rowIds: ["alice", "bob"],
			rowDetails: ["alice": Text("detail")]
		)
		.onSort { _, _ in [] }
		.onSelectAll { _ in [] }
		.onSelect { _, _ in [] }
		.onToggleExpand { _, _ in [] }
		.render()
	}
}

@Suite("DX-11b ops — id vocabulary cross-checks against the components' markup")
struct ComponentOpsVocabularyTests {

	@Test("table id derivations are the ids the wired table renders")
	func tableVocabulary() {
		let html = wiredTableHTML()
		#expect(html.contains("id=\"\(ComponentOps.tableRowID("tbl", 0))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableRowID("tbl", 1))\""))
		#expect(!html.contains("id=\"\(ComponentOps.tableRowID("tbl", 2))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableSortControlID("tbl", 0))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableSortControlID("tbl", 1))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableSelectControlID("tbl", "alice"))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableSelectControlID("tbl", "bob"))\""))
		#expect(html.contains("id=\"\(ComponentOps.tableExpandControlID("tbl", "alice"))\""))
		// the select control id derives from rowIds — the same data-key the row carries.
		#expect(html.contains("data-key=\"alice\""))
	}

	@Test("pagination id derivations are the ids the pager renders")
	func paginationVocabulary() {
		let html = WebUIPagination(page: 2, pages: 5, id: "pg", rowsPerPage: 25).render()
		for n in [1, 2, 3, 4, 5] {
			#expect(html.contains("id=\"\(ComponentOps.paginationPageID("pg", n))\""))
		}
	}

	@Test("chart mark id derivations are the ids a marked chart renders")
	func chartVocabulary() {
		let html = Chart(
			[SectorMark(angle: .value("share", 30), innerRadiusRatio: 0.0).makeMark(),
			 SectorMark(angle: .value("share", 70), innerRadiusRatio: 0.0).makeMark()],
			id: "pie"
		).render()
		#expect(html.contains("id=\"\(ComponentOps.chartMarkID("pie", 0))\""))
		#expect(html.contains("id=\"\(ComponentOps.chartMarkID("pie", 1))\""))
		#expect(!html.contains("id=\"\(ComponentOps.chartMarkID("pie", 2))\""))
	}
}

@Suite("DX-11b ops — composed helpers emit attr/text ops, never whole-region replaces")
struct ComponentOpsEmissionTests {

	/// the op contract: a real op (attr/text/move/…), never the default
	/// whole-region replace, no html payload.
	private func assertOpsOnly(_ updates: [FragmentUpdate], _ context: String) {
		for update in updates {
			#expect(update.op != nil && update.op != .replace, "\(context): expected a real op, got replace: \(update)")
			#expect(update.html.isEmpty, "\(context): ops carry no html payload: \(update)")
		}
	}

	private func attr(_ id: String, _ name: String, _ value: String) -> FragmentUpdate {
		FragmentUpdate.attr(id: id, name: name, value: value)
	}

	@Test("tableRowSelect: class on the row + aria-checked on the control; op-only")
	func rowSelect() {
		let ops = ComponentOps.tableRowSelect(id: "tbl", rowIds: ["alice", "bob"], rowID: "alice", selected: true)
		#expect(ops == [
			attr(ComponentOps.tableRowID("tbl", 0), "class", "tr--selected"),
			attr(ComponentOps.tableSelectControlID("tbl", "alice"), "aria-checked", "true"),
		])
		// deselect clears the class and flips the control
		let off = ComponentOps.tableRowSelect(id: "tbl", rowIds: ["alice", "bob"], rowID: "alice", selected: false)
		#expect(off == [
			attr(ComponentOps.tableRowID("tbl", 0), "class", ""),
			attr(ComponentOps.tableSelectControlID("tbl", "alice"), "aria-checked", "false"),
		])
		// second row: index 1 derives cleanly
		let second = ComponentOps.tableRowSelect(id: "tbl", rowIds: ["alice", "bob"], rowID: "bob", selected: true)
		#expect(second.first?.id == ComponentOps.tableRowID("tbl", 1))
		// unknown row id: control op still emitted (the control id needs no index)
		let unknown = ComponentOps.tableRowSelect(id: "tbl", rowIds: ["alice", "bob"], rowID: "nope", selected: true)
		#expect(unknown == [attr(ComponentOps.tableSelectControlID("tbl", "nope"), "aria-checked", "true")])
		assertOpsOnly(ops + off + second + unknown, "rowSelect")
	}

	@Test("tableSelectAll: select-all + every row's class and control, op-only")
	func selectAll() {
		let ops = ComponentOps.tableSelectAll(id: "tbl", rowIds: ["alice", "bob"], selected: true)
		#expect(ops == [
			attr("tbl-select-all", "aria-checked", "true"),
			attr(ComponentOps.tableRowID("tbl", 0), "class", "tr--selected"),
			attr(ComponentOps.tableSelectControlID("tbl", "alice"), "aria-checked", "true"),
			attr(ComponentOps.tableRowID("tbl", 1), "class", "tr--selected"),
			attr(ComponentOps.tableSelectControlID("tbl", "bob"), "aria-checked", "true"),
		])
		let off = ComponentOps.tableSelectAll(id: "tbl", rowIds: ["alice"], selected: false)
		#expect(off == [
			attr("tbl-select-all", "aria-checked", "false"),
			attr(ComponentOps.tableRowID("tbl", 0), "class", ""),
			attr(ComponentOps.tableSelectControlID("tbl", "alice"), "aria-checked", "false"),
		])
		assertOpsOnly(ops + off, "selectAll")
	}

	@Test("tableSort: header affordance on the active + previously-active columns")
	func sort() {
		// ascending activation on column 1 (previously 0)
		let ascend = ComponentOps.tableSort(
			id: "tbl", sortableColumns: [0, 1], column: 1,
			direction: .ascending, previousColumn: 0
		)
		#expect(ascend == [
			attr(ComponentOps.tableSortControlID("tbl", 1), "class", "sort sort--active"),
			attr(ComponentOps.tableSortControlID("tbl", 0), "class", "sort"),
		])
		// descending adds the marker
		let descend = ComponentOps.tableSort(
			id: "tbl", sortableColumns: [0, 1], column: 1,
			direction: .descending, previousColumn: 0
		)
		#expect(descend == [
			attr(ComponentOps.tableSortControlID("tbl", 1), "class", "sort sort--active sort--desc"),
			attr(ComponentOps.tableSortControlID("tbl", 0), "class", "sort"),
		])
		// previous == new: only the active column is patched
		let same = ComponentOps.tableSort(
			id: "tbl", sortableColumns: [0, 1], column: 1,
			direction: .ascending, previousColumn: 1
		)
		#expect(same == [attr(ComponentOps.tableSortControlID("tbl", 1), "class", "sort sort--active")])
		// a non-sortable column activates nothing
		#expect(ComponentOps.tableSort(
			id: "tbl", sortableColumns: [0, 1], column: 2,
			direction: .ascending, previousColumn: nil
		).isEmpty)
		assertOpsOnly(ascend + descend + same, "sort")
	}

	@Test("tableExpand: tr--expanded class + the control's aria-expanded")
	func expand() {
		let ops = ComponentOps.tableExpand(id: "tbl", rowIds: ["alice", "bob"], rowID: "alice", expanded: true)
		#expect(ops == [
			attr(ComponentOps.tableRowID("tbl", 0), "class", "tr--expanded"),
			attr(ComponentOps.tableExpandControlID("tbl", "alice"), "aria-expanded", "true"),
		])
		let off = ComponentOps.tableExpand(id: "tbl", rowIds: ["alice", "bob"], rowID: "bob", expanded: false)
		#expect(off == [
			attr(ComponentOps.tableRowID("tbl", 1), "class", ""),
			attr(ComponentOps.tableExpandControlID("tbl", "bob"), "aria-expanded", "false"),
		])
		assertOpsOnly(ops + off, "expand")
	}

	@Test("chartMarkSelect: toggles chart__mark--selected onto the host's base classes")
	func chartSelect() {
		let base = ["chart__mark", "chart__sector"]
		let on = ComponentOps.chartMarkSelect(markID: ComponentOps.chartMarkID("pie", 0), classes: base, selected: true)
		#expect(on == [attr(ComponentOps.chartMarkID("pie", 0), "class", "chart__mark chart__sector chart__mark--selected")])
		let off = ComponentOps.chartMarkSelect(markID: ComponentOps.chartMarkID("pie", 0), classes: base, selected: false)
		#expect(off == [attr(ComponentOps.chartMarkID("pie", 0), "class", "chart__mark chart__sector")])
		// idempotent selection
		let again = ComponentOps.chartMarkSelect(
			markID: "pie-mark-0", classes: ["chart__mark", "chart__sector", "chart__mark--selected"], selected: true
		)
		#expect(again == [attr("pie-mark-0", "class", "chart__mark chart__sector chart__mark--selected")])
		assertOpsOnly(on + off + again, "chartSelect")
	}

	@Test("paginationPage: active page gets class+aria-current; previous reverts")
	func pagination() {
		let ops = ComponentOps.paginationPage(id: "pg", page: 3, previousPage: 2)
		#expect(ops == [
			attr(ComponentOps.paginationPageID("pg", 3), "class", "pagination__btn pagination__btn--active"),
			attr(ComponentOps.paginationPageID("pg", 3), "aria-current", "page"),
			attr(ComponentOps.paginationPageID("pg", 2), "class", "pagination__btn"),
			attr(ComponentOps.paginationPageID("pg", 2), "aria-current", ""),
		])
		// first mount / no previous: only the new page is touched
		let first = ComponentOps.paginationPage(id: "pg", page: 1, previousPage: nil)
		#expect(first == [
			attr(ComponentOps.paginationPageID("pg", 1), "class", "pagination__btn pagination__btn--active"),
			attr(ComponentOps.paginationPageID("pg", 1), "aria-current", "page"),
		])
		// same page: no revert ops
		let same = ComponentOps.paginationPage(id: "pg", page: 2, previousPage: 2)
		#expect(same.count == 2)
		assertOpsOnly(ops + first + same, "pagination")
	}

	@Test("the composed helpers equal hand-written literal dictionaries (anti-shackle)")
	func antiShackleHandWrittenEquivalence() {
		// every composed helper above is pinned against the atomics; here the
		// atomics themselves equal a fully hand-written dictionary — the
		// no-hidden-runtime proof (rules §3 / anti-shackle 5).
		let classOp = FragmentUpdate.attr(id: "x-row", name: "class", value: "a b")
		#expect(ComponentOps.classOp("x-row", ["a", "b"]) == classOp)
		#expect(ComponentOps.classOp("x-row", []) == FragmentUpdate.attr(id: "x-row", name: "class", value: ""))
		#expect(ComponentOps.ariaCheckedOp("x", true) == FragmentUpdate.attr(id: "x", name: "aria-checked", value: "true"))
		#expect(ComponentOps.ariaCheckedOp("x", false) == FragmentUpdate.attr(id: "x", name: "aria-checked", value: "false"))
		#expect(ComponentOps.ariaExpandedOp("x", true) == FragmentUpdate.attr(id: "x", name: "aria-expanded", value: "true"))
		#expect(ComponentOps.ariaCurrentOp("x", true) == FragmentUpdate.attr(id: "x", name: "aria-current", value: "page"))
		#expect(ComponentOps.ariaCurrentOp("x", false) == FragmentUpdate.attr(id: "x", name: "aria-current", value: ""))
		#expect(ComponentOps.textOp("x", "42") == FragmentUpdate.text(id: "x", value: "42"))
	}
}
