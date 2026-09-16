import Testing
import WebUICore
@testable import WebUIClientRuntime

// the resident client runtime: boot registers handlers into the page router,
// and dispatch produces fragments. these specs run on the host (the host
// executor drives `await router.handle`); the shared runtime statics require a
// serialized suite, and the pump path is exercised by `WebUIClient
// --verify-event` under WasmKit (host `handleEvent` can't synchronously observe
// its task — the pump is a no-op there).
@Suite(.serialized)
struct ClientRuntimeTests {
	@Test("boot renders the proof page and registers the increment control")
	func bootRegistersHandler() {
		ClientRuntime.boot()
		#expect(ClientRuntime.bootPageHTML.contains("proof-inc"))
		#expect(ClientRuntime.bootPageHTML.contains("data-component-id=\"c0\""))
		#expect(ClientRuntime.bootPageHTML.contains("data-event=\"click\""))
		#expect(ClientRuntime.router.handlerCount == 1)
	}

	@Test("the registered handler dispatches and produces the counter fragment")
	func registeredHandlerDispatch() async {
		ClientRuntime.boot()
		let updates = await ClientRuntime.router.handle(
			EventData(component: "c0", event: "click", data: [:])
		)
		#expect(updates.count == 1)
		#expect(updates[0].id == "client-counter")
		#expect(updates[0].html.contains(">1<"))
	}

	@Test("the local-search vertical filters the resident dataset in wasm")
	func localSearchFiltersClientSide() async {
		ClientRuntime.bootSearch()
		let updates = await ClientRuntime.router.handle(
			EventData(component: "c0", event: "input", data: ["value": "a"])
		)
		#expect(updates.count == 1)
		let html = updates[0].html
		#expect(html.contains(">api<"))
		#expect(html.contains(">auth<"))
		#expect(!html.contains(">web<"))
		#expect(html.contains("search-rows"))
		let rows = html.components(separatedBy: "<tr>").count - 1
		// 1 header row + 2 filtered data rows
		#expect(rows == 3)
	}

	@Test("the typed sort control reorders rows client-side")
	func typedSortReorders() async {
		ClientRuntime.bootSearch()
		// default sort = column 0 ascending (name order). clicking column 1
		// (region) through the typed control registers the re-sort.
		let updates = await ClientRuntime.router.handle(
			EventData(component: "client-table-sort-1", event: "click", data: [:])
		)
		#expect(updates.count == 1)
		let html = updates[0].html
		#expect(html.contains("client-table"))
		#expect(html.contains("aria-sort"))
		// region ascending: ap-south-1 (auth) before eu-west-2 (api)
		let auth = html.range(of: ">auth<")?.lowerBound
		let api = html.range(of: ">api<")?.lowerBound
		#expect(auth != nil && api != nil)
		#expect(auth! < api!, "region sort must order auth before api: \(html)")
	}

	// p5-t4: selection + expand route through the CLIENT router — the
	// websocket is silent; each toggle re-renders the table fragment in wasm.
	@Test("select-all and row selection re-render the table client-side")
	func clientTableSelects() async throws {
		ClientRuntime.bootSearch()
		// select all
		var updates = await ClientRuntime.router.handle(
			EventData(component: "client-table-select-all", event: "click", data: [:])
		)
		var table = try #require(updates.first)
		#expect(table.html.contains("aria-checked=\"true\""))
		#expect(table.html.components(separatedBy: "tr--selected").count - 1 == 4)
		// deselect a single row: three rows stay selected
		updates = await ClientRuntime.router.handle(
			EventData(component: "client-table-select-web", event: "click", data: [:])
		)
		table = try #require(updates.first)
		#expect(table.html.components(separatedBy: "tr--selected").count - 1 == 3)
	}

	@Test("expand toggle reveals the row detail client-side")
	func clientTableExpands() async throws {
		ClientRuntime.bootSearch()
		let updates = await ClientRuntime.router.handle(
			EventData(component: "client-table-expand-web", event: "click", data: [:])
		)
		let table = try #require(updates.first)
		#expect(table.html.contains("web tier"))
		// collapse again
		let collapse = await ClientRuntime.router.handle(
			EventData(component: "client-table-expand-web", event: "click", data: [:])
		)
		let collapsed = try #require(collapse.first)
		#expect(!collapsed.html.contains("web tier"))
	}

	// p5-t6: chart selection routes through the CLIENT router — the mark
	// click re-renders the chart fragment with a wasm-computed selection line.
	@Test("chart mark selection routes through the client router")
	func clientChartSelects() async throws {
		ClientRuntime.bootSearch()
		#expect(ClientRuntime.bootPageHTML.contains("client-chart"))
		guard let markControl = Self.markControlID(in: ClientRuntime.bootPageHTML) else {
			Issue.record("no chart mark control in boot markup")
			return
		}
		let updates = await ClientRuntime.router.handle(
			EventData(component: ComponentID(markControl), event: "click", data: [:])
		)
		let fragment = try #require(updates.first)
		#expect(fragment.html.contains("chart__selection"), "a mark click must render the selection line")
	}

	private static func markControlID(in html: String) -> String? {
		let needle = "data-component-id=\""
		var searchStart = html.startIndex
		while let range = html[searchStart...].range(of: needle) {
			let rest = html[range.upperBound...]
			let id = String(rest.prefix(while: { $0 != "\"" }))
			if id.hasPrefix("client-chart-") { return id }
			searchStart = range.upperBound
		}
		return nil
	}
}
