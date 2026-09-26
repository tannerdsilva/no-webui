import Synchronization
import WebUI
import WebUIDesignSystem

// MARK: - ShowcaseState

/// server-side state for the live showcase demos. mutex-backed value box
/// (same pattern as the smoke page): handlers mutate, render reads — the
/// server is the source of truth, every patch re-emits post-state markup.
/// public so the showcase server can own one instance and share it with
/// both the render closure and the wired handlers.
/// one line of the chat demo: which side it renders on, the text, and the label
/// the bubble shows as a timestamp.
struct ChatLine: Sendable {
	var side: String
	var text: String
	var time: String
}

public final class ShowcaseState: Sendable {
	public init() {}

	private struct Values {
		var count = 0
		var echo = ""
		var preview = ""
		var activeTab = "tab-info"
		var tableSortColumn: Int? = 2
		var tableSortAscending = false
		var tableSelected: Set<String> = ["search"]
		var tableExpanded: Set<String> = ["web"]
		var page = 5
		var rowsPerPage = 25
		var treeExpanded: Set<String> = ["src", "ui"]
		var treeSelected: String? = "view"
		var hiddenColumns: Set<Int> = []
		var chat: [ChatLine] = [
			ChatLine(side: "received", text: "Deploy went out at 09:12.", time: "09:12"),
			ChatLine(side: "sent", text: "Watching the dashboards.", time: "09:13"),
			ChatLine(side: "received", text: "All green on my side.", time: "09:14"),
		]
	}

	private let values = Mutex(Values())

	var count: Int {
		get { values.withLock { $0.count } }
		set { values.withLock { $0.count = newValue } }
	}
	var echo: String {
		get { values.withLock { $0.echo } }
		set { values.withLock { $0.echo = newValue } }
	}
	var preview: String {
		get { values.withLock { $0.preview } }
		set { values.withLock { $0.preview = newValue } }
	}
	var activeTab: String {
		get { values.withLock { $0.activeTab } }
		set { values.withLock { $0.activeTab = newValue } }
	}
	var tableSortColumn: Int? {
		get { values.withLock { $0.tableSortColumn } }
		set { values.withLock { $0.tableSortColumn = newValue } }
	}
	var tableSortAscending: Bool {
		get { values.withLock { $0.tableSortAscending } }
		set { values.withLock { $0.tableSortAscending = newValue } }
	}
	var tableSelected: Set<String> {
		get { values.withLock { $0.tableSelected } }
		set { values.withLock { $0.tableSelected = newValue } }
	}
	var tableExpanded: Set<String> {
		get { values.withLock { $0.tableExpanded } }
		set { values.withLock { $0.tableExpanded = newValue } }
	}
	var page: Int {
		get { values.withLock { $0.page } }
		set { values.withLock { $0.page = newValue } }
	}
	var rowsPerPage: Int {
		get { values.withLock { $0.rowsPerPage } }
		set { values.withLock { $0.rowsPerPage = newValue } }
	}
	var treeExpanded: Set<String> {
		get { values.withLock { $0.treeExpanded } }
		set { values.withLock { $0.treeExpanded = newValue } }
	}
	var treeSelected: String? {
		get { values.withLock { $0.treeSelected } }
		set { values.withLock { $0.treeSelected = newValue } }
	}

	var hiddenColumns: Set<Int> {
		get { values.withLock { $0.hiddenColumns } }
		set { values.withLock { $0.hiddenColumns = newValue } }
	}

	var chat: [ChatLine] {
		get { values.withLock { $0.chat } }
		set { values.withLock { $0.chat = newValue } }
	}

	/// append one outgoing line: the chat demo's server-side mutation.
	func appendChat(_ text: String) {
		values.withLock { $0.chat.append(ChatLine(side: "sent", text: text, time: "just now")) }
	}

	var tableSort: (column: Int, direction: WebUITable.SortDirection)? {
		values.withLock { v in
			v.tableSortColumn.map { ($0, v.tableSortAscending ? .ascending : .descending) }
		}
	}
}

// MARK: - live demo HTML builders

