import WebUICore

// MARK: - ComponentOps — DX-11b op-emitting handlers (CONTINUUM_DX §2.11, lane D)
//
// the built-in helpers that turn component events into `FragmentOp` payloads
// (`.attr` / `.text` on the DX-11a id vocabulary) instead of whole-region
// `FragmentUpdate(id:html:)` replaces. the `FragmentOp` plane is engine-applied
// today; without these, every host hand-authors the op dictionaries the
// red-team found would otherwise be "the host's job" (§2.11).
//
// CONTRACT:
// - every composed helper emits ops whose TARGETS are DX-11a ids only —
//   `{id}-r{rowIndex}`, `{id}-sort-{column}`, `{id}-select-{rowId}`,
//   `{id}-expand-{rowId}`, `{id}-page-{n}`, `{id}-mark-{i}` — derived here in
//   ONE place (no string math in host code). the `tableRowID`/… derivations are
//   the single source of the spelling, diffed against the components' own
//   markup by the op-vocabulary tests.
// - every op returned is a REAL op (`op != nil`, `op != .replace`,
//   `html.isEmpty`) — a handler that returns these never triggers a
//   whole-region replace. `FragmentUpdate.text` stays available for the
//   token-append path (pagination numbers); the composed pagination helper uses
//   the attr plane (class + aria-current), the two attrs the engine allowlist
//   and the active-page affordance render.
// - the op VALUE is the exact string the component renders for that state
//   (`tr--selected`, `sort sort--active sort--desc`, `pagination__btn
//   pagination__btn--active`, `aria-checked="true|false"`,
//   `chart__mark--selected` …), so the engine-applied DOM equals a re-render.
//
// SCOPE BOUNDARY (documented): `aria-sort` lives on the `<th>`, which carries
// no DX-11a id (the id is on the inner `.sort` span — DX-11a pin, and moving
// it is the W3 routing re-target). the sort helper therefore patches the
// pinned span via `attr class` (the visible sort affordance), not `aria-sort`;
// the th-id re-target is the gate for an aria-sort op.

/// DX-11b — op-emitting handler factories for the interactive built-ins.
public enum ComponentOps {

    // ── DX-11a id derivation (one spelling for the whole surface) ─────────

    /// the data-row id `{id}-r{rowIndex}` (DX-11a); `rowIndex` is the row's
    /// position in the rendered rows array — stable for a select/expand event
    /// (no reorder), NOT for a sort (the table re-sorts server-side; the sort
    /// helper only touches the header affordance).
    @inlinable
    public static func tableRowID(_ id: String, _ rowIndex: Int) -> String {
        "\(id)-r\(rowIndex)"
    }

    /// the sortable-header control id `{id}-sort-{column}` (DX-11a; the span
    /// inside the `<th>`).
    @inlinable
    public static func tableSortControlID(_ id: String, _ column: Int) -> String {
        "\(id)-sort-\(column)"
    }

    /// the row-select control id `{id}-select-{rowId}` (DX-11a; `rowId` is the
    /// same `data-key`/`rowIds` identity the row id derives from).
    @inlinable
    public static func tableSelectControlID(_ id: String, _ rowID: String) -> String {
        "\(id)-select-\(rowID)"
    }

    /// the expand control id `{id}-expand-{rowId}` (DX-11a).
    @inlinable
    public static func tableExpandControlID(_ id: String, _ rowID: String) -> String {
        "\(id)-expand-\(rowID)"
    }

    /// the page-number button id `{id}-page-{n}` (DX-11a/WebUIPagination).
    @inlinable
    public static func paginationPageID(_ id: String, _ page: Int) -> String {
        "\(id)-page-\(page)"
    }

    /// the chart mark id `{id}-mark-{index}` (DX-11a; sector/categorical
    /// marks; points use the single `{id}-mark-pt` id — pass it via the
    /// `markID` overload).
    @inlinable
    public static func chartMarkID(_ id: String, _ index: Int) -> String {
        "\(id)-mark-\(index)"
    }

    // ── atomic op builders (the hand-written dictionary the composed helpers
    //    are pinned against — anti-shackle: a host may write these by hand and
    //    get the identical bytes) ──────────────────────────────────────────

    /// `.attr class` on `elementID` with the given class list (joined by
    /// space; empty list clears the attribute — the engine sets it to "").
    public static func classOp(_ elementID: String, _ classes: [String]) -> FragmentUpdate {
        .attr(id: elementID, name: "class", value: classes.joined(separator: " "))
    }

    /// `.attr aria-checked` with the rendered spelling `true`/`false`.
    public static func ariaCheckedOp(_ elementID: String, _ checked: Bool) -> FragmentUpdate {
        .attr(id: elementID, name: "aria-checked", value: checked ? "true" : "false")
    }

    /// `.attr aria-expanded` with the rendered spelling `true`/`false`.
    public static func ariaExpandedOp(_ elementID: String, _ expanded: Bool) -> FragmentUpdate {
        .attr(id: elementID, name: "aria-expanded", value: expanded ? "true" : "false")
    }

    /// `.attr aria-current` — `"page"` when current, cleared otherwise
    /// (the paginated page-button affordance).
    public static func ariaCurrentOp(_ elementID: String, _ current: Bool) -> FragmentUpdate {
        .attr(id: elementID, name: "aria-current", value: current ? "page" : "")
    }

    /// `.text` — set the element's text content (the token-append primitive);
    /// used for the pagination page-number channel where a host re-numbers.
    public static func textOp(_ elementID: String, _ value: String) -> FragmentUpdate {
        .text(id: elementID, value: value)
    }

