import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Synchronization
import WebUI
import WebUIDesignSystem

// MARK: - cached assets

/// pre-encoded response bytes for the framework's own assets. they are fixed
/// for the life of the process, and the stylesheet is 320 KB — re-encoding it
/// per request would copy it twice for nothing.
private enum CachedAssets {
	static let css = ByteBuffer(string: DesignSystemAssets.minifiedCss)
	static let engine = ByteBuffer(string: WebUIAssets.engine)
	static let shell = ByteBuffer(string: WebUIAssets.shell)
	/// the build-time pre-compressed variants, served when the client accepts gzip.
	/// `nil` when the build host had no `gzip`, in which case the raw bytes serve.
	/// the runtime never compresses anything — see `WebUIAssetTool.gzipBase64`.
	static let cssGzip = WebUIAssets.cssGzip.map { ByteBuffer(bytes: $0) }
	static let engineGzip = WebUIAssets.engineGzip.map { ByteBuffer(bytes: $0) }
	static let shellGzip = WebUIAssets.shellGzip.map { ByteBuffer(bytes: $0) }
}

// MARK: - host assets

/// one asset a host serves alongside the framework's own.
///
/// `WebUIServer` already serves the design-system stylesheet, the engine, and
/// the shell. this is the seam for everything else an app ships — vendor
/// css/js, woff2 fonts, app scripts — so a host never keeps a second http
/// server just to answer asset paths.
///
/// the framework routes win: a host asset whose path collides with
/// `/__assets/css`, `/__assets/css.<sha>`, `/ui/webui-engine.js`, or
/// `/ui/webui-shell.js` is never reached.
public struct WebUIServerAsset: Sendable {
	/// the response body. `text` covers css/js/html; `bytes` covers binary
	/// payloads (fonts) that must not round-trip through `String`.
	public enum Body: Sendable {
		case text(String)
		case bytes([UInt8])
	}

	/// the exact request path, e.g. `/ui/vendor/katex/katex.min.css`. matched
	/// after the query string is stripped, so a cache-busting `?v=41` still
	/// resolves.
	public var path: String
	public var body: Body
	/// the `Content-Type` header value.
	public var contentType: String
	/// `Cache-Control: max-age=<seconds>`. `nil` emits `no-store`.
	public var cacheSeconds: Int?
	/// append `, immutable` to the cache policy. for a content-addressed response — a
	/// ``WebUIAsset`` registration, whose url carries the stamp of the bytes it serves —
	/// revalidation can never find anything new, so it is pure overhead. has no effect when
	/// ``cacheSeconds`` is `nil`: without a policy there is nothing to extend, and the
	/// response is `no-store`.
	public var immutable: Bool
	/// a **pre-compressed** variant of ``body`` (gzip bytes), served when the client's
	/// `Accept-Encoding` allows it; `nil` serves ``body`` to every client.
	///
	/// the compression happens at the host's build time, never in this server: the runtime
	/// links no compressor, so a host that wants the smaller transfer ships both forms —
	/// the same arrangement the framework's own sheet and engine use.
	public var gzip: [UInt8]?

	public init(
		path: String, body: Body, contentType: String,
		cacheSeconds: Int? = nil, immutable: Bool = false, gzip: [UInt8]? = nil
	) {
		self.path = path
		self.body = body
		self.contentType = contentType
		self.cacheSeconds = cacheSeconds
		self.immutable = immutable
		self.gzip = gzip
	}

	/// a utf-8 text asset (css, js, html).
	public static func text(
		_ path: String,
		_ text: String,
		contentType: String,
		cacheSeconds: Int? = nil,
		immutable: Bool = false,
		gzip: [UInt8]? = nil
	) -> WebUIServerAsset {
		WebUIServerAsset(
			path: path, body: .text(text), contentType: contentType,
			cacheSeconds: cacheSeconds, immutable: immutable, gzip: gzip
		)
	}

