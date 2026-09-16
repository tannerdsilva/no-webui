import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIChart
import WebUISmokeShared

// MARK: - Shared state

final class SmokeState: Sendable {
	private struct Values {
		var count = 0
		var progress = 0.25
		var echo = ""
		// interactive table demo (server is the source of truth)
		var tableSortColumn = 0
		var tableSortAsc = true
		var tableSelected: Set<String> = []
		var tableExpanded: Set<String> = []
		// interactive chart demo (chart selection: click a bar → server re-renders)
		var chartSelected: String? = nil
	}
	private let values = Mutex(Values())

	var count: Int {
		get { values.withLock { $0.count } }
		set { values.withLock { $0.count = newValue } }
	}
	var progress: Double {
		get { values.withLock { $0.progress } }
		set { values.withLock { $0.progress = newValue } }
	}
	var echo: String {
		get { values.withLock { $0.echo } }
		set { values.withLock { $0.echo = newValue } }
	}
	var tableSortColumn: Int {
		get { values.withLock { $0.tableSortColumn } }
		set { values.withLock { $0.tableSortColumn = newValue } }
	}
	var tableSortAsc: Bool {
		get { values.withLock { $0.tableSortAsc } }
		set { values.withLock { $0.tableSortAsc = newValue } }
	}
	var tableSelected: Set<String> {
		get { values.withLock { $0.tableSelected } }
		set { values.withLock { $0.tableSelected = newValue } }
	}
	var tableExpanded: Set<String> {
		get { values.withLock { $0.tableExpanded } }
		set { values.withLock { $0.tableExpanded = newValue } }
	}
	var chartSelected: String? {
		get { values.withLock { $0.chartSelected } }
		set { values.withLock { $0.chartSelected = newValue } }
	}
}

// MARK: - Interactive table demo data

let smokeTableRecords: [(id: String, name: String, region: String, ms: Int, detail: String)] = [
	("web", "web", "us-east-1", 42, "8 instances · 99.98% SLA · canary 10% to v2.14"),
	("api", "api", "eu-west-2", 18, "4 instances · 99.95% SLA · zero-downtime deploys"),
	("search", "search", "us-west-2", 61, "12 shards · 99.9% SLA · 3 warm nodes"),
	("auth", "auth", "ap-south-1", 9, "3 instances · 100% SLA · hardware-backed keys"),
]