func counterValueHTML(_ value: Int) -> String {
	"<span id=\"counter-value\" class=\"counter-number\">\(value)</span>"
}

func echoResultHTML(_ text: String) -> String {
	"<div id=\"echo-result\">\(htmlEscape(text))</div>"
}

func previewOutputHTML(_ text: String) -> String {
	"<span id=\"preview-output\">\(htmlEscape(text))</span>"
}

func tabContentHTML(_ tabID: String) -> String {
	let body: String
	switch tabID {
	case "tab-stats":
		body = "Statistics tab content — routed from the server on every switch."
	case "tab-log":
		body = "Log tab content — routed from the server on every switch."
	default:
		body = "Information tab content. Click other tabs to switch."
	}
	// re-emits the same anchored container the page renders initially: the
	// fragment patch replaces the element whose id matches, so the anchor and
	// its class must be carried by the patched html itself.
	return "<div id=\"tab-content\" class=\"tab-content-box\"><p>\(body)</p></div>"
}

// MARK: - live demo views

func contentTabs(state: ShowcaseState) -> WebUITabs {
	WebUITabs(
		tabs: [
			TabItem(id: "tab-info", label: "Info"),
			TabItem(id: "tab-stats", label: "Stats"),
			TabItem(id: "tab-log", label: "Log"),
		],
		activeTab: state.activeTab,
		id: "content-tabs",
		onSelect: { me, tabID in
			state.activeTab = tabID
			return [
				me.update(contentTabs(state: state)),
				FragmentUpdate(id: "tab-content", html: tabContentHTML(tabID)),
			]
		}
	)
}

/// the live chat demo: a bottom-anchored scroller over the server-held lines,
/// with a typing indicator pinned at the newest edge. the scroller reverses its
/// children internally, so this list stays chronological.
func liveChat(state: ShowcaseState) -> WebUIMessageScroller {
	WebUIMessageScroller(height: "22rem", id: "live-chat", ariaLabel: "Live conversation") {
		WebUIMarker("Live session")
		for line in state.chat {
			WebUIChatBubble(
				line.text,
				side: line.side == "sent" ? .sent : .received,
				time: line.time,
				receipt: line.side == "sent" ? .delivered : nil
			)
		}
		WebUITypingIndicator(inline: true)
	}
}

/// the column-visibility control for the interactive table demo. it is a plain
/// `WebUIMenu` whose selection is dispatched by `targetId` — the container-handler
/// pattern — and whose effect is host state: toggling an index re-renders the menu
/// (for the check marks) and the table (which simply stops emitting that column).
func columnMenu(state: ShowcaseState) -> WebUIMenu {
	let columns = ["Service", "Region", "p95"]
	return WebUIMenu(
		items: columns.enumerated().map { index, name in
			WebUIMenu.Item(
				name,
				icon: state.hiddenColumns.contains(index) ? .xCircle : .checkCircle
			)
		},
		id: "column-menu",
		onSelect: { event in
			guard let raw = event.string("targetId"),
			      let last = raw.split(separator: "-").last,
			      let index = Int(last) else { return [] }
			if state.hiddenColumns.contains(index) {
				state.hiddenColumns.remove(index)
			} else {
				state.hiddenColumns.insert(index)
			}
			return [
				FragmentUpdate(id: "column-menu", html: columnMenu(state: state).render()),
				FragmentUpdate(id: "demo-interactive", html: interactiveTable(state: state).render()),
			]
		},
		header: "Columns",
		panel: true
	)
}