	/// a binary asset (fonts, images).
	public static func bytes(
		_ path: String,
		_ bytes: [UInt8],
		contentType: String,
		cacheSeconds: Int? = nil,
		immutable: Bool = false,
		gzip: [UInt8]? = nil
	) -> WebUIServerAsset {
		WebUIServerAsset(
			path: path, body: .bytes(bytes), contentType: contentType,
			cacheSeconds: cacheSeconds, immutable: immutable, gzip: gzip
		)
	}
}

// MARK: - shipped asset (runtime value)

/// one value that owns a shipped asset's bytes, address, variant and cache policy.
///
/// the pairing that used to be hand-maintained per asset — the url a document links and the
/// path the server registers — is derived from this single value instead: ``url`` is
/// ``registration``'s path plus the `?v=` stamp, and ``registration`` always registers the
/// *bare* path. the server matches host assets after stripping the query, so a registration
/// carrying its stamp would answer 404 for the whole asset (the failure mode is pinned as a
/// test, not a comment). immutable caching is part of the value rather than something a host
/// remembers to ask for, for the same reason: the url changes exactly when the bytes do.
///
/// a host builds one per served asset and hands `url` to the document and `registration` to
/// ``WebUIServerConfig/assets``.
public struct WebUIAsset: Sendable {
	/// the bare request path, e.g. `/ui/style.css`. the stamp rides the url, never this.
	public let path: String
	/// the payload, exactly as it ships.
	public let bytes: [UInt8]
	/// the pre-compressed variant, or `nil` when the build host had no `gzip`.
	public let gzip: [UInt8]?
	/// the `Content-Type` header value.
	public let contentType: String
	/// the address the url carries: the first 12 hex characters of the sha256 of ``bytes``,
	/// computed once at init — the same convention ``WebUIShippedAsset/stamp`` declares.
	public let stamp: String

	public init(path: String, bytes: [UInt8], gzip: [UInt8]? = nil, contentType: String) {
		self.path = path
		self.bytes = bytes
		self.gzip = gzip
		self.contentType = contentType
		self.stamp = String(SHA256.hex(bytes).prefix(12))
	}

	/// a utf-8 text asset.
	public init(path: String, text: String, gzip: [UInt8]? = nil, contentType: String) {
		self.init(path: path, bytes: Array(text.utf8), gzip: gzip, contentType: contentType)
	}

	/// what a document links: the bare path plus the `?v=<12 hex>` stamp.
	public var url: String { "\(path)?v=\(stamp)" }

	/// what the server registers: the bare path, a year-long immutable cache, the
	/// pre-compressed variant attached.
	public var registration: WebUIServerAsset {
		WebUIServerAsset(
			path: path, body: .bytes(bytes), contentType: contentType,
			cacheSeconds: 31536000, immutable: true, gzip: gzip
		)
	}
}

// MARK: - request

/// the request a page render answers: the path plus the decoded query, so a
/// host can render different content for `/index.html?s=<id>` (deep links)
/// without standing up a second server.
public struct WebUIServerRequest: Sendable {
	/// the request path, query string already stripped.
	public var path: String
	/// the decoded `?a=1&b=2` pairs. a repeated key keeps its first value.
	public var query: [String: String]

	public init(path: String, query: [String: String] = [:]) {
		self.path = path
		self.query = query
	}