func interactiveTableHTML(state: SmokeState) -> String {
	let col = state.tableSortColumn
	let asc = state.tableSortAsc
	let sorted = smokeTableRecords.sorted { a, b in
		let less: Bool
		switch col {
		case 1: less = a.region.localizedCaseInsensitiveCompare(b.region) == .orderedAscending
		case 2: less = a.ms < b.ms
		default: less = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		}
		return asc ? less : !less
	}
	let rows = sorted.map { (rec: (id: String, name: String, region: String, ms: Int, detail: String)) in
		[Text(rec.name), Text(rec.region), Text("\(rec.ms) ms")]
	}
	let details = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, Text($0.detail)) })

	// Typed handlers: the table self-wires each control as a routed component
	// under its stable id ({id}-sort-{col} / -select-all / -select-{rowId} /
	// -expand-{rowId}). `me` references the table root, so the handler can
	// re-render the table in place with zero id strings. The fullstack driver
	// drives these same controls over the WS by their component ids.
	return WebUITable(
		headers: ["Name", "Region", "p95"],
		rows: rows,
		alignments: [.leading, .leading, .trailing],
		id: "interactive-table",
		sortableColumns: [0, 1, 2],
		sort: (col, asc ? .ascending : .descending),
		selectable: true,
		rowIds: sorted.map { $0.id },
		selectedRows: state.tableSelected,
		expandedRows: state.tableExpanded,
		rowDetails: details
	)
	.onSort { me, column in
		if state.tableSortColumn == column { state.tableSortAsc.toggle() }
		else { state.tableSortColumn = column; state.tableSortAsc = true }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onSelectAll { me in
		if state.tableSelected.count == smokeTableRecords.count { state.tableSelected = [] }
		else { state.tableSelected = Set(smokeTableRecords.map { $0.id }) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onSelect { me, rowID in
		if state.tableSelected.contains(rowID) { state.tableSelected.remove(rowID) }
		else { state.tableSelected.insert(rowID) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.onToggleExpand { me, rowID in
		if state.tableExpanded.contains(rowID) { state.tableExpanded.remove(rowID) }
		else { state.tableExpanded.insert(rowID) }
		return [me.replace(with: interactiveTableHTML(state: state))]
	}
	.render()
}

// MARK: - Display-element renderers (stable ids, no event handlers)

func counterValueHTML(_ n: Int) -> String {
	"<div id=\"counter-value\" class=\"counter-value\" role=\"status\"><span>\(n)</span></div>"
}

func progressValueHTML(_ value: Double) -> String {
	let bar = WebUIProgress(value: value, variant: .primary, showLabel: true, size: .md).render()
	return "<div id=\"progress-value\">\(bar)</div>"
}

func echoOutHTML(_ text: String) -> String {
	let safe = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
	return "<div id=\"echo-out\" class=\"echo-out\" role=\"status\"><span class=\"echo-out__text\">\(safe)</span></div>"
}

// MARK: - Interactive chart demo data

let smokeChartData: [(month: String, product: String, sales: Double)] = [
	("Jan", "Atlas", 12), ("Jan", "Boreas", 8),
	("Feb", "Atlas", 20), ("Feb", "Boreas", 15),
	("Mar", "Atlas", 16), ("Mar", "Boreas", 24),
]

func smokeChartHTML(state: SmokeState) -> String {
	var marks: [ChartMark] = []
	for d in smokeChartData {
		marks.append(BarMark(x: .value("Month", d.month), y: .value("Sales", d.sales))
			.foregroundStyle(by: d.product)
			.stacking(.unstacked)
			.makeMark())
	}
	return Chart(marks)
		.chartID("smoke-chart")
		.chartTitle("Quarterly sales by product")
		.chartAccessibilityLabel("Bar chart of quarterly sales by product")
		.chartYScale(.linear(domain: 0...28))
		.chartSelection(axis: .x, value: .category(state.chartSelected ?? ""))
		.onSelectMark { me, category in
			state.chartSelected = (state.chartSelected == category) ? nil : category
			return [me.replace(with: smokeChartHTML(state: state))]
		}
		.render()
}

// MARK: - Page shell

// Page-level layout for the smoke page only (injected via the document's
// `head:` slot, mirroring how the showcase scopes its own shell). The
// design system owns component styling; the page owns its gutter,
// header, and card rhythm. tokens come from the design system :root.
let smokePageStyle: String = """
	<style>
	.smoke { max-width: 56rem; margin: 0 auto; padding: var(--space-8) var(--space-6) var(--space-10); }
	.smoke__header { margin-bottom: var(--space-6); }
	.smoke__header h1 { font-size: var(--font-size-2xl); font-weight: 700; letter-spacing: -0.02em; line-height: 1.15; }
	.smoke__subtitle { margin-top: var(--space-2); color: var(--color-text-muted); font-size: var(--font-size-sm); }
	.smoke__content { display: grid; gap: var(--space-5); }
	.smoke__content > .card { padding: var(--space-5); }
	.smoke__content > .card > h3 { font-size: var(--font-size-sm); font-weight: 600; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: var(--space-4); }
	.smoke__actions { display: flex; gap: var(--space-2); margin-top: var(--space-4); }
	.smoke .counter-value { font-size: var(--font-size-3xl); font-weight: 700; font-variant-numeric: tabular-nums; line-height: 1.1; margin-bottom: var(--space-1); }
	.smoke .echo-out { margin-top: var(--space-3); font-size: var(--font-size-sm); color: var(--color-text-muted); min-height: 1.4em; }
	.smoke .echo-out__text { color: var(--color-text); font-family: var(--font-mono); }
	.smoke .table-wrap { margin-top: var(--space-2); }
	.smoke__chart { margin-top: var(--space-1); }
	.smoke__chart-hint { margin-top: var(--space-3); font-size: var(--font-size-xs); color: var(--color-text-faint); }
	@media (max-width: 720px) { .smoke { padding: var(--space-6) var(--space-4) var(--space-8); } }
	</style>
"""

// MARK: - Page assembly (renders interactive views, registers handlers)

func renderSmokePage(state: SmokeState, router: EventRouter) -> String {
	let ctx = RenderContext(router: router)
	let body = ctx.withValueBody {
		Div(class: "smoke") {
			Header(class: "smoke__header") {
				Heading("Design System — Full-Stack Smoke Test", level: .h1)
				Div(class: "smoke__subtitle") {
					Text("Live event routing: click / type → WebSocket → Swift EventRouter → fragment patch → DOM.")
				}
			}
			Main(class: "smoke__content") {
				// Counter card
				WebUICard(variant: .elevated) {
					Heading("Counter", level: .h3)
					Raw(counterValueHTML(state.count))
					Div(class: "smoke__actions") {
						WebUIButton("−", variant: .secondary, size: .md, id: "btn-dec")
							.onClick { _ in
								state.count -= 1
								return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
							}
						WebUIButton("+", variant: .primary, size: .md, id: "btn-inc")
							.onClick { _ in
								state.count += 1
								return [FragmentUpdate(id: "counter-value", html: counterValueHTML(state.count))]
							}
						WebUIButton("Reset", variant: .ghost, size: .sm, id: "btn-reset")
							.onOptimisticClick(
								predict: { [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))] },
								perform: { _ in
									state.count = 0
									return [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))]
								}
							)
					}
				}
				// Progress card
				WebUICard(variant: .outlined) {
					Heading("Progress", level: .h3)
					Raw(progressValueHTML(state.progress))
					Div(class: "smoke__actions") {
						WebUIButton("−10%", variant: .secondary, size: .sm, id: "btn-pdec")
							.onClick { _ in
								state.progress = max(0, state.progress - 0.1)
								return [FragmentUpdate(id: "progress-value", html: progressValueHTML(state.progress))]
							}
						WebUIButton("+10%", variant: .primary, size: .sm, id: "btn-pinc")
							.onClick { _ in
								state.progress = min(1, state.progress + 0.1)
								return [FragmentUpdate(id: "progress-value", html: progressValueHTML(state.progress))]
							}
					}
				}
				// Echo card
				WebUICard(variant: .flat) {
					Heading("Echo (input → server → DOM)", level: .h3)
					WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input", helpText: "Round-trips over the WebSocket.")
						.onInput { event in
							state.echo = event.string("value") ?? ""
							return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
						}
					Raw(echoOutHTML(state.echo))
				}
				// Interactive table card — sortable · selectable · expandable.
				// The persistent .table-wrap div carries the STABLE routing anchor
				// (data-component-id="interactive-table"); the inner element is
				// re-patched wholesale on every state change. One container handler
				// dispatches on event.data.targetId — the server is the source of
				// truth for sort, selection and expansion.
				WebUICard(variant: .outlined) {
					Heading("Table (sort · select · expand)", level: .h3)
					Div(id: "interactive-table-anchor", class: "table-wrap") {
						Raw(interactiveTableHTML(state: state))
					}
				}
				// Interactive chart card — WebUIChart bar chart; clicking a
				// bar routes through the runtime (SVG-safe parentNode walk)
				// to the container handler, which toggles the x-selection
				// and re-renders the figure (server is the source of truth).
				// The stable #smoke-chart-anchor div carries the routing
				// anchor (data-component-id="smoke-chart") and is NEVER
				// patched; the inner figure is re-patched in place by its own
				// id (the runtime replaces the element the fragment names).
				WebUICard(variant: .elevated) {
					Heading("Chart (bars · selection)", level: .h3)
					Div(id: "smoke-chart-anchor", class: "smoke__chart") {
						Raw(smokeChartHTML(state: state))
					}
					Div(class: "smoke__chart-hint") {
						Text("Click a bar to toggle its selection.")
					}
				}
			}
		}
	}
		return WebUIDocument(
			title: "Design System Full-Stack Smoke Test",
			body: body,
			head: smokePageStyle
		).render()
	}