func interactiveTable(state: ShowcaseState) -> WebUITable {
	WebUITable(
		headers: ["Service", "Region", "p95"],
		rows: [
			[Text("web"), Text("us-east-1"), Text("42 ms")],
			[Text("api"), Text("eu-west-2"), Text("18 ms")],
			[Text("search"), Text("us-west-2"), Text("61 ms")],
		],
		// not wrapped: the table element is the typed `me` patch target, so
		// the fragment re-emitted by `me.update` must be the same element
		// shape (a wrap div would nest on every patch).
		wrapped: false,
		alignments: [.leading, .leading, .trailing],
		id: "demo-interactive",
		sortableColumns: [0, 1, 2],
		hiddenColumns: state.hiddenColumns,
		sort: state.tableSort,
		selectable: true,
		rowIds: ["web", "api", "search"],
		selectedRows: state.tableSelected,
		expandedRows: state.tableExpanded,
		rowDetails: [
			"web": Text("8 instances · 99.98% SLA · canary 10% to v2.14"),
			"api": Text("4 instances · 99.95% SLA · zero-downtime deploys"),
		]
	)
	.onSort { me, column in
		if state.tableSortColumn == column {
			state.tableSortAscending.toggle()
		} else {
			state.tableSortColumn = column
			state.tableSortAscending = true
		}
		return [me.update(interactiveTable(state: state))]
	}
	.onSelectAll { me in
		state.tableSelected = state.tableSelected.count == 3 ? [] : ["web", "api", "search"]
		return [me.update(interactiveTable(state: state))]
	}
	.onSelect { me, rowID in
		if state.tableSelected.contains(rowID) {
			state.tableSelected.remove(rowID)
		} else {
			state.tableSelected.insert(rowID)
		}
		return [me.update(interactiveTable(state: state))]
	}
	.onToggleExpand { me, rowID in
		if state.tableExpanded.contains(rowID) {
			state.tableExpanded.remove(rowID)
		} else {
			state.tableExpanded.insert(rowID)
		}
		return [me.update(interactiveTable(state: state))]
	}
}

func paginationDemo(state: ShowcaseState) -> some View {
	Div(id: "demo-pagination") {
		WebUIPagination(
			page: state.page,
			pages: 12,
			id: "demo-pagination",
			rowsPerPage: state.rowsPerPage,
			rowsPerPageOptions: [10, 25, 50, 100]
		)
		.onPageChange { me, page in
			state.page = page
			return [me.update(paginationDemo(state: state))]
		}
		.onRowsPerPageChange { me, size in
			state.rowsPerPage = size
			state.page = 1
			return [me.update(paginationDemo(state: state))]
		}
	}
}

// MARK: - tree demo

// the showcase tree's node graph, shared by render + toggle routing.
private let showcaseTreeNodes: [WebUITree.Node] = [
	WebUITree.Node(id: "src", label: "src", icon: .folder, children: [
		WebUITree.Node(id: "main", label: "main.swift", icon: .fileText),
		WebUITree.Node(id: "ui", label: "ui", icon: .folder, children: [
			WebUITree.Node(id: "view", label: "view.swift", icon: .fileText),
			WebUITree.Node(id: "state", label: "state.swift", icon: .fileText),
		]),
	]),
	WebUITree.Node(id: "tests", label: "tests", icon: .folder, children: [
		WebUITree.Node(id: "smoke", label: "smoke.swift", icon: .fileText),
	]),
]

private func treeNodeHasChildren(_ id: String) -> Bool {
	func find(_ nodes: [WebUITree.Node]) -> Bool {
		for node in nodes {
			if node.id == id { return !(node.children?.isEmpty ?? true) }
			if let children = node.children, find(children) { return true }
		}
		return false
	}
	return find(showcaseTreeNodes)
}

func treeDemo(state: ShowcaseState) -> WebUITree {
	WebUITree(
		nodes: showcaseTreeNodes,
		id: "demo-tree",
		expanded: state.treeExpanded,
		selected: state.treeSelected,
		onToggle: { event in
			let raw = event.string("targetId") ?? ""
			let prefix = "demo-tree-node-"
			guard raw.hasPrefix(prefix) else { return [] }
			let nodeID = String(raw.dropFirst(prefix.count))
			if treeNodeHasChildren(nodeID) {
				if state.treeExpanded.contains(nodeID) {
					state.treeExpanded.remove(nodeID)
				} else {
					state.treeExpanded.insert(nodeID)
				}
			} else {
				state.treeSelected = nodeID
			}
			return [FragmentUpdate(id: "demo-tree", html: treeDemo(state: state).render())]
		}
	)
}
