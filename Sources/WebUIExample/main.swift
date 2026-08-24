import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUIDesignSystem

// MARK: - Shared state

final class ExampleState: @unchecked Sendable {
	private let lock = NSLock()
	private var _count: Int = 0
	private var _echo: String = ""

	var count: Int {
		get { lock.lock(); defer { lock.unlock() }; return _count }
		set { lock.lock(); defer { lock.unlock() }; _count = newValue }
	}
	var echo: String {
		get { lock.lock(); defer { lock.unlock() }; return _echo }
		set { lock.lock(); defer { lock.unlock() }; _echo = newValue }
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
		guard let data = payload.data(using: .utf8) else { return }
		do {
			let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
			switch msg {
			case .event(let component, let event, let data):
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
