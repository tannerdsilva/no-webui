import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUIDesignSystem

// MARK: - Shared state

final class SmokeState: @unchecked Sendable {
	private let lock = NSLock()
	private var _count: Int = 0
	private var _progress: Double = 0.25
	private var _echo: String = ""
	// interactive table demo (server is the source of truth)
	private var _tableSortColumn: Int = 0
	private var _tableSortAsc: Bool = true
	private var _tableSelected: Set<String> = []
	private var _tableExpanded: Set<String> = []

	var count: Int {
		get { lock.lock(); defer { lock.unlock() }; return _count }
		set { lock.lock(); defer { lock.unlock() }; _count = newValue }
	}
	var progress: Double {
		get { lock.lock(); defer { lock.unlock() }; return _progress }
		set { lock.lock(); defer { lock.unlock() }; _progress = newValue }
	}
	var echo: String {
		get { lock.lock(); defer { lock.unlock() }; return _echo }
		set { lock.lock(); defer { lock.unlock() }; _echo = newValue }
	}
	var tableSortColumn: Int {
		get { lock.lock(); defer { lock.unlock() }; return _tableSortColumn }
		set { lock.lock(); defer { lock.unlock() }; _tableSortColumn = newValue }
	}
	var tableSortAsc: Bool {
		get { lock.lock(); defer { lock.unlock() }; return _tableSortAsc }
		set { lock.lock(); defer { lock.unlock() }; _tableSortAsc = newValue }
	}
	var tableSelected: Set<String> {
		get { lock.lock(); defer { lock.unlock() }; return _tableSelected }
		set { lock.lock(); defer { lock.unlock() }; _tableSelected = newValue }
	}
	var tableExpanded: Set<String> {
		get { lock.lock(); defer { lock.unlock() }; return _tableExpanded }
		set { lock.lock(); defer { lock.unlock() }; _tableExpanded = newValue }
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
	).render()
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
							state.echo = event.data["value"] ?? ""
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
					.onClick(id: "interactive-table") { event in
						let target = event.data["targetId"] ?? ""
						let prefix = "interactive-table-"
						guard target.hasPrefix(prefix) else { return [] }
						let suffix = String(target.dropFirst(prefix.count))
						// mutate the server state (source of truth) FIRST, then
						// render the patch once from the new state — rendering
						// before the mutation would emit a frame one state stale.
						if suffix == "select-all" {
							if state.tableSelected.count == smokeTableRecords.count { state.tableSelected = [] }
							else { state.tableSelected = Set(smokeTableRecords.map { $0.id }) }
						} else if suffix.hasPrefix("select-") {
							let rowId = String(suffix.dropFirst(7))
							if state.tableSelected.contains(rowId) { state.tableSelected.remove(rowId) }
							else { state.tableSelected.insert(rowId) }
						} else if suffix.hasPrefix("sort-") {
							let col = Int(suffix.dropFirst(5)) ?? 0
							if state.tableSortColumn == col { state.tableSortAsc.toggle() }
							else { state.tableSortColumn = col; state.tableSortAsc = true }
						} else if suffix.hasPrefix("expand-") {
							let rowId = String(suffix.dropFirst(7))
							if state.tableExpanded.contains(rowId) { state.tableExpanded.remove(rowId) }
							else { state.tableExpanded.insert(rowId) }
						} else {
							return []
						}
						return [FragmentUpdate(id: "interactive-table", html: interactiveTableHTML(state: state))]
					}
				}
				}
				}
				}
	return WebUIDocument(title: "Design System Full-Stack Smoke Test", body: body).render()
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

struct SmokeApp {
	let state: SmokeState
	let router: EventRouter
	let pageHTML: String
}

enum SmokeUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

extension SmokeApp {
	static func main() async throws {
		let state = SmokeState()
		let router = EventRouter()
		let page = renderSmokePage(state: state, router: router)
		let app = SmokeApp(state: state, router: router, pageHTML: page)
		let logger = Logger(label: "webui.smoketest")
		logger.info("full-stack smoke page rendered (\(page.utf8.count) bytes)")

		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<SmokeUpgradeResult>, Never> = try await bootstrap.bind(
			host: "127.0.0.1", port: 9123
		) { channel in
			channel.eventLoop.makeCompletedFuture {
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
			// connection error; ignore
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
		guard let data = payload.data(using: .utf8) else { return }
		do {
			let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
			switch msg {
			case .event(let component, let event, let data):
				if component == "redirect-test" {
					try await writeJSON(WSOutgoing.redirect(url: "/", replace: true), outbound: outbound)
					return
				}
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let updates = await self.router.handle(eventData)
				guard !updates.isEmpty else { return }
				let out = WSOutgoing.update(fragments: updates)
				try await writeJSON(out, outbound: outbound)
			case .ping:
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
		let data = try JSONEncoder().encode(msg)
		var buf = ByteBuffer()
		buf.writeBytes(data)
		let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
		try await outbound.write(frame)
	}

	private func handleHTTP(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			for try await part in inbound {
				guard case .head(let head) = part else { continue }
				guard head.method == .GET else {
					try await respond405(outbound: outbound)
					return
				}
				let (text, contentType): (String, String)
				switch head.uri {
				case "/__assets/css":
					text = WebUIAssets.css; contentType = "text/css; charset=utf-8"
				case "/__assets/js":
					text = WebUIAssets.js; contentType = "text/javascript; charset=utf-8"
				case "/", "/index.html":
					text = self.pageHTML; contentType = "text/html; charset=utf-8"
				default:
					try await respond404(outbound: outbound)
					return
				}
				try await respond(outbound: outbound, body: text, contentType: contentType)
			}
		}
	}

	private func respond(outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>, body: String, contentType: String) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .ok)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		var buf = ByteBuffer()
		buf.writeString(body)
		try await outbound.write(contentsOf: [.head(head), .body(buf), .end(nil)])
	}

	private func respond404(outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .notFound)
		head.headers.replaceOrAdd(name: "Content-Length", value: "9")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		var buf = ByteBuffer()
		buf.writeString("not found")
		try await outbound.write(contentsOf: [.head(head), .body(buf), .end(nil)])
	}

	private func respond405(outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .methodNotAllowed)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		try await outbound.write(contentsOf: [.head(head), .end(nil)])
	}
}

// MARK: - Entry point

try await SmokeApp.main()
