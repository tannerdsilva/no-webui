import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Synchronization
import WebUI
import WebUIDesignSystem

// MARK: - Shared state

final class ExampleState: Sendable {
	private struct Values {
		var count = 0
		var echo = ""
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
}

// MARK: - Display-element renderers (stable ids, no event handlers)

func counterValueHTML(_ n: Int) -> String {
	"<div id=\"counter-value\" class=\"counter-value\" role=\"status\"><span>\(n)</span></div>"
}

func echoOutHTML(_ text: String) -> String {
	let safe = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
	return "<div id=\"echo-out\" class=\"echo-out\" role=\"status\"><span class=\"echo-out__text\">\(safe)</span></div>"
}

// MARK: - Page assembly (renders interactive views, registers handlers)

func renderExamplePage(state: ExampleState, router: EventRouter) -> String {
	let ctx = RenderContext(router: router)
	let body = ctx.withValueBody {
		Div(class: "app") {
			Header(class: "app__header") {
				Heading("WebUI Live Demo", level: .h1)
			}
			Main(class: "app__content") {
				WebUICard(variant: .elevated) {
					Heading("Counter", level: .h3)
					Raw(counterValueHTML(state.count))
					Div(class: "app__actions") {
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
							.onClick { _ in
								state.count = 0
								return [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))]
							}
					}
				}
				WebUICard(variant: .outlined) {
					Heading("Echo (input → server → DOM)", level: .h3)
					WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input")
						.onInput { event in
							state.echo = event.data["value"] ?? ""
							return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
						}
					Raw(echoOutHTML(state.echo))
				}
			}
			Footer(class: "app__footer") {
				Text("every click and keystroke round-trips over the WebSocket and repaints.")
			}
		}
	}
	return WebUIDocument(title: "WebUI Live Demo", body: body).render()
}

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

enum ExampleUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

@main
struct WebUIExample {
	let state: ExampleState
	let router: EventRouter
	let pageHTML: String

	static func main() async throws {
		let state = ExampleState()
		let router = EventRouter()
		let page = renderExamplePage(state: state, router: router)
		let app = WebUIExample(state: state, router: router, pageHTML: page)
		let logger = Logger(label: "webui.example")
		logger.info("example page rendered (\(page.utf8.count) bytes)")

		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<ExampleUpgradeResult>, Never> = try await bootstrap.bind(
			host: "0.0.0.0", port: 9090
		) { channel in
			channel.eventLoop.makeCompletedFuture {
				let upgrader = NIOTypedWebSocketServerUpgrader<ExampleUpgradeResult>(
					shouldUpgrade: { channel, head in
						let ok = head.method == .GET && head.uri == "/ws"
						return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
					},
					upgradePipelineHandler: { channel, _ in
						channel.eventLoop.makeCompletedFuture {
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
							return ExampleUpgradeResult.websocket(ws)
						}
					}
				)
				let config = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
							let http = try NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>(wrappingChannelSynchronously: channel)
							return ExampleUpgradeResult.http(http)
						}
					}
				)
				let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(upgradeConfiguration: config)
				let negotiation = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(configuration: pipelineConfig)
				return negotiation
			}
		}

		logger.info("live demo on http://localhost:9090 (ws://localhost:9090/ws)")

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

	func handle(_ negotiationFuture: EventLoopFuture<ExampleUpgradeResult>) async {
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
		do {
			let msg = try WSIncoming(jsonText: payload)
			switch msg {
			case .event(let component, let event, let data, _):
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
				let (text, contentType): (String, String)
				switch head.uri {
				case "/__assets/css":
					text = WebUIAssets.css; contentType = "text/css; charset=utf-8"
				case "/__assets/js":
					text = WebUIAssets.js; contentType = "text/javascript; charset=utf-8"
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
		var buf = ByteBuffer()
		buf.writeString(body)
		// await the terminal write promise: the async channel writer does not
		// await write promises, and a response larger than the socket send
		// buffer would otherwise lose its tail when the connection closes
		// right after writing (probe-verified truncation).
		_ = channel.write(NIOAny(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head)))
		_ = channel.write(NIOAny(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf)))
		try await channel.writeAndFlush(NIOAny(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil))).get()
	}

	private func respond404(channel: Channel) async throws {
		try await respond(channel: channel, body: "not found", contentType: "text/plain; charset=utf-8")
	}

	private func respond405(channel: Channel) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: .methodNotAllowed)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		_ = channel.write(NIOAny(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head)))
		try await channel.writeAndFlush(NIOAny(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil))).get()
	}
}
