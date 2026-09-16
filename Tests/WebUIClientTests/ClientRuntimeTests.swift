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
}
