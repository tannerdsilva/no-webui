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

public extension WebUIAsset {
	/// the runtime value for a build-produced conformance — the shape generated code hands
	/// the server: the conformance's bytes, variant and content type, served at `path`.
	///
	/// the stamp is recomputed from ``WebUIShippedAsset/body``, not copied from the
	/// conformance's declared ``WebUIShippedAsset/stamp``. the two agree for every
	/// in-contract conformance — ``WebUIBuild`` pins the literal against the bytes it emits —
	/// and recomputing means a payload edited without its literal cannot keep an old url
	/// alive in a year-long cache.
	init(_ shipped: any WebUIShippedAsset.Type, path: String) {
		self.init(
			path: path, bytes: shipped.body, gzip: shipped.gzip, contentType: shipped.contentType
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
	/// the token minted for THIS render.
	///
	/// a page echoes it into `RuntimeConfig.renderToken` so the socket's frames
	/// can be bound back to this render's session. empty when the entropy source
	/// failed, in which case the page's events are refused under
	/// `WebUIServerConfig.requireRenderToken`.
	public var renderToken: RenderToken

	public init(
		path: String,
		query: [String: String] = [:],
		renderToken: RenderToken = RenderToken("")
	) {
		self.path = path
		self.query = query
		self.renderToken = renderToken
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

	/// when true, a websocket `event`/`ping` whose render token is absent or
	/// unknown is answered with a `token` error frame and the socket is closed
	/// (AGENTS.md security invariant 11).
	///
	/// defaults to false so a 1.x host that never threaded a token keeps working
	/// unchanged; it flips to true at the 2.0 cut. a host that threads the token
	/// today — pass `WebUIServerRequest.renderToken.value` into the document's
	/// `renderToken:` — can turn it on now.
	public var requireRenderToken: Bool

	/// what the server does when a handler throws.
	///
	/// defaults to ``HandlerFailurePolicy/notifyClient``: the page is told and,
	/// when the component registered a fallback, given something to render in the
	/// broken control's place. a silent failure is what made C3 invisible.
	public var handlerFailurePolicy: HandlerFailurePolicy
	/// what a failed page render answers over http: the host's error page for
	/// the thrown error. `nil` answers a plain-text 500 naming the failure.
	///
	/// a render throw used to surface as a dead page — the error propagated up
	/// and the connection was dropped. with this set, the request is answered
	/// with a 500 carrying `onRenderFailure(error)`, so the failure is visible
	/// and the connection survives. a swift trap is not an error and never
	/// reaches this closure (see `STABILITY.md`).
	public var onRenderFailure: (@Sendable (any Error) -> String)?

	/// the hard cap on one request body, in bytes. a declared `Content-Length`
	/// over the cap is refused before a single body byte is buffered, and a
	/// body that grows past it mid-stream is cut off — an upload endpoint
	/// without a cap is a DoS (plan w3.3). default 1 MiB.
	public var maxBodyBytes: Int
	/// the hard cap on one multipart body's parts. exceeding it is a 422 that
	/// names the limit. default 64.
	public var maxMultipartParts: Int

	public init(
		host: String = "0.0.0.0",
		port: Int = 9090,
		maxConnections: Int = 256,
		readIdleSeconds: Int64 = 120,
		assetCacheSeconds: Int = 3600,
		pagePath: String = "/",
		themeSheet: ThemeSheet? = nil,
		assets: [WebUIServerAsset] = [],
		requireRenderToken: Bool = false,
		handlerFailurePolicy: HandlerFailurePolicy = .notifyClient,
		onRenderFailure: (@Sendable (any Error) -> String)? = nil,
		maxBodyBytes: Int = 1 << 20,
		maxMultipartParts: Int = 64
	) {
		self.host = host
		self.port = port
		self.maxConnections = maxConnections
		self.readIdleSeconds = readIdleSeconds
		self.assetCacheSeconds = assetCacheSeconds
		self.pagePath = pagePath
		self.themeSheet = themeSheet
		self.assets = assets
		self.requireRenderToken = requireRenderToken
		self.handlerFailurePolicy = handlerFailurePolicy
		self.onRenderFailure = onRenderFailure
		self.maxBodyBytes = maxBodyBytes
		self.maxMultipartParts = maxMultipartParts
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
	public typealias Render = @Sendable () throws -> String
	/// the request-aware render: receives the path and decoded query, so a page
	/// can vary by URL (deep links) as well as by router state.
	///
	/// async because a page that reflects live store state has to await it —
	/// a session store, a database, a filesystem scan. pre-rendering into a
	/// cache to satisfy a sync signature is how a page goes stale.
	///
	/// throwing: a render that throws is answered as a 500 carrying the host's
	/// error page (`WebUIServerConfig.onRenderFailure`) instead of dropping
	/// the connection. a closure that never throws needs no `try`.
	public typealias RequestRender = @Sendable (WebUIServerRequest) async throws -> String

	/// the element id a document's page region carries for in-place
	/// navigation: the `navigate` answer patches this element. a page without
	/// it is still answered (the engine skips an element it cannot find); a
	/// path the router cannot answer is answered with a full-page redirect.
	static let pageRegionID = "webui-page"

	private let config: WebUIServerConfig
	private let logger: Logger
	private var lifecycle: Lifecycle?
	/// the typed route table that answers the page path (and, at the
	/// deprecated inits, nothing else). the framework's own asset routes are
	/// matched before it, so a route can neither shadow nor disable them.
	private let pageRouter: Router

	/// render one fixed page and let the router carry all variation.
	///
	/// deprecated: a ``Router`` answers paths and parameters directly. this
	/// init keeps its signature and stands on a single-route ``Router`` for
	/// `config.pagePath`, so existing pages render byte-identically.
	@available(*, deprecated, message: "build a Router and use init(router:config:logger:)")
	public init(
		render: @escaping Render,
		router: EventRouter,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.init(requestRender: { _ in try render() }, router: router, config: config, logger: logger)
	}

	/// render from the request: path-dependent pages and `?s=<id>` deep links.
	/// distinct label, so the two inits never compete in overload resolution.
	///
	/// deprecated: a ``Router`` answers paths and parameters directly. this
	/// init keeps its signature and stands on a single-route ``Router`` for
	/// `config.pagePath`, so existing pages render byte-identically.
	@available(*, deprecated, message: "build a Router and use init(router:config:logger:)")
	public init(
		requestRender: @escaping RequestRender,
		router: EventRouter,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.config = config
		self.logger = logger
		self.router = router
		self.pageRouter = Self.deprecatedPageRouter(config: config, render: requestRender)
	}

	/// serve a typed route table, routing events through a host-owned ``EventRouter``.
	///
	/// additive beside ``init(router:config:logger:)``, which mints its own event
	/// router: that suits a host whose handlers all register during render
	/// (`.onX`/`controlAttributes`, which write into the server's router for the
	/// render's session). a host that wires handlers *explicitly* — the
	/// `router.register(_:for:)` shape, whose default session is documented as
	/// the single-page host's path — must hand its router in, or every
	/// registration lands in a router nothing consults. the label is distinct,
	/// so the two inits never compete in overload resolution.
	public init(
		router: Router,
		eventRouter: EventRouter,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.config = config
		self.logger = logger
		self.router = eventRouter
		self.pageRouter = router
	}

	/// serve a typed route table: many paths, path parameters, methods, and
	/// the engine's `navigate` answered. this actor owns its event router —
	/// handlers a page wires through `.onX`/`controlAttributes` register into
	/// it, exactly as they did with the render-closure inits.
	public init(
		router: Router,
		config: WebUIServerConfig = WebUIServerConfig(),
		logger: Logger = Logger(label: "webui.server")
	) {
		self.config = config
		self.logger = logger
		self.router = EventRouter()
		self.pageRouter = router
	}

	private let router: EventRouter
	/// the connected pages a push reaches. created at init, so a broadcast
	/// issued before `start()` is a no-op rather than a crash.
	private let sinks = ConnectionSinks()

	/// bind and serve until `stop()` or process exit.
	public func start() async throws {
		DesignSystemAssets.prewarm()
		let cfg = config
		let runner = Runner(router: router, pageRouter: pageRouter, config: cfg, logger: logger, sinks: sinks)
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

// MARK: - deprecated render inits

extension WebUIServer {
	/// the single-route router the deprecated `render:`/`requestRender:` inits
	/// stand on: the page at `config.pagePath`, plus the historic
	/// `/index.html` alias, answered through the given string-rendering
	/// closure.
	private static func deprecatedPageRouter(
		config: WebUIServerConfig,
		render: @escaping RequestRender
	) -> Router {
		Router {
			Route(
				method: .get,
				pattern: PathPattern(config.pagePath),
				responder: LegacyPageResponder(render: render)
			)
			// "/index.html" was an alias for the page before the router
			// existed and stays one, so a deep link keeps resolving.
			if config.pagePath != "/index.html" {
				Route(
					method: .get,
					pattern: PathPattern("/index.html"),
					responder: LegacyPageResponder(render: render)
				)
			}
		}
	}
}

/// the responder behind the deprecated render inits: adapt the typed request
/// to the request-aware render closure and hand its string out as html.
private struct LegacyPageResponder: Responder {
	let render: WebUIServer.RequestRender

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		let pageRequest = WebUIServerRequest(
			path: request.path,
			query: request.query,
			renderToken: request.renderToken
		)
		// the 1.x compat boundary: a `Render`/`RequestRender` closure answers a
		// String by contract (public typealias, frozen). this is the one place
		// that string becomes a page, and it is the framework — not a host —
		// that takes responsibility for it here. a host on the typed surface
		// never passes through this line.
		return HTTPResponse(body: .html(UnsafeMarkup.trusted(try await render(pageRequest))))
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
	private let router: EventRouter
	/// the typed route table that owns the page path and everything else the
	/// framework does not already answer.
	private let pageRouter: Router
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
	/// the catalog's pre-compressed variant, when the host shipped one.
	private let themeSheetGzip: ByteBuffer?
	private let themeSheetPath: String?

	struct HostAsset: Sendable {
		let body: ByteBuffer
		/// the host's pre-compressed variant, when it shipped one.
		let gzip: ByteBuffer?
		let contentType: String
		let cacheControl: String
	}

	init(
		router: EventRouter,
		pageRouter: Router,
		config: WebUIServerConfig,
		logger: Logger,
		sinks: ConnectionSinks
	) {
		self.router = router
		self.pageRouter = pageRouter
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
			self.themeSheetGzip = sheet.gzip.map { ByteBuffer(bytes: $0) }
			self.themeSheetPath = sheet.url
		} else {
			self.themeSheet = nil
			self.themeSheetGzip = nil
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
							// a frame the server refuses (an unknown render token)
							// ends the connection: that page can no longer be
							// trusted to drive this router.
							let keepGoing = await self.dispatch(eventText: payload, outbound: outbound)
							if !keepGoing { return }
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

	private func dispatch(
		eventText payload: String,
		outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>
	) async -> Bool {
		do {
			let msg = try WSIncoming(jsonText: payload)
			switch msg {
			case .event(let component, let event, let data, let token):
				guard let session = boundSession(token) else {
					try? await writeJSON(
						WSOutgoing.error(code: "token", message: "unknown or missing render token"),
						outbound: outbound
					)
					return false
				}
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let outcome = await router.dispatch(eventData, in: session)
				for frame in frames(of: outcome) {
					try await writeJSON(frame, outbound: outbound)
				}
			case .ping(let token):
				guard boundSession(token) != nil else {
					try? await writeJSON(
						WSOutgoing.error(code: "token", message: "unknown or missing render token"),
						outbound: outbound
					)
					return false
				}
				try await writeJSON(WSOutgoing.pong, outbound: outbound)
			case .navigate(let url):
				// a client-side navigation (the engine reports popstate):
				// answer it instead of discarding it. an in-scope path
				// re-renders the matched route into a fragment patch of the
				// page region (see `pageRegionID`); anything the router
				// cannot answer is a full-page redirect to the url itself.
				guard let session = boundSession(nil) else {
					try? await writeJSON(
						WSOutgoing.error(code: "token", message: "unknown or missing render token"),
						outbound: outbound
					)
					return false
				}
				await answerNavigate(url: url, session: session, outbound: outbound)
			}
		} catch {
			let err = WSOutgoing.error(code: "decode", message: "bad event: \(error)")
			try? await writeJSON(err, outbound: outbound)
		}
		return true
	}

	/// the frames to send for `outcome`, after applying the failure policy.
	///
	/// the router reports every failure through the observer funnel regardless;
	/// this decides whether the page learns about it and whether it reaches the
	/// server's log.
	private func frames(of outcome: HandlerOutcome) -> [WSOutgoing] {
		guard case .fail(let code, let message, _) = outcome else {
			return outcome.wireMessages
		}
		if config.handlerFailurePolicy != .silent {
			logger.warning("WebUIServer: handler failed (\(code)): \(message)")
		}
		return config.handlerFailurePolicy == .notifyClient ? outcome.wireMessages : []
	}

	/// resolve the render session a frame's token names.
	///
	/// `nil` means "refuse and close". a frame with no token — or with a token
	/// this server never minted — is refused only while
	/// ``WebUIServerConfig/requireRenderToken`` is on; otherwise it routes to the
	/// shared default session, which is exactly the pre-session behaviour.
	private func boundSession(_ token: String?) -> RenderSessionID? {
		guard let token, !token.isEmpty else {
			return config.requireRenderToken ? nil : .default
		}
		let session = RenderSessionID(token)
		guard router.contains(session) else {
			return config.requireRenderToken ? nil : .default
		}
		return session
	}

	// MARK: navigate

	/// answer the engine's `navigate` frame: re-render the matched route in
	/// the socket's session and patch the page region, or fall back to a
	/// full-page redirect when the router cannot answer the path.
	private func answerNavigate(
		url: String,
		session: RenderSessionID,
		outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>
	) async {
		// the engine reports `location.pathname + location.search`; derive
		// the routed path and query the same way an http request is derived.
		let pathPart = navigatePath(url)
		let request = HTTPRequest(
			method: .get,
			path: pathPart,
			query: parseQuery(navigateQuery(url)),
			renderToken: RenderToken("")
		)
		// the re-render takes the same path a fresh page request takes: a
		// session pass, the render context established for its duration.
		router.begin(session)
		let response: HTTPResponse
		do {
			response = try await RenderContext.$current.withValue(
				RenderContext(router: router, session: session)
			) {
				try await pageRouter.respond(to: request)
			}
		} catch {
			// a render throw has nowhere to carry a 500 on a websocket — the page
			// is told by frame instead, and the socket stays open.
			logger.error("WebUIServer: navigate re-render failed for \(url): \(error)")
			try? await writeJSON(
				WSOutgoing.error(code: "render", message: "re-render failed: \(error)"),
				outbound: outbound
			)
			return
		}
		let frame: WSOutgoing
		switch response.body {
		case .html(let markup):
			frame = .update(fragments: [FragmentUpdate(id: WebUIServer.pageRegionID, html: markup.html)])
		case .redirect(let to, _):
			frame = .redirect(url: to, replace: true)
		default:
			// no page markup matched and no redirect was declared: the path
			// is outside the router's scope, so answer with a full-page
			// redirect to the url the engine navigated to.
			frame = .redirect(url: url, replace: true)
		}
		try? await writeJSON(frame, outbound: outbound)
	}

	/// the routed path of a navigate url: everything before '?' and '#', with
	/// a scheme+host stripped so an absolute url routes as its path.
	private func navigatePath(_ url: String) -> String {
		var rest = url
		if let qi = rest.firstIndex(of: "?"), qi > rest.startIndex { rest = String(rest[..<qi]) }
		if let hi = rest.firstIndex(of: "#"), hi > rest.startIndex { rest = String(rest[..<hi]) }
		if let scheme = rest.range(of: "://") {
			if let slash = rest[scheme.upperBound...].firstIndex(of: "/") {
				rest = String(rest[slash...])
			} else {
				rest = "/"
			}
		}
		return rest.isEmpty ? "/" : rest
	}

	/// the query text of a navigate url ("" when absent).
	private func navigateQuery(_ url: String) -> String {
		guard let qi = url.firstIndex(of: "?") else { return "" }
		return String(url[url.index(after: qi)...].prefix(while: { $0 != "#" }))
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
			// nio's upgraded http stream allows exactly ONE iterator per
			// connection, so the whole request loop — the head, the bounded body
			// read, the next request's head — shares this one.
			var iterator = inbound.makeAsyncIterator()
			// a streaming response runs as a lease alongside this loop: the
			// response is written by its own task, so a pipelined request is
			// simply deferred until the stream's response completes (http/1.1
			// answers in order). `StreamingReadKeeper` keeps the socket's reads
			// armed so a mid-stream disconnect cancels the lease.
			var streaming: Task<Void, Never>? = nil

			while let part = try await iterator.next() {
				guard case .head(let head) = part else { continue }
				// a request that arrived while a stream is still answering the
				// previous one cannot be answered out of order (http/1.1), so
				// defer it until the stream's response is complete.
				if let lease = streaming {
					await lease.value
					streaming = nil
				}
				// a wire verb the typed model cannot name (trace, connect,
				// custom): answer the old blanket 405 rather than routing a
				// verb the model has no case for.
				guard let method = HTTPMethod(rawValue: head.method.rawValue.lowercased()) else {
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
				// the framework asset chain is get-only (that is how browsers
				// fetch it); every other request — a non-get included — is the
				// typed router's (plan w3.2). a non-get body is read under the
				// byte cap: a declared `Content-Length` over the cap is refused
				// BEFORE any buffering, and a body that outgrows the cap
				// mid-stream is refused the moment it does — the bounded-parse
				// discipline, applied to request bodies (plan w3.3).
				if method != .get {
					let declaredLength = BodyReader.contentLength(head.headers)
					var bodyBytes: [UInt8] = []
					var received: Int = 0
					if let declaredLength, declaredLength > config.maxBodyBytes {
						received = declaredLength
					} else {
						while let bodyPart = try await iterator.next() {
							guard case .body(let buffer) = bodyPart else { break }
							if received != 0 { continue }
							bodyBytes.append(contentsOf: buffer.readableBytesView)
							if bodyBytes.count > config.maxBodyBytes {
								received = bodyBytes.count
							}
						}
					}
					if received != 0 {
						try await respond(
							channel: channel.channel,
							body: "413 — request body too large: WebUIServerConfig.maxBodyBytes is \(config.maxBodyBytes) bytes; received \(received)",
							contentType: "text/plain; charset=utf-8",
							status: .payloadTooLarge
						)
						continue
					}
					if let declaredLength, declaredLength != bodyBytes.count {
						// a declared length that contradicts the received byte
						// count is a smuggling red flag, never something to route.
						try await respond(
							channel: channel.channel,
							body: "400 — Content-Length declares \(declaredLength) bytes, but \(bodyBytes.count) arrived; the body is refused",
							contentType: "text/plain; charset=utf-8",
							status: .badRequest
						)
						continue
					}
					streaming = try await routePage(
						channel: channel.channel,
						method: method,
						path: path,
						queryText: queryText,
						headers: head.headers,
						body: bodyBytes
					)
					continue
				}
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
					// sheet is a different url and no cache invalidation is ever needed. it
					// negotiates like every other asset route when the host built a variant.
					try await respond(
						channel: channel.channel,
						bytes: sheet,
						gzip: themeSheetGzip,
						acceptEncoding: acceptEncoding,
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
				} else {
					// everything the asset chain does not answer is the router's:
					// the page route became a responder in plan w3.2, so this is
					// the ONLY path into the page. a path no route matches is the
					// router's 404; a matched pattern with an unmatched method is
					// its 405 with an Allow header.
					streaming = try await routePage(
						channel: channel.channel,
						method: method,
						path: path,
						queryText: queryText,
						headers: head.headers
					)
				}
			}
			if let lease = streaming { await lease.value }
		}
	}

	/// route one request through the typed ``Router``.
	///
	/// the server owns the render context: handlers a page wires through
	/// `.onX`/`controlAttributes` register into THIS server's router, so hosts
	/// never juggle a second router (the classic page-local vs server-router
	/// mismatch). a page that wraps its own context still wins (the inner
	/// `withValue` takes precedence), so existing hosts are unaffected.
	///
	/// every render also mints a token and opens a render session for it. the
	/// session is what bounds the router: a page's auto-minted ids are minted
	/// *within* it, so re-rendering overwrites the same keys instead of
	/// appending new ones, and two page instances can reuse one id space
	/// without ever sharing a handler.
	private func routePage(
		channel: Channel,
		method: HTTPMethod,
		path: String,
		queryText: Substring,
		headers: HTTPHeaders,
		body: [UInt8] = []
	) async throws -> Task<Void, Never>? {
		let token = RenderToken.mint() ?? RenderToken("")
		if token.value.isEmpty {
			logger.error("WebUIServer: entropy unavailable — this render's events cannot be token-bound")
		}
		let session = token.session
		router.begin(session)

		// parse the bounded body into a typed shape. a refusal here — the
		// byte cap, the part cap, a lying content length, a malformed
		// boundary — is answered with a status that names the limit, never
		// routed (plan w3.3).
		var requestBody: RequestBody = body.isEmpty ? .none : .bytes(body)
		if !body.isEmpty {
			let contentType = headers.first(name: "Content-Type") ?? ""
			let reader = BodyReader(
				maxBodyBytes: config.maxBodyBytes,
				maxMultipartParts: config.maxMultipartParts
			)
			do {
				if contentType.hasPrefix("application/x-www-form-urlencoded") {
					requestBody = .form(reader.urlencoded(body))
				} else if contentType.hasPrefix("multipart/form-data") {
					requestBody = .multipart(try reader.multipart(body, contentType: contentType))
				}
			} catch let error as BodyParseError {
				switch error {
				case .tooLarge(let limit, let actual):
					try await respond(
						channel: channel,
						body: "413 — request body too large: WebUIServerConfig.maxBodyBytes is \(limit) bytes; received \(actual)",
						contentType: "text/plain; charset=utf-8",
						status: .payloadTooLarge
					)
				case .tooManyParts(let limit, let actual):
					try await respond(
						channel: channel,
						body: "422 — multipart body has too many parts: WebUIServerConfig.maxMultipartParts is \(limit); received \(actual) parts",
						contentType: "text/plain; charset=utf-8",
						status: .unprocessableEntity
					)
				case .lengthMismatch(let declared, let actual):
					try await respond(
						channel: channel,
						body: "400 — Content-Length declares \(declared) bytes, but \(actual) arrived; the body is refused",
						contentType: "text/plain; charset=utf-8",
						status: .badRequest
					)
				case .malformedMultipart:
					try await respond(
						channel: channel,
						body: "400 — malformed multipart body",
						contentType: "text/plain; charset=utf-8",
						status: .badRequest
					)
				}
				return nil
			}
		}

		let request = HTTPRequest(
			method: method,
			path: path,
			query: parseQuery(String(queryText)),
			headers: headers,
			body: requestBody,
			renderToken: token
		)
		let response: HTTPResponse
		do {
			response = try await RenderContext.$current.withValue(
				RenderContext(router: router, session: session)
			) {
				try await pageRouter.respond(to: request)
			}
		} catch {
			// a render throw used to drop the connection — the error surfaced as a
			// dead page with no explanation. now it is a 500 carrying the host's
			// error page (or a plain naming of the failure), and the connection
			// survives. a swift trap is not an error and never lands here.
			logger.error("WebUIServer: page render failed for \(path): \(error)")
			let body: HTTPResponse.Body
			if let page = config.onRenderFailure {
				// the error-page boundary: `onRenderFailure` is a host closure
				// that answers a String by contract (a frozen public config
				// property — `WebUIServerConfig.onRenderFailure`), so this is
				// where that string becomes a page. the framework — not the
				// host — takes responsibility for it here; a host on the typed
				// surface never passes through this line.
				body = .html(UnsafeMarkup.trusted(page(error)))
			} else {
				body = .text("500 — the page failed to render: \(error)")
			}
			response = HTTPResponse(status: 500, body: body)
		}
		return try await respond(channel: channel, response: response)
	}

	/// encode a typed ``HTTPResponse`` onto the wire — status, headers,
	/// cookies, and one body shape — through the same byte responder the
	/// cached assets use, so the security-header block and the cache policy
	/// stay in one place.
	///
	/// a `Body.stream` response is not awaited here: it returns a lease the
	/// connection's request loop defers subsequent requests to while the
	/// stream runs (see `handleHTTP` and `respondStream`). every other body
	/// shape returns nil.
	private func respond(
		channel: Channel,
		response: HTTPResponse
	) async throws -> Task<Void, Never>? {
		let contentType: String
		let status: HTTPResponseStatus
		var extraHeaders: [(name: String, value: String)] = []
		let body: ByteBuffer

		switch response.body {
		case .html(let markup):
			contentType = "text/html; charset=utf-8"
			status = HTTPResponseStatus(statusCode: response.status.code)
			var buf = channel.allocator.buffer(capacity: markup.html.utf8.count)
			buf.writeString(markup.html)
			body = buf
		case .text(let text):
			contentType = "text/plain; charset=utf-8"
			status = HTTPResponseStatus(statusCode: response.status.code)
			var buf = channel.allocator.buffer(capacity: text.utf8.count)
			buf.writeString(text)
			body = buf
		case .bytes(let bytes, let bytesContentType):
			contentType = bytesContentType
			status = HTTPResponseStatus(statusCode: response.status.code)
			body = channel.allocator.buffer(bytes: bytes)
		case .stream(let chunks, let streamContentType):
			// a streaming body takes a different writer: chunked framing, a
			// flush per chunk, and the producer cancelled on disconnect. the
			// byte responder below would impose a content-length, which a
			// stream cannot honor.
			//
			// the stream runs as a background lease: the connection's request
			// loop must keep reading while it is in flight or a mid-stream
			// disconnect would never surface (nio pauses the socket's reads the
			// moment the loop stops demanding), so this hands the lease back
			// instead of awaiting the stream's end.
			let lease = Task<Void, Never> { _ = try? await respondStream(
				channel: channel,
				chunks: chunks,
				contentType: streamContentType,
				status: HTTPResponseStatus(statusCode: response.status.code),
				extraHeaders: response.headers,
				cookies: response.cookies
			) }
			return lease
		case .empty:
			contentType = "text/plain; charset=utf-8"
			status = HTTPResponseStatus(statusCode: response.status.code)
			body = ByteBuffer()
		case .redirect(let to, let redirectStatus):
			contentType = "text/plain; charset=utf-8"
			status = HTTPResponseStatus(statusCode: redirectStatus.code)
			extraHeaders.append(("Location", to))
			body = ByteBuffer()
		}

		// response headers and cookies are extras: applied after the
		// framework's own block, so a handler can set any header it pleases.
		extraHeaders.append(contentsOf: response.headers.map { (name: $0.key, value: $0.value) })
		for cookie in response.cookies {
			if let header = try? cookie.setCookieHeaderValue() {
				extraHeaders.append(("Set-Cookie", header))
			}
		}

		try await respond(
			channel: channel,
			bytes: body,
			contentType: contentType,
			status: status,
			cacheControl: "no-store",
		extraHeaders: extraHeaders
	)
	return nil
}

	/// stream a `Body.stream` response: `Transfer-Encoding: chunked`, one flush
	/// per chunk, and the producing stream cancelled the moment the connection
	/// goes away.
	///
	/// the cancellation wiring mirrors `WebUIServerService.run()`. each stream
	/// gets one task that owns the iteration, and every signal that says "the
	/// client is gone" — the channel closing, or the outer request task being
	/// cancelled — cancels that task. the cancellation propagates into the chunk
	/// stream's storage (sse's async cancellation contract: a cancelled consumer
	/// ends the `for await` and fires the producer's termination hook), which
	/// lets a producer that never finishes be wound down on disconnect instead
	/// of leaking. the registration order is safe by construction: a channel
	/// that already closed has a complete close future, whose callback fires
	/// immediately and cancels the task before its first iteration can write.
	///
	/// the lease runs detached from the request loop (see `respond`); the loop
	/// defers pipelined requests to it, and `StreamingReadKeeper` keeps the
	/// socket's reads armed past nio's response-pending gate, so a mid-stream
	/// disconnect shows up as an eof that completes the close future and
	/// cancels the iterate task. no timer or polling is involved.
	///
	/// there is no `defer` here — `await` is forbidden in `defer` — so the
	/// terminal chunk is written on the success path and the error path simply
	/// lets the closed channel swallow whatever could not be written.
private func respondStream(
	channel: Channel,
	chunks: AsyncStream<[UInt8]>,
	contentType: String,
	status: HTTPResponseStatus,
	extraHeaders: [String: String],
	cookies: [WebUISharedCore.HTTPCookie]
) async throws {
	var head = HTTPResponseHead(version: .http1_1, status: status)
	// chunked framing instead of a content-length: nio's http encoder frames
	// each flushed body part once this header is present.
	head.headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
	head.headers.replaceOrAdd(name: "Content-Type", value: contentType)
	// security headers — parity with the plain-http responder.
	head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
	head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
	head.headers.replaceOrAdd(name: "Service-Worker-Allowed", value: "/")
	head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
	for (name, value) in extraHeaders {
		head.headers.replaceOrAdd(name: name, value: value)
	}
	for cookie in cookies {
		if let header = try? cookie.setCookieHeaderValue() {
			head.headers.replaceOrAdd(name: "Set-Cookie", value: header)
		}
	}
	// the head goes out before the first chunk, so the client establishes
	// the stream on the headers instead of waiting for the first event.
	try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head)).get()

	// a mid-stream disconnect is only observable if the socket keeps
	// reading: nio's http pipeline swallows `read()` while a response is in
	// flight, so the client's fin would otherwise sit unseen until the
	// connection is reused or reaped. the keeper below re-arms the socket's
	// reads from the head of the pipeline — past that gate — on demand.
	try await channel.pipeline.addHandler(StreamingReadKeeper(), position: .first).get()
	channel.pipeline.fireUserInboundEventTriggered(KeepReading())

	// the iterate task owns the chunk consumption. it is cancelled from the
	// channel's close future and from outer cancellation; both paths end the
	// `for await`, which lets the producer's termination hook fire.
	let iteration = Task { () -> Void in
		do {
			for await chunk in chunks {
				try Task.checkCancellation()
				var buffer = channel.allocator.buffer(capacity: chunk.count)
				buffer.writeBytes(chunk)
				try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.body(buffer)).get()
				// keep the read armed across read cycles: the eof observed
				// here is what cancels the producing stream.
				channel.pipeline.fireUserInboundEventTriggered(KeepReading())
			}
		} catch {
			// the channel died or the task was cancelled mid-write: every
			// byte after the failure is lost, so there is no terminator to
			// write and nothing to unwind.
		}
	}
	channel.closeFuture.whenComplete { _ in iteration.cancel() }
	try await withTaskCancellationHandler {
		await iteration.value
	} onCancel: {
		iteration.cancel()
	}
	// the stream ended on its own: close the chunked framing with the
	// zero-length terminal chunk.
	try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
}

	private func respond(
		channel: Channel,
		body: String,
		contentType: String,
		status: HTTPResponseStatus = .ok,
		cacheControl: String = "no-store",
		extraHeaders: [(name: String, value: String)] = []
	) async throws {
		// one copy: the utf-8 view goes straight into the channel's buffer.
		var buf = channel.allocator.buffer(capacity: body.utf8.count)
		buf.writeString(body)
		try await respond(
			channel: channel,
			bytes: buf,
			contentType: contentType,
			status: status,
			cacheControl: cacheControl,
			extraHeaders: extraHeaders
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
		cacheControl: String = "no-store",
		extraHeaders: [(name: String, value: String)] = []
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
		// per-response extras, applied last so a caller cannot have one silently
		// overwritten by the block above.
		for header in extraHeaders {
			head.headers.replaceOrAdd(name: header.name, value: header.value)
		}
		// await the terminal write promise: the async channel writer does not
		// await write promises, and a response larger than the socket send
		// buffer would otherwise lose its tail when the connection closes
		// right after writing (probe-verified truncation).
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(body))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}

	/// the fallback for wire verbs the typed model cannot name. the router
	/// answers every routed 405 with its own Allow list; this one exists only
	/// for verbs that never reach a route.
	private func respond405(channel: Channel) async throws {
		try await respond(
			channel: channel,
			body: Router.methodNotAllowedBody,
			contentType: "text/plain; charset=utf-8",
			status: .methodNotAllowed,
			extraHeaders: [("Allow", "GET")]
		)
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
func percentDecode(_ text: Substring) -> String {
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

/// a marker fired through the pipeline to ask `StreamingReadKeeper` to
/// re-arm the socket's read interest.
private struct KeepReading: Hashable {}

/// sits at the head of the pipeline and starts a socket read on demand.
///
/// nio's http pipeline deliberately swallows `read()` while a response is in
/// flight (`HTTPServerPipelineHandler` parks it until the response ends), so
/// a client that vanishes mid-stream would otherwise never be noticed. a
/// read begun from this handler's position reaches the socket without
/// crossing that gate, so the peer's fin is seen as an eof, the close future
/// completes, and the producing stream is cancelled (see `respondStream`).
final class StreamingReadKeeper: ChannelInboundHandler {
	typealias InboundIn = Never
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is KeepReading {
			context.read()
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

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