// small helper to run a builder under a RenderContext value
extension RenderContext {
	func withValueBody<V: View>(_ build: () -> V) -> String {
		RenderContext.$current.withValue(self) { build().render() }
	}
}

// MARK: - HTTP / WebSocket server

final class HTTPByteBufferResponsePartHandler: ChannelOutboundHandler {
	typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
	typealias OutboundOut = HTTPServerResponsePart
	func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
		let part = Self.unwrapOutboundIn(data)
		switch part {
		case .head(let head):
			context.write(Self.wrapOutboundOut(.head(head)), promise: promise)
		case .body(let buffer):
			context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
		case .end(let trailers):
			context.write(Self.wrapOutboundOut(.end(trailers)), promise: promise)
		}
	}
}

/// close the channel when the read-idle window elapses (guards plain http
/// keep-alive, slow readers, and websockets alike).
final class IdleCloseHandler: ChannelInboundHandler {
	typealias InboundIn = IOData
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is IdleStateHandler.IdleStateEvent {
			context.close(promise: nil)
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

/// refused admission: `--max-connections` reached.
enum ConnectionGateError: Error { case atCapacity }

/// release a `ConnectionGate` slot when the channel closes. the gate is
/// acquired in the child channel initializer — before any request or upgrade
/// negotiation — so bare connect-only sockets count toward the cap.
final class ConnectionGateReleaser: ChannelInboundHandler {
	typealias InboundIn = IOData
	private let gate: ConnectionGate
	init(gate: ConnectionGate) { self.gate = gate }
	func channelInactive(context: ChannelHandlerContext) {
		gate.release()
		context.fireChannelInactive()
	}
}

struct SmokeApp {
	let state: SmokeState
	let router: EventRouter
	let pageHTML: String
	let connectionGate: ConnectionGate
	let clientWasm: [UInt8]
	let clientWasmHash: String
	let clientDemoPage: String
	let searchDemoPage: String
}

/// read the release `WebUIClient.wasm` product (built separately with the wasm
/// sdk) so the smoke server can serve it as a first-class static asset. an
/// absent artifact yields empty bytes and the wasm route 404s (gates build it
/// first).
func readClientWasmArtifact() -> [UInt8] {
	let path = ".build/out/Products/Release-webassembly-wasm32/WebUIClient.wasm"
	let fd = open(path, O_RDONLY)
	guard fd >= 0 else { return [] }
	defer { close(fd) }
	var st = stat()
	guard fstat(fd, &st) == 0, st.st_size > 0 else { return [] }
	let size = Int(st.st_size)
	var bytes = [UInt8](repeating: 0, count: size)
	let n = bytes.withUnsafeMutableBytes { buf in
		read(fd, buf.baseAddress, size)
	}
	guard n == size else { return [] }
	return bytes
}

/// the content-addressed wasm url (immutable-cached) or the no-store alias
/// when the artifact is absent.
func clientWasmURL(_ hash: String) -> String {
	hash.isEmpty ? "/__assets/app.wasm" : "/__assets/app.\(hash).wasm"
}

/// the client-mode hydration probe page (clientMode contract emitted by the
/// framework — the smoke server only supplies the artifact url + script urls).
func makeClientDemoPage(wasmHash: String) -> String {
	let body = HydrationView().render()
	let boot = ClientBoot(
		wasmURL: clientWasmURL(wasmHash),
		mode: .hydrate,
		scriptURLs: ["/__assets/webui-client.js", "/__assets/client-demo-boot.js"]
	)
	return HTMLDocument(
		title: "WebUI Client Render — Hydration Probe",
		body: "<div id=\"app\" class=\"smoke\">\(body)</div>",
		clientMode: boot,
		includeRuntime: false
	).render()
}

/// the local-search vertical page. the wasm boots the search page (webui_init),
/// mounts it into `#search-app`, and dispatches delegated events entirely in
/// wasm — the websocket stays silent on the hot path.
func makeSearchDemoPage(wasmHash: String) -> String {
	let boot = ClientBoot(
		wasmURL: clientWasmURL(wasmHash),
		mode: .app,
		scriptURLs: ["/__assets/webui-client.js", "/__assets/search-demo-boot.js"]
	)
	return HTMLDocument(
		title: "WebUI Client Render — Local Search",
		body: "<div id=\"search-app\" class=\"search\"></div>",
		clientMode: boot,
		includeRuntime: false
	).render()
}

enum SmokeUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

extension SmokeApp {
	/// parse a positive-integer flag (`--name N`) with a fallback.
	static func intFlag(named name: String, default fallback: Int) -> Int {
		if let i = CommandLine.arguments.firstIndex(of: name),
		   i + 1 < CommandLine.arguments.count,
		   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
			return v
		}
		return fallback
	}

	static func main() async throws {
		let state = SmokeState()
		let router = EventRouter()
		let page = renderSmokePage(state: state, router: router)
		let connectionGate = ConnectionGate(maximum: intFlag(named: "--max-connections", default: 256))
		let clientWasm = readClientWasmArtifact()
		let wasmHash = WebUIBoot.wasmHash(of: clientWasm)
		let app = SmokeApp(
			state: state,
			router: router,
			pageHTML: page,
			connectionGate: connectionGate,
			clientWasm: clientWasm,
			clientWasmHash: wasmHash,
			clientDemoPage: makeClientDemoPage(wasmHash: wasmHash),
			searchDemoPage: makeSearchDemoPage(wasmHash: wasmHash)
		)
		let logger = Logger(label: "webui.smoketest")
		logger.info("full-stack smoke page rendered (\(page.utf8.count) bytes)")
		// prewarm the hoisted minified sheets so the one-time minify never
		// lands inside the first request handler.
		DesignSystemAssets.prewarm()

		let group = MultiThreadedEventLoopGroup(numberOfThreads: intFlag(named: "--event-loops", default: System.coreCount))
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<SmokeUpgradeResult>, Never> = try await bootstrap.bind(
			host: "127.0.0.1", port: 9123
		) { channel in
			channel.eventLoop.makeCompletedFuture { () -> EventLoopFuture<SmokeUpgradeResult> in
				// admission: every connection — request-bearing or a bare
				// connect — counts toward the cap (acquired before any
				// negotiation); at capacity the channel is closed up front.
				guard app.connectionGate.tryAcquire() else {
					channel.close(promise: nil)
					return channel.eventLoop.makeFailedFuture(ConnectionGateError.atCapacity)
				}
				// a single idle reaper guards every channel — plain http
				// (idle keep-alive, slow readers) and websockets alike.
				try channel.pipeline.syncOperations.addHandler(IdleStateHandler(readTimeout: .seconds(120)))
				try channel.pipeline.syncOperations.addHandler(IdleCloseHandler())
				// release the gate slot when this channel finally closes.
				try channel.pipeline.syncOperations.addHandler(ConnectionGateReleaser(gate: app.connectionGate))
				let upgrader = NIOTypedWebSocketServerUpgrader<SmokeUpgradeResult>(
					shouldUpgrade: { channel, head in
						let ok = head.method == .GET && head.uri == "/ws"
						return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
					},
					upgradePipelineHandler: { channel, _ in
						channel.eventLoop.makeCompletedFuture {
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
							return SmokeUpgradeResult.websocket(ws)
						}
					}
				)
				let config = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
							let http = try NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>(wrappingChannelSynchronously: channel)
							return SmokeUpgradeResult.http(http)
						}
					}
				)
				let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(upgradeConfiguration: config)
				let negotiation = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(configuration: pipelineConfig)
				return negotiation
			}
		}

		logger.info("full-stack smoke server on http://127.0.0.1:9123 (ws://127.0.0.1:9123/ws)")

		try await withThrowingDiscardingTaskGroup { group in
			try await channel.executeThenClose { inbound in
				for try await negotiationFuture in inbound {
					group.addTask {
						await app.handle(negotiationFuture)
					}
				}
			}
		}

		try await group.shutdownGracefully()
	}

	func handle(_ negotiationFuture: EventLoopFuture<SmokeUpgradeResult>) async {
		do {
			switch try await negotiationFuture.get() {
			case .websocket(let ws):
				try await handleWebsocket(ws)
			case .http(let http):
				try await handleHTTP(http)
			}
		} catch {
			// connection error or a refused admission (gate failure); ignore.
		}
	}

	private func handleWebsocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			try await withThrowingTaskGroup(of: Void.self) { tg in
				tg.addTask {
					for try await frame in inbound {
						switch frame.opcode {
						case .text:
							let payload = String(buffer: frame.unmaskedData)
							await self.dispatch(eventText: payload, outbound: outbound)
						case .ping:
							let buf = ByteBuffer()
							let pong = WebSocketFrame(fin: true, opcode: .pong, data: buf)
							try await outbound.write(pong)
						case .connectionClose:
							var data = frame.unmaskedData
							let code = data.readSlice(length: 2) ?? ByteBuffer()
							let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: code)
							try await outbound.write(close)
							return
						default:
							break
						}
					}
				}
				try await tg.next()
				tg.cancelAll()
			}
		}
	}

	private func dispatch(eventText payload: String, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async {
		do {
			let msg = try WSIncoming(jsonText: payload)
			switch msg {
			case .event(let component, let event, let data, _):
				if component == "redirect-test" {
					try await writeJSON(WSOutgoing.redirect(url: "/", replace: true), outbound: outbound)
					return
				}
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let updates = await self.router.handle(eventData)
				guard !updates.isEmpty else { return }
				let out = WSOutgoing.update(fragments: updates)
				try await writeJSON(out, outbound: outbound)
			case .ping(_):
				try await writeJSON(WSOutgoing.pong, outbound: outbound)
			case .navigate:
				break
			}
		} catch {
			let err = WSOutgoing.error(code: "decode", message: "bad event: \(error)")
			try? await writeJSON(err, outbound: outbound)
		}
	}

	private func writeJSON(_ msg: WSOutgoing, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		let bytes = msg.jsonBytes
		var buf = ByteBuffer()
		buf.writeBytes(bytes)
		let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
		try await outbound.write(frame)
	}

	private func handleHTTP(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			for try await part in inbound {
				guard case .head(let head) = part else { continue }
				guard head.method == .GET else {
					try await respond405(channel: channel.channel)
					return
				}
				if head.uri == "/__assets/app.wasm" {
					guard !self.clientWasm.isEmpty else {
						try await respond404(channel: channel.channel)
						return
					}
					// the fixed-name alias stays no-store (gates + probes fetch by
					// name and must never see a stale binary).
					try await respond(channel: channel.channel, bytes: self.clientWasm, contentType: "application/wasm")
					return
				}
				if !self.clientWasmHash.isEmpty, head.uri == "/__assets/app.\(self.clientWasmHash).wasm" {
					// the content-addressed timer: immutable cache for a year; the
					// hash changes with the binary, so this route can never go stale.
					try await respond(
						channel: channel.channel,
						bytes: self.clientWasm,
						contentType: "application/wasm",
						cacheControl: "public, max-age=31536000, immutable"
					)
					return
				}
				let (text, contentType): (String, String)
				switch head.uri {
				case "/__assets/css":
					text = DesignSystemAssets.minifiedCss; contentType = "text/css; charset=utf-8"
				case "/__assets/js":
					text = WebUIAssets.js; contentType = "text/javascript; charset=utf-8"
				case "/__assets/webui-client.js":
					text = WebUIAssets.client; contentType = "text/javascript; charset=utf-8"
				case "/__assets/client-demo-boot.js":
					text = WebUIAssets.clientBoot; contentType = "text/javascript; charset=utf-8"
				case "/__assets/search-demo-boot.js":
					text = WebUIAssets.clientSearchBoot; contentType = "text/javascript; charset=utf-8"
				case "/__assets/client-demo":
					text = self.clientDemoPage; contentType = "text/html; charset=utf-8"
				case "/__assets/search-demo":
					text = self.searchDemoPage; contentType = "text/html; charset=utf-8"
				case "/", "/index.html":
					text = self.pageHTML; contentType = "text/html; charset=utf-8"
				default:
					try await respond404(channel: channel.channel)
					return
				}
				try await respond(channel: channel.channel, body: text, contentType: contentType)
			}
		}
	}

	private func respond(channel: Channel, body: String, contentType: String) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .ok)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		// security headers — parity with the auth server.
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		var buf = ByteBuffer()
		buf.writeString(body)
		// await the terminal write promise: the async channel writer does not
		// await write promises, and a response larger than the socket send
		// buffer would otherwise lose its tail when the connection closes
		// right after writing (probe-verified truncation).
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}

	private func respond(channel: Channel, bytes: [UInt8], contentType: String, cacheControl: String = "no-store") async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .ok)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(bytes.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Cache-Control", value: cacheControl)
		var buf = ByteBuffer()
		buf.writeBytes(bytes)
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}

	private func respond404(channel: Channel) async throws {
		try await respond(channel: channel, body: "not found", contentType: "text/plain; charset=utf-8")
	}

	private func respond405(channel: Channel) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .methodNotAllowed)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}
}

// MARK: - Entry point

// hydration byte-identity mode: print the shared hydration view's SSR bytes
// and stop (the wasm client's --verify-render must produce the same bytes).
if CommandLine.arguments.contains("--print-hydration-ssr") {
	print(HydrationView().render())
} else {
	try await SmokeApp.main()
}