    // ── composed event → ops ──────────────────────────────────────────────

    /// **table row select** — the `onSelect` handler's op answer: the row's
    /// `tr--selected` class (`.attr class` on `{id}-r{rowIndex}`) + the
    /// control's `aria-checked` (on `{id}-select-{rowId}`). `rowIds` is the
    /// same parallel array the table renders with (needed to derive the row's
    /// index from its key — the strings never meet in host code).
    ///
    /// note: the row's class op carries ONLY the selection marker. a row that
    /// is ALSO expanded (or otherwise classed) composes `classOp(tableRowID(…,
    /// index), [own markers] + ["tr--selected"])` from the atomics above.
    public static func tableRowSelect(
        id: String,
        rowIds: [String],
        rowID: String,
        selected: Bool
    ) -> [FragmentUpdate] {
        var ops = [
            ariaCheckedOp(tableSelectControlID(id, rowID), selected)
        ]
        if let rowIndex = rowIds.firstIndex(of: rowID) {
            ops.insert(classOp(tableRowID(id, rowIndex), selected ? ["tr--selected"] : []), at: 0)
        }
        return ops
    }

    /// **table select-all** — the `onSelectAll` handler's op answer: the
    /// select-all control's `aria-checked` + every row's class and control
    /// `aria-checked` (the whole selection plane in attr ops).
    public static func tableSelectAll(
        id: String,
        rowIds: [String],
        selected: Bool
    ) -> [FragmentUpdate] {
        var ops: [FragmentUpdate] = [ariaCheckedOp("\(id)-select-all", selected)]
        for (rowIndex, rowID) in rowIds.enumerated() {
            ops.append(classOp(tableRowID(id, rowIndex), selected ? ["tr--selected"] : []))
            ops.append(ariaCheckedOp(tableSelectControlID(id, rowID), selected))
        }
        return ops
    }

    /// **table sort state** — the `onSort` handler's op answer: the header
    /// affordance for the newly-active sortable column and (when given) the
    /// previously-active one — `.attr class` on `{id}-sort-{column}`
    /// (`sort` / `sort sort--active[ sort--desc]`, the exact strings the
    /// component renders). row reordering stays server-side (the table
    /// source of truth re-renders via the ops' host state); sorting only ever
    /// patches headers here. see the `aria-sort` scope boundary above.
    public static func tableSort(
        id: String,
        sortableColumns: [Int],
        column: Int,
        direction: WebUITable.SortDirection,
        previousColumn: Int? = nil
    ) -> [FragmentUpdate] {
        guard sortableColumns.contains(column) else { return [] }
        var ops: [FragmentUpdate] = []
        var active = [String]()
        if direction == .descending { active = ["sort", "sort--active", "sort--desc"] }
        else { active = ["sort", "sort--active"] }
        ops.append(classOp(tableSortControlID(id, column), active))
        if let previous = previousColumn, previous != column, sortableColumns.contains(previous) {
            ops.append(classOp(tableSortControlID(id, previous), ["sort"]))
        }
        return ops
    }

    /// **table expand** — the `onToggleExpand` handler's op answer: the row's
    /// `tr--expanded` class + the control's `aria-expanded` on
    /// `{id}-expand-{rowId}`. the DETAIL row's materialization is a structural
    /// insert (needs a parent id the component does not emit today) — that
    /// stays a host-side region op; this helper owns the affordance deltas.
    public static func tableExpand(
        id: String,
        rowIds: [String],
        rowID: String,
        expanded: Bool
    ) -> [FragmentUpdate] {
        var ops = [
            ariaExpandedOp(tableExpandControlID(id, rowID), expanded)
        ]
        if let rowIndex = rowIds.firstIndex(of: rowID) {
            ops.insert(classOp(tableRowID(id, rowIndex), expanded ? ["tr--expanded"] : []), at: 0)
        }
        return ops
    }

    /// **chart mark select** — the `onSelectMark` handler's op answer: the
    /// `.attr class` on the mark id (`{id}-mark-{i}` via `chartMarkID`, or the
    /// `{id}-mark-pt` point id / `{id}-mark-{cat}-{series}` bar id passed
    /// directly) with the `chart__mark--selected` marker toggled onto the
    /// mark's own class list (the host supplies the base classes it renders —
    /// color/geometry — and the helper owns the selection marker).
    public static func chartMarkSelect(
        markID: String,
        classes: [String],
        selected: Bool
    ) -> [FragmentUpdate] {
        var rendered = classes
        if selected {
            if !rendered.contains("chart__mark--selected") { rendered.append("chart__mark--selected") }
        } else {
            rendered.removeAll { $0 == "chart__mark--selected" }
        }
        return [classOp(markID, rendered)]
    }

    /// **pagination active page** — the `onPageChange` handler's op answer:
    /// the newly-active page button gets `pagination__btn pagination__btn--active`
    /// + `aria-current="page"`, and the previously-active button (when given)
    /// reverts to `pagination__btn` and clears `aria-current`. only the two
    /// affected buttons are touched — the page-number window the component
    /// windowed is unchanged.
    public static func paginationPage(
        id: String,
        page: Int,
        previousPage: Int? = nil
    ) -> [FragmentUpdate] {
        var ops: [FragmentUpdate] = [
            classOp(paginationPageID(id, page), ["pagination__btn", "pagination__btn--active"]),
            ariaCurrentOp(paginationPageID(id, page), true),
        ]
        if let previous = previousPage, previous != page {
            ops.append(classOp(paginationPageID(id, previous), ["pagination__btn"]))
            ops.append(ariaCurrentOp(paginationPageID(id, previous), false))
        }
        return ops
    }
}
