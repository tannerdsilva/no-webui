import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUICompression
import WebUIDesignSystem

// MARK: - gzip

/// rfc-1952 gzip encoding through the `WebUICompression` C shim. returns nil
/// on a framework error or empty input; small payloads pass through
/// uncompressed by the caller.
enum GzipEncoder {
	static func encode(_ input: [UInt8]) -> [UInt8]? {
		var outLen = 0
		guard let ptr = input.withUnsafeBufferPointer({ src in
			webui_gzip_compress(src.baseAddress, src.count, &outLen)
		}) else {
			return nil
		}
		defer { webui_gzip_free(ptr) }
		return Array(UnsafeBufferPointer(start: ptr, count: outLen))
	}
}

// MARK: - Configuration

/// tuning for `WebUIServer`. defaults match the reference servers: bind any
/// interface, 256-connection admission cap, 120 s read idle, one-hour asset
/// cache.
public struct WebUIServerConfig: Sendable {
	public var host: String
	public var port: Int
	public var maxConnections: Int
	public var readIdleSeconds: Int64
	public var assetCacheSeconds: Int
	public var pagePath: String

	public init(
		host: String = "0.0.0.0",
		port: Int = 9090,
		maxConnections: Int = 256,
		readIdleSeconds: Int64 = 120,
		assetCacheSeconds: Int = 3600,
		pagePath: String = "/"
	) {
		self.host = host
		self.port = port
		self.maxConnections = maxConnections
		self.readIdleSeconds = readIdleSeconds
		self.assetCacheSeconds = assetCacheSeconds
		self.pagePath = pagePath
	}
}

// MARK: - WebUIServer

/// one-call serving of a no-webui page: http page route, the framework asset
/// routes (engine, shell, client boot, css, wasm artifact) with cache
/// headers, `/ws` upgrade, `EventRouter` dispatch, ping/pong, read-idle
/// reaping, and an admission cap. replaces the per-executable NIO boilerplate
/// every reference host used to copy.
///
/// the `render` closure is called per request (fresh CSP nonce each time, the
/// documented best practice) and may inject a `RuntimeConfig` render token;
/// `router` is the same router the render registered into — re-rendering
/// replaces handler registrations idempotently (register is a dictionary
/// assignment), so a page can re-render with a stable router.
public actor WebUIServer {
	public typealias Render = @Sendable () -> String

	private let config: WebUIServerConfig
	private let logger: Logger
	private var lifecycle: Lifecycle?

	public init(
		render: @escaping Render,
		router: EventRouter,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.config = config
		self.logger = logger
		self.lifecycle = nil
		self.router = router
		self.render = render
	}

	private let router: EventRouter
	private let render: Render

	/// bind and serve until `stop()` or process exit.
	public func start() async throws {
		DesignSystemAssets.prewarm()
		let cfg = config
		let runner = Runner(render: render, router: router, config: cfg, logger: logger)
		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<ServerUpgradeResult>, Never> = try await bootstrap.bind(
			host: cfg.host,
			port: cfg.port
		) { channel in
			channel.eventLoop.makeCompletedFuture {
				// admission: bare connects count; at capacity close up front.
				guard runner.gate.tryAcquire() else {
					channel.close(promise: nil)
					return channel.eventLoop.makeFailedFuture(ServerGateError.atCapacity)
				}
				try channel.pipeline.syncOperations.addHandler(
					IdleStateHandler(readTimeout: .seconds(cfg.readIdleSeconds))
				)
				try channel.pipeline.syncOperations.addHandler(ServerIdleCloseHandler())
				try channel.pipeline.syncOperations.addHandler(ServerGateReleaser(gate: runner.gate))

				let upgrader = NIOTypedWebSocketServerUpgrader<ServerUpgradeResult>(
					shouldUpgrade: { channel, head in
						let ok = head.method == .GET && head.uri == "/ws"
						return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
					},
					upgradePipelineHandler: { channel, _ in
						channel.eventLoop.makeCompletedFuture {
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(
								wrappingChannelSynchronously: channel
							)
							return ServerUpgradeResult.websocket(ws)
						}
					}
				)
				let upgradeConfig = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							try channel.pipeline.syncOperations.addHandler(ServerHTTPResponsePartHandler())
							let http = try NIOAsyncChannel<
								HTTPServerRequestPart,
								HTTPPart<HTTPResponseHead, ByteBuffer>
							>(wrappingChannelSynchronously: channel)
							return ServerUpgradeResult.http(http)
						}
					}
				)
				let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(
					upgradeConfiguration: upgradeConfig
				)
				return try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(
					configuration: pipelineConfig
				)
			}
		}

		self.lifecycle = Lifecycle(channel: channel, group: group)
		logger.info(
			"WebUIServer serving \(config.pagePath) on http://\(config.host):\(config.port) (ws://\(config.host):\(config.port)/ws)"
		)

		try await withThrowingDiscardingTaskGroup { group in
			try await channel.executeThenClose { inbound in
				for try await negotiationFuture in inbound {
					group.addTask {
						await runner.handle(negotiationFuture)
					}
				}
			}
		}
	}

	/// close the listener and shut the event loop group down.
	public func stop() async {
		guard let lifecycle else { return }
		self.lifecycle = nil
		// the listener is closed first so no new connections arrive.
		try? await lifecycle.channel.channel.close().get()
		try? await lifecycle.group.shutdownGracefully()
	}

	// MARK: - lifecycle state

	struct Lifecycle: Sendable {
		let channel: NIOAsyncChannel<EventLoopFuture<ServerUpgradeResult>, Never>
		let group: MultiThreadedEventLoopGroup
	}
}