	/// the percent-decoded value for `name`, or `nil`.
	public func value(_ name: String) -> String? {
		query[name]
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
	/// the host's rendered theme catalog (see ``ThemeSheet``), served at its
	/// content-addressed `url` with a year-long immutable cache. the same value's `url` is
	/// what a ``WebUIDocument`` links, so the page and the server agree by construction.
	public var themeSheet: ThemeSheet?
	/// extra assets this host serves (see ``WebUIServerAsset``). the framework
	/// routes and the page route are matched first, so an entry here can
	/// neither shadow nor disable them. duplicate paths: the last entry wins.
	public var assets: [WebUIServerAsset]

	public init(
		host: String = "0.0.0.0",
		port: Int = 9090,
		maxConnections: Int = 256,
		readIdleSeconds: Int64 = 120,
		assetCacheSeconds: Int = 3600,
		pagePath: String = "/",
		themeSheet: ThemeSheet? = nil,
		assets: [WebUIServerAsset] = []
	) {
		self.host = host
		self.port = port
		self.maxConnections = maxConnections
		self.readIdleSeconds = readIdleSeconds
		self.assetCacheSeconds = assetCacheSeconds
		self.pagePath = pagePath
		self.themeSheet = themeSheet
		self.assets = assets
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
	/// the request-aware render: receives the path and decoded query, so a page
	/// can vary by URL (deep links) as well as by router state.
	///
	/// async because a page that reflects live store state has to await it —
	/// a session store, a database, a filesystem scan. pre-rendering into a
	/// cache to satisfy a sync signature is how a page goes stale.
	public typealias RequestRender = @Sendable (WebUIServerRequest) async -> String

	private let config: WebUIServerConfig
	private let logger: Logger
	private var lifecycle: Lifecycle?

	/// render one fixed page and let the router carry all variation.
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
		self.render = { _ in render() }
	}

	/// render from the request: path-dependent pages and `?s=<id>` deep links.
	/// distinct label, so the two inits never compete in overload resolution.
	public init(
		requestRender: @escaping RequestRender,
		router: EventRouter,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.config = config
		self.logger = logger
		self.lifecycle = nil
		self.router = router
		self.render = requestRender
	}

	private let router: EventRouter
	private let render: RequestRender
	/// the connected pages a push reaches. created at init, so a broadcast
	/// issued before `start()` is a no-op rather than a crash.
	private let sinks = ConnectionSinks()

	/// bind and serve until `stop()` or process exit.
	public func start() async throws {
		DesignSystemAssets.prewarm()
		let cfg = config
		let runner = Runner(render: render, router: router, config: cfg, logger: logger, sinks: sinks)
		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
			// request/response traffic here is small and latency-shaped (a ws frame
			// is ~60 bytes), so nagle + delayed-ack can add tens of ms on a real
			// network. nio enables this for client channels but not for accepted
			// children, so set it explicitly.
			.childChannelOption(ChannelOptions.tcpOption(.tcp_nodelay), value: 1)

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

		self.lifecycle = Lifecycle(channel: channel)
		logger.info(
			"WebUIServer serving \(config.pagePath) on http://\(config.host):\(config.port) (ws://\(config.host):\(config.port)/ws)"
		)

		// the accept loop owns the loop group's lifetime: the connections
		// already accepted drain first, and only then does the group stop.
		// shutting the group down from `stop()` instead races a handler that
		// is still running — swift-nio answers that with "Cannot schedule
		// tasks on an EventLoop that has already shut down", and upgrades the
		// race to a forced crash in a later release.
		do {
			try await withThrowingDiscardingTaskGroup { group in
				try await channel.executeThenClose { inbound in
					for try await negotiationFuture in inbound {
						group.addTask {
							await runner.handle(negotiationFuture)
						}
					}
				}
			}
			try await group.shutdownGracefully()
		} catch {
			try? await group.shutdownGracefully()
			throw error
		}
	}

	/// close the listener. the accept loop drains the connections already
	/// accepted and shuts the event loop group down itself, so a handler never
	/// schedules work on a loop that has already stopped.
	public func stop() async {
		guard let lifecycle else { return }
		self.lifecycle = nil
		try? await lifecycle.channel.channel.close().get()
	}

	// MARK: - server-initiated push

	/// push fragments to every connected page, with no inbound event to answer.
	///
	/// the engine applies an update by element id, so a page that does not
	/// render the id ignores it and one push reaches every page that does.
	/// this is how a host streams a turn, reports background progress, or
	/// refreshes a panel that changed on disk.
	public func broadcast(_ updates: [FragmentUpdate]) async {
		guard !updates.isEmpty else { return }
		await sinks.broadcast(WSOutgoing.update(fragments: updates).jsonBytes)
	}

	/// how many pages are connected right now (diagnostics and tests).
	public var connectedPages: Int {
		sinks.count
	}

	// MARK: - lifecycle state

	struct Lifecycle: Sendable {
		let channel: NIOAsyncChannel<EventLoopFuture<ServerUpgradeResult>, Never>
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

// MARK: - connected pages

/// the live websocket outbound writers, keyed by connection id — the targets a
/// server-initiated push writes to. the accept side registers on upgrade and
/// removes on close; `Mutex`-backed and `Sendable`, matching the gate.
///
/// a socket whose `render` token the server rejects is already closed, so a
/// push can never reach a stale page from a former session: the render-binding
/// invariant is enforced when the connection is admitted, not per message.
final class ConnectionSinks: Sendable {
	private let state = Mutex<[Int: NIOAsyncChannelOutboundWriter<WebSocketFrame>]>([:])
	private let counter = Mutex<Int>(0)

	/// register a connection and return its id.
	func register(_ outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) -> Int {
		let id = counter.withLock { value -> Int in
			value += 1
			return value
		}
		state.withLock { $0[id] = outbound }
		return id
	}

	func unregister(_ id: Int) {
		_ = state.withLock { $0.removeValue(forKey: id) }
	}

	/// how many pages are connected right now.
	var count: Int {
		state.withLock { $0.count }
	}

	/// push `bytes` to every connected page. a connection that fails to write
	/// is dropped here rather than in its own read loop.
	///
	/// the snapshot is taken under the lock and written outside it: awaiting
	/// while holding a `Mutex` would deadlock. a page that accepts between the
	/// snapshot and the writes simply misses this push — it will be rendered
	/// from current state on its own first request.
	func broadcast(_ bytes: [UInt8]) async {
		let targets = state.withLock { Array($0) }
		guard !targets.isEmpty else { return }
		for (id, outbound) in targets {
			var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
			buffer.writeBytes(bytes)
			let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
			do {
				try await outbound.write(frame)
			} catch {
				_ = state.withLock { $0.removeValue(forKey: id) }
			}
		}
	}
}

// MARK: - request runner

/// the connection-bound logic. `Sendable`: all state is immutable after init
/// (the gate is the only mutable piece and is Mutex-backed).
final class Runner: Sendable {
	private let render: WebUIServer.RequestRender
	private let router: EventRouter
	private let config: WebUIServerConfig
	private let logger: Logger
	let gate: ConnectionGate
	/// the push targets this connection joins for its lifetime.
	let sinks: ConnectionSinks

	/// host assets, pre-encoded: path → body + content type + cache policy.
	/// fixed for the life of the process, so each body is built exactly once
	/// instead of per request.
	private let assets: [String: HostAsset]

	/// the host's theme catalog, pre-encoded once like the framework assets. `nil` when the
	/// host has no catalog, in which case the route simply does not exist.
	private let themeSheet: ByteBuffer?
	private let themeSheetPath: String?

	struct HostAsset: Sendable {
		let body: ByteBuffer
		/// the host's pre-compressed variant, when it shipped one.
		let gzip: ByteBuffer?
		let contentType: String
		let cacheControl: String
	}

	init(
		render: @escaping WebUIServer.RequestRender,
		router: EventRouter,
		config: WebUIServerConfig,
		logger: Logger,
		sinks: ConnectionSinks
	) {
		self.render = render
		self.router = router
		self.config = config
		self.logger = logger
		self.gate = ConnectionGate(maximum: config.maxConnections)
		self.sinks = sinks
		var encoded: [String: HostAsset] = [:]
		encoded.reserveCapacity(config.assets.count)
		for asset in config.assets {
			let bytes: [UInt8]
			switch asset.body {
			case .text(let text): bytes = Array(text.utf8)
			case .bytes(let raw): bytes = raw
			}
			// `immutable` extends a policy; without a max-age there is none to extend.
			let cacheControl = asset.cacheSeconds.map {
				"public, max-age=\($0)" + (asset.immutable ? ", immutable" : "")
			} ?? "no-store"
			encoded[asset.path] = HostAsset(
				body: ByteBuffer(bytes: bytes),
				gzip: asset.gzip.map { ByteBuffer(bytes: $0) },
				contentType: asset.contentType,
				cacheControl: cacheControl
			)
		}
		self.assets = encoded
		if let sheet = config.themeSheet, !sheet.isEmpty {
			self.themeSheet = ByteBuffer(bytes: Array(sheet.css.utf8))
			self.themeSheetPath = sheet.url
		} else {
			self.themeSheet = nil
			self.themeSheetPath = nil
		}
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
			// a connected page is a push target for the life of the socket.
			let connectionID = sinks.register(outbound)
			defer { sinks.unregister(connectionID) }
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
				// read once; every asset response below negotiates against it
				let acceptEncoding = head.headers.first(name: "Accept-Encoding")
				// strip the query once: routing and the host-asset table both
				// key on the bare path, so a cache-busting `?v=41` still
				// resolves, and the bare page path accepts `?s=<id>`.
				let path = String(uri.prefix(while: { $0 != "?" }))
				let queryText = uri.dropFirst(path.count).dropFirst()
				let request = WebUIServerRequest(path: path, query: parseQuery(String(queryText)))
				if path == "/__assets/css" {
					// legacy stable path (old pages / old cache) — short cache.
					try await respond(
						channel: channel.channel,
						bytes: CachedAssets.css,
						gzip: CachedAssets.cssGzip,
						acceptEncoding: acceptEncoding,
						contentType: "text/css; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)"
					)
				} else if path.hasPrefix("/__assets/css.") {
					// content-addressed sheet: a rebuilt sheet is a new url, so
					// the response is immutable — a year-long, revalidation-free
					// cache with no stale-sheet window.
					try await respond(
						channel: channel.channel,
						bytes: CachedAssets.css,
						gzip: CachedAssets.cssGzip,
						acceptEncoding: acceptEncoding,
						contentType: "text/css; charset=utf-8",
						cacheControl: "public, max-age=31536000, immutable"
					)
				} else if let sheet = themeSheet, path == themeSheetPath {
					// the host's theme catalog. content-addressed, so immutable: a rebuilt
					// sheet is a different url and no cache invalidation is ever needed.
					try await respond(
						channel: channel.channel,
						bytes: sheet,
						contentType: "text/css; charset=utf-8",
						cacheControl: "public, max-age=31536000, immutable"
					)
				} else if path == "/ui/webui-engine.js" {
					try await respond(
						channel: channel.channel,
						bytes: CachedAssets.engine,
						gzip: CachedAssets.engineGzip,
						acceptEncoding: acceptEncoding,
						contentType: "text/javascript; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)"
					)
				} else if path == "/ui/webui-shell.js" {
					try await respond(
						channel: channel.channel,
						bytes: CachedAssets.shell,
						gzip: CachedAssets.shellGzip,
						acceptEncoding: acceptEncoding,
						contentType: "text/javascript; charset=utf-8",
						cacheControl: "public, max-age=\(config.assetCacheSeconds)"
					)
				} else if let asset = assets[path] {
					// host asset: vendor css/js, fonts, app scripts. the
					// framework routes above win, so a host asset can never
					// shadow the stylesheet, the engine, or the shell. a host
					// that shipped a pre-compressed variant gets the same
					// negotiation the framework's own assets use.
					try await respond(
						channel: channel.channel,
						bytes: asset.body,
						gzip: asset.gzip,
						acceptEncoding: acceptEncoding,
						contentType: asset.contentType,
						cacheControl: asset.cacheControl
					)
				} else if path == config.pagePath || path == "/index.html" {
					// the server owns the render context: handlers a page wires
					// through `.onX`/`controlAttributes` register into THIS
					// server's router, so hosts never juggle a second router
					// (the classic page-local vs server-router mismatch). a page
					// that wraps its own context still wins (the inner
					// `withValue` takes precedence), so existing hosts are
					// unaffected.
					let body = await RenderContext.$current.withValue(RenderContext(router: router)) {
						await render(request)
					}
					try await respond(
						channel: channel.channel,
						body: body,
						contentType: "text/html; charset=utf-8"
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
		cacheControl: String = "no-store"
	) async throws {
		// one copy: the utf-8 view goes straight into the channel's buffer.
		var buf = channel.allocator.buffer(capacity: body.utf8.count)
		buf.writeString(body)
		try await respond(
			channel: channel,
			bytes: buf,
			contentType: contentType,
			status: status,
			cacheControl: cacheControl
		)
	}

	/// the byte-level responder — cached assets skip the string path entirely.
	/// http/1.1 keep-alive is the default here (no `Connection: close`): the
	/// read-idle handler still reaps an abandoned connection after
	/// `readIdleSeconds`, and the admission gate still bounds the total.
	private func respond(
		channel: Channel,
		bytes: ByteBuffer,
		gzip: ByteBuffer? = nil,
		acceptEncoding: String? = nil,
		contentType: String,
		status: HTTPResponseStatus = .ok,
		cacheControl: String = "no-store"
	) async throws {
		// negotiate once. a client that accepts gzip gets the pre-compressed body, and
		// `Vary` goes out whenever a variant EXISTS — not only when it was chosen — or a
		// shared cache would hand the compressed body to the next client that did not ask.
		let useGzip = gzip != nil && (acceptEncoding?.contains("gzip") ?? false)
		let body = useGzip ? gzip! : bytes
		var head = HTTPResponseHead(version: .http1_1, status: status)
		head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.readableBytes)")
		if gzip != nil { head.headers.replaceOrAdd(name: "Vary", value: "Accept-Encoding") }
		if useGzip { head.headers.replaceOrAdd(name: "Content-Encoding", value: "gzip") }
		// security headers — parity with the reference servers.
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Service-Worker-Allowed", value: "/")
		head.headers.replaceOrAdd(name: "Cache-Control", value: cacheControl)
		// await the terminal write promise: the async channel writer does not
		// await write promises, and a response larger than the socket send
		// buffer would otherwise lose its tail when the connection closes
		// right after writing (probe-verified truncation).
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(body))
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
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}
}

// MARK: - query parsing

/// parse an `a=1&b=2` query string into decoded pairs. `+` decodes to a space
/// (form encoding) and `%XX` to its byte; a malformed escape stays verbatim
/// rather than being dropped, so a bad parameter cannot silently vanish. the
/// first value wins for a repeated key.
func parseQuery(_ text: String) -> [String: String] {
	guard !text.isEmpty else { return [:] }
	var out: [String: String] = [:]
	for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
		let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
		let name = percentDecode(parts[0])
		guard !name.isEmpty, out[name] == nil else { continue }
		out[name] = parts.count == 2 ? percentDecode(parts[1]) : ""
	}
	return out
}

/// percent-decode one url component. invalid escapes pass through unchanged.
private func percentDecode(_ text: Substring) -> String {
	guard text.contains("%") || text.contains("+") else { return String(text) }
	let input = Array(text.utf8)
	var bytes: [UInt8] = []
	bytes.reserveCapacity(input.count)
	var i = 0
	while i < input.count {
		let byte = input[i]
		if byte == 0x2B {                                    // '+'
			bytes.append(0x20)
			i += 1
		} else if byte == 0x25, i + 2 < input.count,         // '%XX'
			let hi = hexValue(input[i + 1]), let lo = hexValue(input[i + 2]) {
			bytes.append(hi << 4 | lo)
			i += 3
		} else {
			bytes.append(byte)
			i += 1
		}
	}
	return String(decoding: bytes, as: UTF8.self)
}

private func hexValue(_ byte: UInt8) -> UInt8? {
	switch byte {
	case 0x30...0x39: return byte - 0x30                 // 0-9
	case 0x41...0x46: return byte - 0x41 + 10            // A-F
	case 0x61...0x66: return byte - 0x61 + 10            // a-f
	default: return nil
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