// MARK: - upgrade result

enum ServerUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

enum ServerGateError: Error {
	case atCapacity
}

// MARK: - request runner

/// the connection-bound logic. `Sendable`: all state is immutable after init
/// (the gate is the only mutable piece and is Mutex-backed).
final class Runner: Sendable {
	private let render: WebUIServer.Render
	private let router: EventRouter
	private let config: WebUIServerConfig
	private let logger: Logger
	let gate: ConnectionGate

	init(
		render: @escaping WebUIServer.Render,
		router: EventRouter,
		config: WebUIServerConfig,
		logger: Logger
	) {
		self.render = render
		self.router = router
		self.config = config
		self.logger = logger
		self.gate = ConnectionGate(maximum: config.maxConnections)
	}

	func handle(_ negotiationFuture: EventLoopFuture<ServerUpgradeResult>) async {
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

	// MARK: websocket

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
				try await writeJSON(WSOutgoing.update(fragments: updates), outbound: outbound)
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
		let bytes = msg.jsonBytes
		var buf = ByteBuffer()
		buf.writeBytes(bytes)
		let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
		try await outbound.write(frame)
	}

	// MARK: http

	private func handleHTTP(
		_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>
	) async throws {
		try await channel.executeThenClose { inbound, outbound in
			for try await part in inbound {
				guard case .head(let head) = part else { continue }
				guard head.method == .GET else {
					try await respond405(channel: channel.channel)
					return
				}
				let uri = head.uri
				let canGzip = head.headers["accept-encoding"].contains { $0.lowercased().contains("gzip") }
				if uri == "/__assets/css" {
					// legacy stable path (old pages / old cache) — short cache.
					try await respond(
						channel: channel.channel,
						body: DesignSystemAssets.minifiedCss,
						contentType: "text/css; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)",
						gzip: canGzip
					)
				} else if uri.hasPrefix("/__assets/css.") {
					// content-addressed sheet: a rebuilt sheet is a new url, so
					// the response is immutable — a year-long, revalidation-free
					// cache with no stale-sheet window.
					try await respond(
						channel: channel.channel,
						body: DesignSystemAssets.minifiedCss,
						contentType: "text/css; charset=utf-8",
						cacheControl: "public, max-age=31536000, immutable",
						gzip: canGzip
					)
				} else if uri == "/ui/webui-engine.js" {
					try await respond(
						channel: channel.channel,
						body: WebUIAssets.engine,
						contentType: "text/javascript; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)",
						gzip: canGzip
					)
				} else if uri == "/ui/webui-shell.js" {
					try await respond(
						channel: channel.channel,
						body: WebUIAssets.shell,
						contentType: "text/javascript; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)",
						gzip: canGzip
					)
				} else if uri == "/ui/webui-client.js" {
					try await respond(
						channel: channel.channel,
						body: WebUIAssets.client,
						contentType: "text/javascript; charset=utf-8",
						gzip: canGzip
					)
				} else if uri == "/ui/webui-app-boot.js" {
					try await respond(
						channel: channel.channel,
						body: WebUIAssets.clientBoot,
						contentType: "text/javascript; charset=utf-8",
						gzip: canGzip
					)
				} else if uri == config.pagePath || uri == "/index.html" {
					// the server owns the render context: handlers a page wires
					// through `.onX`/`controlAttributes` register into THIS
					// server's router, so hosts never juggle a second router
					// (the classic page-local vs server-router mismatch). a page
					// that wraps its own context still wins (the inner
					// `withValue` takes precedence), so existing hosts are
					// unaffected.
					let body = RenderContext.$current.withValue(RenderContext(router: router)) {
						render()
					}
					try await respond(
						channel: channel.channel,
						body: body,
						contentType: "text/html; charset=utf-8",
						gzip: canGzip
					)
				} else {
					try await respond404(channel: channel.channel)
					return
				}
			}
		}
	}

	private func respond(
		channel: Channel,
		body: String,
		contentType: String,
		status: HTTPResponseStatus = .ok,
		cacheControl: String = "no-store",
		gzip: Bool = false
	) async throws {
		var payload = Array(body.utf8)
		var head = HTTPResponseHead(version: .http1_1, status: status)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(payload.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		// security headers — parity with the reference servers.
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Service-Worker-Allowed", value: "/")
		head.headers.replaceOrAdd(name: "Cache-Control", value: cacheControl)
		var buf = ByteBuffer()
		buf.writeBytes(payload)
		// await the terminal write promise: the async channel writer does not
		// await write promises, and a response larger than the socket send
		// buffer would otherwise lose its tail when the connection closes
		// right after writing (probe-verified truncation).
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buf))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}


	private func respond404(channel: Channel) async throws {
		try await respond(
			channel: channel,
			body: "not found",
			contentType: "text/plain; charset=utf-8",
			status: .notFound
		)
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

// MARK: - pipeline helpers

/// close the channel when the read-idle window elapses (guards plain http
/// keep-alive, slow readers, and websockets alike).
final class ServerIdleCloseHandler: ChannelInboundHandler {
	typealias InboundIn = IOData
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is IdleStateHandler.IdleStateEvent {
			context.close(promise: nil)
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

/// release a `ConnectionGate` slot when the channel closes.
final class ServerGateReleaser: ChannelInboundHandler {
	typealias InboundIn = IOData
	private let gate: ConnectionGate
	init(gate: ConnectionGate) { self.gate = gate }
	func channelInactive(context: ChannelHandlerContext) {
		gate.release()
		context.fireChannelInactive()
	}
}

final class ServerHTTPResponsePartHandler: ChannelOutboundHandler {
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
