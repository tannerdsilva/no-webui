import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIAuth

// MARK: - Session registry (per-session interactive routers)

// maps a session's token hash to the EventRouters of its recent full renders,
// keyed by the per-render websocket token minted into each page. replaced as
// pages re-render (one router per render pass). keeping the recent N render
// tokens per session lets several tabs of the same session route events while
// a stale page from a *different* session can never present a valid token for
// this one (cross-session replay); logout removes the whole session entry.
final class RouterRegistry: Sendable {
	private struct Values {
		var routers: [[UInt8]: [String: EventRouter]] = [:]
		var order: [[UInt8]: [String]] = [:]
	}
	private let values = Mutex(Values())
	private let maxRendersPerSession: Int

	init(maxRendersPerSession: Int = 8) {
		self.maxRendersPerSession = maxRendersPerSession
	}

	func router(forTokenHash hash: [UInt8], renderToken: String) -> EventRouter? {
		values.withLock { $0.routers[hash]?[renderToken] }
	}
	func set(_ router: EventRouter, forTokenHash hash: [UInt8], renderToken: String) {
		values.withLock { values in
			if values.routers[hash] == nil {
				values.routers[hash] = [:]
				values.order[hash] = []
			}
			if let seen = values.order[hash]!.firstIndex(of: renderToken) {
				values.order[hash]!.remove(at: seen)
			}
			values.routers[hash]![renderToken] = router
			values.order[hash]!.append(renderToken)
			while values.order[hash]!.count > maxRendersPerSession {
				let evicted = values.order[hash]!.removeFirst()
				values.routers[hash]!.removeValue(forKey: evicted)
			}
		}
	}
	func remove(forTokenHash hash: [UInt8]) {
		values.withLock { values in
			values.routers.removeValue(forKey: hash)
			values.order.removeValue(forKey: hash)
		}
	}

	/// snapshot of every session token hash that has live router entries —
	/// used by the maintenance sweep to drop entries whose session has expired
	/// or been purged.
	func allTokenHashes() -> [[UInt8]] {
		values.withLock { Array($0.routers.keys) }
	}
}

// MARK: - Authenticated connection registry (logout teardown)

// maps a session's token hash to the live WebSocket channels bound to it.
// logout (and any future server-side invalidation) closes every channel here
// so revocation tears the connection down immediately — the per-event liveness
// check is the backstop, not the primary mechanism. channels self-unregister
// when the connection ends (including idle-reaped ones).
actor AuthConnectionRegistry {
	private var nextID = 0
	private var channels: [[UInt8]: [Int: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>]] = [:]

	/// register `channel` under its session; returns a handle for unregister.
	func register(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, tokenHash: [UInt8]) -> Int {
		nextID += 1
		channels[tokenHash, default: [:]][nextID] = channel
		return nextID
	}

	func unregister(_ id: Int, tokenHash: [UInt8]) {
		guard var byID = channels[tokenHash] else { return }
		byID.removeValue(forKey: id)
		if byID.isEmpty {
			channels.removeValue(forKey: tokenHash)
		} else {
			channels[tokenHash] = byID
		}
	}

	/// close every socket bound to `tokenHash` (fire-and-forget).
	func closeAll(forTokenHash tokenHash: [UInt8]) {
		guard let byID = channels.removeValue(forKey: tokenHash) else { return }
		for channel in byID.values {
			_ = channel.channel.close()
		}
	}
}

// MARK: - Idle socket reaping

/// signal a refused admission: `--max-connections` reached.
enum ConnectionGateError: Error { case atCapacity }

/// release a `ConnectionGate` slot when the channel closes. the gate is
/// acquired in the child channel initializer — BEFORE any request or upgrade
/// negotiation — so bare connect-only sockets count toward the cap and a
/// connect-flood cannot sidestep it through negotiation that never completes.
final class ConnectionGateReleaser: ChannelInboundHandler {
	typealias InboundIn = IOData
	private let gate: ConnectionGate
	init(gate: ConnectionGate) { self.gate = gate }
	func channelInactive(context: ChannelHandlerContext) {
		gate.release()
		context.fireChannelInactive()
	}
}

// an authenticated socket that stops sending (no pings, no events) is closed
// after the read-idle window — a silent zombie never outlives its timeout.
// the runtime pings every 30s, so a healthy connection resets the counter.
final class AuthIdleCloseHandler: ChannelInboundHandler {
	typealias InboundIn = WebSocketFrame
	func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
		if event is IdleStateHandler.IdleStateEvent {
			context.close(promise: nil)
		} else {
			context.fireUserInboundEventTriggered(event)
		}
	}
}

// MARK: - Demo state (per-process interactive model, like WebUIExample)

final class AuthDemoState: Sendable {
	private struct Values {
		var count = 0
		var progress = 0.25
		var echo = ""
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

// MARK: - Page renderers

/// render the interactive dashboard for an authenticated session. the page is
/// a full re-render with a *fresh* `EventRouter` per render pass (house rule),
/// registered under the session's token hash so the WebSocket can dispatch to
/// it. `AuthContext` flows into the tree so views can branch on the identity.
func renderDashboard(state: AuthDemoState, auth: AuthContext, logoutToken: String, renderToken: String) -> (html: String, router: EventRouter) {
	let router = EventRouter()
	let html = AuthContext.$current.withValue(auth) {
		RenderContext.$current.withValue(RenderContext(router: router)) {
			Div(class: "app") {
				Header(class: "app__header") {
					Heading("Member Dashboard", level: .h1)
					Div(class: "app__session") {
						Text("signed in as \(auth.identity?.id ?? "?") · roles: \(auth.identity?.roles.sorted().joined(separator: ", ") ?? "none")")
						// logout is a native POST form (no event handler
						// modifier -> the runtime does not hijack its submit)
						// carrying a per-render CSRF token.
						Form(action: "/logout", method: "post", class: "app__logout", csrfToken: logoutToken) {
							Button("sign out", class: "button button--ghost button--sm", type: .submit)
						}
					}
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
								.onOptimisticClick(
									predict: { [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))] },
									perform: { _ in
										state.count = 0
										return [FragmentUpdate(id: "counter-value", html: counterValueHTML(0))]
									}
								)
						}
					}
					WebUICard(variant: .outlined) {
						Heading("Progress", level: .h3)
						Raw(progressValueHTML(state.progress))
						Div(class: "app__actions") {
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
					WebUICard(variant: .flat) {
						Heading("Echo", level: .h3)
						WebUIInput(placeholder: "Type something…", id: "echo-input", label: "Input")
							.onInput { event in
								state.echo = event.data["value"] ?? ""
								return [FragmentUpdate(id: "echo-out", html: echoOutHTML(state.echo))]
							}
						Raw(echoOutHTML(state.echo))
					}
				}
			}
			.render()
		}
	}
	let document = WebUIDocument(
		title: "Member Dashboard",
		body: html,
		// the per-render websocket token: the runtime echoes it with every
		// event/ping, and the server only routes messages carrying a token it
		// minted for this session (cross-session replay protection).
		runtimeConfig: RuntimeConfig(renderToken: renderToken)
	).render()
	return (html: document, router: router)
}

/// render the login page. per AD-1 this is a *static* document — no JS
/// runtime, native form POST, a synchronizer CSRF token, and a hardened CSP
/// with `form-action 'self'` (the framework default only covers
/// default/script/style/img/connect-src; auth pages add the rest explicitly).
func renderLoginPage(error: String?, csrfToken: String) -> String {
	let body = Div(class: "login") {
		Div(class: "login__card") {
			Heading("Sign in", level: .h1)
			if let error {
				Div(class: "login__error") {
					Text(error)
				}
			}
			Form(action: "/login", method: "post", class: "login__form", csrfToken: csrfToken) {
				Label("Username", for: "username")
				Input(id: "username", name: "username", placeholder: "admin", type: .text, required: true)
				Label("Password", for: "password")
				Input(id: "password", name: "password", placeholder: "password", type: .password, required: true)
				Button("Sign in", class: "button button--primary button--md", type: .submit)
			}
		}
	}
	return WebUIDocument(
		title: "Sign in",
		body: body.render(),
		includeRuntime: false,
		// form-action + base-uri are meta-valid CSP directives; clickjacking
		// control is delivered as an X-Frame-Options header on the response
		// (frame-ancestors is header-only and inert in a meta element).
		contentSecurityPolicy: "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; form-action 'self'; base-uri 'self'"
	).render()
}

// MARK: - URL-encoded body parsing (single-purpose, for POST /login)

enum URLEncodedForm {
	enum ParseError: Error {
		case invalidPercentEncoding
	}
	static func parse(_ body: String) throws -> [String: String] {
		var result: [String: String] = [:]
		for pair in body.split(separator: "&") {
			let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
			guard components.count == 2 else { continue }
			let key = String(components[0]).replacingOccurrences(of: "+", with: " ")
			let value = String(components[1]).replacingOccurrences(of: "+", with: " ")
			guard let decodedKey = key.removingPercentEncoding,
			      let decodedValue = value.removingPercentEncoding else {
				throw ParseError.invalidPercentEncoding
			}
			result[decodedKey] = decodedValue
		}
		return result
	}
}

// MARK: - Session plumbing

enum DemoSession {
	static let cookieName = "auth" // deliberately *not* __Host-: the demo runs on
	// plain http where `Secure` cannot be promised; production uses
	// __Host-auth + Secure + TLS (see the cookie __Host- rules in WebUIAuth).
	static let maxAgeSeconds = 8 * 60 * 60
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

// MARK: - Auth server entry point

/// the auth demo server: `@main` entry type (see `--port` above).
@main
struct WebUIAuthExample {
	// demo credentials (trivial by design — this is the demonstration login)
	static let demoUsername = "admin"
	static let demoPassword = "password"

	let state: AuthDemoState
	let sessionStore: InMemoryAuthSessionStore
	let csrfSecret: String
	let adminPasswordRecord: PasswordRecord
	let argonPool: NIOThreadPool
	let connectionGate: ConnectionGate
	let routers = RouterRegistry()
	let connections = AuthConnectionRegistry()
	let argon2Limiter = AsyncSemaphore(permits: 4)
	let loginThrottle = LoginThrottle(windowSeconds: 60, maxAttempts: 20)
	// the mint page gets its own, more generous budget — separate from submit
	// attempts so a user can refresh the login page without burning their
	// attempt budget, but still bounds how fast one ip can load it.
	let loginPageThrottle = LoginThrottle(windowSeconds: 60, maxAttempts: 60)
	let loginTokenStore = SingleUseTokenStore()

	// uploads beyond this are rejected with 413 — the demo accepts only tiny
	// urlencoded forms.
	static let maxBodyBytes = 16 * 1024

	// MARK: auth helpers

	func sessionDescription(for request: HTTPRequestHead) async -> (session: AuthenticatedSession, token: [UInt8])? {
		guard let cookieHeader = request.headers.first(name: "cookie"),
		      let cookieValue = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName] else {
			return nil
		}
		let tokenBytes = Self.decodeCookieToken(cookieValue)
		guard let tokenHash = try? SessionToken.hash(tokenBytes) else { return nil }
		guard let session = try? await sessionStore.find(tokenHash: tokenHash),
		      !session.isExpired() else {
			return nil
		}
		return (session, tokenBytes)
	}

	func tokenHash(for request: HTTPRequestHead) -> [UInt8]? {
		guard let cookieHeader = request.headers.first(name: "cookie"),
		      let cookieValue = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName] else {
			return nil
		}
		return try? SessionToken.hash(Self.decodeCookieToken(cookieValue))
	}

	static func decodeCookieToken(_ token: String) -> [UInt8] {
		// sessions are minted as base64 of the raw 32-byte token; only that
		// form is accepted (no utf8 fallback — the encoding is unambiguous).
		Base64.decode(token) ?? []
	}

	/// the WebSocket upgrade is refused for foreign origins: a same-origin
	/// page is the only thing that should drive the session's socket, and
	/// `SameSite=Lax` cookies are still sent to same-host (port-agnostic)
	/// siblings, so the true host check is the upgrade-time gate.
	func originMatchesHost(head: HTTPRequestHead) -> Bool {
		guard let origin = head.headers.first(name: "origin") else { return false }
		let host = (head.headers.first(name: "host") ?? "").lowercased()
		guard let url = URL(string: origin) else { return false }
		var authority = (url.host ?? "").lowercased()
		if let port = url.port {
			authority += ":\(port)"
		}
		return authority == host
	}

	/// write a full http response and await the terminal write's promise. the
	/// `NIOAsyncChannel` outbound writer does not await write promises, so a
	/// response larger than the socket send buffer could be truncated when the
	/// connection closes right after writing (probe-verified: ~327 kb pages
	/// lost their tail). writing through the raw channel and awaiting the
	/// terminal flush guarantees every byte reached the kernel before the
	/// connection closes — no send-buffer sizing required.
	func writeResponse(channel: Channel, head: HTTPResponseHead, body: ByteBuffer) async throws {
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.head(head))
		_ = channel.write(HTTPPart<HTTPResponseHead, ByteBuffer>.body(body))
		try await channel.writeAndFlush(HTTPPart<HTTPResponseHead, ByteBuffer>.end(nil)).get()
	}

	func loginResponse(channel: Channel, status: HTTPResponseStatus, headers: [(String, String)], body: String) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: status)
		// clickjacking control — X-Frame-Options is header-only (the
		// frame-ancestors CSP directive is inert in a <meta> element).
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		// authenticated pages must not be cacheable: no-store keeps the
		// dashboard (username, roles, logout token) out of the http cache and
		// out of the back-forward cache after logout on shared machines.
		head.headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
		head.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
		for (name, value) in headers {
			head.headers.replaceOrAdd(name: name, value: value)
		}
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		var buf = ByteBuffer()
		buf.writeString(body)
		try await writeResponse(channel: channel, head: head, body: buf)
	}

	func redirect(channel: Channel, to target: String, setCookies: [(String, String)] = []) async throws {
		var setCookieHeaders = setCookies
		setCookieHeaders.insert(("Location", target), at: 0)
		try await loginResponse(channel: channel, status: .seeOther, headers: setCookieHeaders, body: "")
	}

	/// refused upgrade response: write the rejection and close, then return
	/// `nil` so the upgrader declines. the typed upgrader's fallback replay
	/// re-delivers only `.end` (the request head is not buffered), so routing
	/// can never see a refused upgrade — the answer has to go out here.
	func rejectUpgrade(channel: Channel, status: HTTPResponseStatus) -> EventLoopFuture<HTTPHeaders?> {
		var head = HTTPResponseHead(version: .http1_1, status: status)
		head.headers.replaceOrAdd(name: "Content-Length", value: "0")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		let body = ByteBuffer(string: "")
		_ = channel.writeAndFlush(HTTPServerResponsePart.head(head))
		_ = channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(body)))
		return channel.writeAndFlush(HTTPServerResponsePart.end(nil))
			.map { nil as HTTPHeaders? }
	}

	// MARK: server

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
		// port is a flag so the ceremony tests can boot on an ephemeral port
		// without contending with a running demo on :9091.
		let port: Int
		if let flagIndex = CommandLine.arguments.firstIndex(of: "--port"),
		   flagIndex + 1 < CommandLine.arguments.count,
		   let parsed = Int(CommandLine.arguments[flagIndex + 1]), parsed > 0, parsed < 65536 {
			port = parsed
		} else {
			port = 9091
		}
		// resource budget for small hosts (a 2 gb linux box): event loops size
		// the nio group, argon2 workers size the kdf thread pool, and the
		// connection cap is a hard memory ceiling — each open connection can
		// hold a page-sized response while an awaited write drains.
		let csrfSecret = try CSRFProtection.generateSecret()
		let passwordRecord = PasswordRecord(
			salt: try PasswordVerifier.makeSalt(),
			hash: [],
			parameters: .interactive
		)
		let hash = try PasswordVerifier.hash(
			password: [UInt8](demoPassword.utf8),
			salt: passwordRecord.salt,
			parameters: .interactive
		)
		let record = PasswordRecord(salt: passwordRecord.salt, hash: hash, parameters: .interactive)

		let argonPool = NIOThreadPool(numberOfThreads: Self.intFlag(named: "--argon2-workers", default: 2))
		argonPool.start()
		let connectionGate = ConnectionGate(maximum: Self.intFlag(named: "--max-connections", default: 256))
		let example = WebUIAuthExample(
			state: AuthDemoState(),
			sessionStore: InMemoryAuthSessionStore(),
			csrfSecret: csrfSecret,
			adminPasswordRecord: record,
			argonPool: argonPool,
			connectionGate: connectionGate
		)

		let logger = Logger(label: "webui.auth.example")
		logger.info("auth demo ready — sign in with '\(demoUsername)' / '\(demoPassword)'")
		// prewarm the hoisted minified sheets so the one-time ~10 ms minify
		// never lands inside the first request handler.
		DesignSystemAssets.prewarm()

		let group = MultiThreadedEventLoopGroup(numberOfThreads: Self.intFlag(named: "--event-loops", default: System.coreCount))
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<AuthUpgradeResult>, Never> = try await bootstrap.bind(
			host: "0.0.0.0", port: port
		) { channel in
			channel.eventLoop.makeCompletedFuture { () -> EventLoopFuture<AuthUpgradeResult> in
				// admission: every connection — request-bearing or a bare connect —
				// counts toward the cap (acquired before any negotiation), so a
				// connect-flood cannot sidestep the gate through channels whose
				// negotiation never completes. at capacity the channel is closed
				// before any parsing happens.
				guard example.connectionGate.tryAcquire() else {
					channel.close(promise: nil)
					return channel.eventLoop.makeFailedFuture(ConnectionGateError.atCapacity)
				}
				// a single idle reaper guards every channel — plain http (an idle
				// keep-alive or a slow reader that never drains) and upgraded
				// websockets alike — so no silent connection outlives the window.
				try channel.pipeline.syncOperations.addHandler(IdleStateHandler(readTimeout: .seconds(120)))
				try channel.pipeline.syncOperations.addHandler(AuthIdleCloseHandler())
				// release the gate slot when this channel finally closes.
				try channel.pipeline.syncOperations.addHandler(ConnectionGateReleaser(gate: example.connectionGate))
				let upgrader = NIOTypedWebSocketServerUpgrader<AuthUpgradeResult>(
					shouldUpgrade: { channel, head in
						// the demo binds the socket to the page's per-session
						// router at upgrade time (cookie -> token hash -> router
						// registered by the last full render), refuses foreign
						// origins, and — since the login page never connects —
						// requires a real, unexpired session cookie before the
						// 101 is ever sent. refusals are answered directly here
						// (the upgrader's fallback replay only re-delivers
						// `.end`, so routing can't see the request head).
						let structurallyValid = head.method == .GET
							&& head.uri == "/ws"
							&& example.originMatchesHost(head: head)
						guard structurallyValid else {
							return example.rejectUpgrade(channel: channel, status: .forbidden)
						}
						let sessionValid: EventLoopFuture<Bool> = channel.eventLoop.makeFutureWithTask {
							guard let tokenHash = example.tokenHash(for: head),
							      let session = try? await example.sessionStore.find(tokenHash: tokenHash),
							      !session.isExpired() else {
								return false
							}
							return true
						}
						return sessionValid.flatMap { valid in
							if valid {
								return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
							}
							return example.rejectUpgrade(channel: channel, status: .forbidden)
						}
					},
						upgradePipelineHandler: { channel, head in
						channel.eventLoop.makeCompletedFuture {
							// the top-level IdleStateHandler already reaps
							// silent sockets (read-idle, incl. missing ws
							// pings) — no per-upgrade reaper needed.
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
							let tokenHash = example.tokenHash(for: head)
							// the router is NOT resolved at upgrade: the first
							// event/ping carries the page's render token, which
							// selects the router (and proves the page belongs to
							// this session). see `boundRouter`.
							return AuthUpgradeResult.websocket(ws, tokenHash: tokenHash)
						}
					}
				)
				let config = NIOTypedHTTPServerUpgradeConfiguration(
					upgraders: [upgrader],
					notUpgradingCompletionHandler: { channel in
						channel.eventLoop.makeCompletedFuture {
							try channel.pipeline.syncOperations.addHandler(HTTPByteBufferResponsePartHandler())
							let http = try NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>(wrappingChannelSynchronously: channel)
							return AuthUpgradeResult.http(http)
						}
					}
				)
				let pipelineConfig = NIOUpgradableHTTPServerPipelineConfiguration(upgradeConfiguration: config)
				let negotiation = try channel.pipeline.syncOperations.configureUpgradableHTTPServerPipeline(configuration: pipelineConfig)
				return negotiation
			}
		}

		logger.info("auth demo on http://localhost:\(port) (ws://localhost:\(port)/ws)")

		try await withThrowingDiscardingTaskGroup { group in
			group.addTask {
				// maintenance: keep the session store, router registry, and
				// throttle windows bounded for the life of the process.
				while !Task.isCancelled {
					do { try await Task.sleep(for: .seconds(60)) } catch { break }
					await example.runMaintenance()
				}
			}
			try await channel.executeThenClose { inbound in
				for try await negotiationFuture in inbound {
					group.addTask {
						await example.handle(negotiationFuture)
					}
				}
			}
		}

		try await group.shutdownGracefully()
		argonPool.shutdownGracefully { _ in }
	}

	func handle(_ negotiationFuture: EventLoopFuture<AuthUpgradeResult>) async {
		do {
			switch try await negotiationFuture.get() {
			case .websocket(let ws, let tokenHash):
				try await handleWebsocket(ws, tokenHash: tokenHash)
			case .http(let http):
				try await handleHTTP(http)
			}
		} catch {
			// connection error or a refused admission (gate failure); ignore.
		}
	}

	/// bounded housekeeping sweep (every 60 s on the maintenance task): expired
	/// sessions are purged from the store, their router entries removed, and
	/// throttle + token-store bookkeeping pruned. a long-lived server must
	/// never accumulate dead sessions or attacker-rotated throttle keys.
	func runMaintenance() async {
		let now = Date()
		_ = (try? await sessionStore.purgeExpired(before: now)) ?? 0
		loginThrottle.prune(before: now)
		loginPageThrottle.prune(before: now)
		await loginTokenStore.prune(now: now.timeIntervalSince1970)
		for hash in routers.allTokenHashes() {
			if !(await sessionExists(hash)) {
				routers.remove(forTokenHash: hash)
			}
		}
	}

	private func sessionExists(_ tokenHash: [UInt8]) async -> Bool {
		guard let session = try? await sessionStore.find(tokenHash: tokenHash) else { return false }
		return !session.isExpired()
	}

	private func handleWebsocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, tokenHash: [UInt8]?) async throws {
		// register before reading so logout teardown can close this socket;
		// unregister when the connection ends (normal close or idle reap).
		var connectionID: Int?
		if let tokenHash {
			connectionID = await connections.register(channel, tokenHash: tokenHash)
		}
		do {
			try await channel.executeThenClose { inbound, outbound in
				try await withThrowingTaskGroup(of: Void.self) { tg in
					tg.addTask {
						for try await frame in inbound {
							switch frame.opcode {
							case .text:
								let payload = String(buffer: frame.unmaskedData)
								await self.dispatch(eventText: payload, tokenHash: tokenHash, outbound: outbound)
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
		} catch {
			// connection error; the unregister below still runs.
		}
		if let tokenHash, let connectionID {
			await connections.unregister(connectionID, tokenHash: tokenHash)
		}
	}

	// the socket carries no identity in its messages — each `event`/`ping`
	// carries the page's render token, which selects the router (a token this
	// session never minted means a stale or foreign page, and is rejected).
	// revocation (logout) and expiry are enforced per event too: the session
	// must still exist and be unexpired in the store, or the client is
	// redirected to /login and the socket closed — an already-open socket has
	// no residual power after logout.
	private func dispatch(eventText payload: String, tokenHash: [UInt8]?, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async {
		do {
			let msg = try WSIncoming(jsonText: payload)
			switch msg {
			case .event(let component, let event, let data, let token):
				guard await sessionIsAlive(tokenHash: tokenHash, outbound: outbound) else { return }
				guard let router = await boundRouter(token: token, tokenHash: tokenHash, outbound: outbound) else { return }
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let updates = await router.handle(eventData)
				guard !updates.isEmpty else { return }
				let out = WSOutgoing.update(fragments: updates)
				try await writeJSON(out, outbound: outbound)
			case .ping(let token):
				// pings keep an idle socket alive — session liveness is
				// enforced here too, so an expired or revoked session's
				// socket cannot ping forever.
				guard await sessionIsAlive(tokenHash: tokenHash, outbound: outbound) else { return }
				guard await boundRouter(token: token, tokenHash: tokenHash, outbound: outbound) != nil else { return }
				try await writeJSON(WSOutgoing.pong, outbound: outbound)
			case .navigate:
				break
			}
		} catch {
			let err = WSOutgoing.error(code: "decode", message: "bad event: \(error)")
			try? await writeJSON(err, outbound: outbound)
		}
	}

	/// the router for a message presenting `token` on a session's socket, or
	/// `nil` when the token is absent or unknown to this session — answered
	/// with a redirect to /login and the socket closed. this is the
	/// cross-session replay gate: a stale page from another (or a former)
	/// session's render can never present a token this session minted.
	private func boundRouter(token: String?, tokenHash: [UInt8]?, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async -> EventRouter? {
		guard let tokenHash, let token,
		      let router = routers.router(forTokenHash: tokenHash, renderToken: token) else {
			try? await writeJSON(WSOutgoing.redirect(url: "/login", replace: true), outbound: outbound)
			try? await writeClose(outbound: outbound)
			return nil
		}
		return router
	}

	/// `true` when the session behind `tokenHash` still exists and is
	/// unexpired. when it is not, the client is redirected to `/login` and the
	/// socket closed — revocation is enforced on the next interaction, and
	/// this backstop runs for events and pings alike.
	private func sessionIsAlive(tokenHash: [UInt8]?, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async -> Bool {
		if let tokenHash {
			let session = try? await sessionStore.find(tokenHash: tokenHash)
			guard session != nil, !(session?.isExpired() ?? true) else {
				try? await writeJSON(WSOutgoing.redirect(url: "/login", replace: true), outbound: outbound)
				try? await writeClose(outbound: outbound)
				return false
			}
		}
		return true
	}

	private func writeClose(outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		var buf = ByteBuffer()
		buf.writeInteger(UInt16(1000))
		let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: buf)
		try await outbound.write(close)
	}

	private func writeJSON(_ msg: WSOutgoing, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		let bytes = msg.jsonBytes
		var buf = ByteBuffer()
		buf.writeBytes(bytes)
		let frame = WebSocketFrame(fin: true, opcode: .text, data: buf)
		try await outbound.write(frame)
	}

	// MARK: HTTP

	private func handleHTTP(_ channel: NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		try await channel.executeThenClose { inbound, outbound in
			var requestHead: HTTPRequestHead?
			var bodyBytes: [UInt8] = []
			var bodyTooLarge = false
			for try await part in inbound {
				switch part {
				case .head(let head):
					requestHead = head
				case .body(let buffer):
					guard !bodyTooLarge else { continue }
					var buffer = buffer
					if let b = buffer.readBytes(length: buffer.readableBytes) {
						bodyBytes.append(contentsOf: b)
						if bodyBytes.count > Self.maxBodyBytes {
							bodyTooLarge = true
							bodyBytes = []
						}
					}
				case .end:
					guard let head = requestHead else { return }
					if bodyTooLarge {
						try await loginResponse(channel: channel.channel, status: .payloadTooLarge, headers: [], body: "request body too large")
					} else {
						let peerIP = channel.channel.remoteAddress?.ipAddress ?? "unknown"
						try await self.route(head: head, body: bodyBytes, peerIP: peerIP, channel: channel.channel)
					}
					return
				}
			}
		}
	}

	private func route(head: HTTPRequestHead, body: [UInt8], peerIP: String, channel: Channel) async throws {
		// assets are public (the design system css + js runtime)
		switch (head.method, head.uri) {
		case (.GET, "/__assets/css"):
			// the minified sheet — the raw working file carries designer
			// comments (the first law) and ~6% more bytes on the wire.
			try await loginResponse(channel: channel, status: .ok, headers: [("Content-Type", "text/css; charset=utf-8")], body: DesignSystemAssets.minifiedCss)
			return
		case (.GET, "/__assets/js"):
			try await loginResponse(channel: channel, status: .ok, headers: [("Content-Type", "text/javascript; charset=utf-8")], body: WebUIAssets.js)
			return
		default:
			break
		}

		switch (head.method, head.uri) {
		case (.GET, "/login"):
			// the mint page is throttled (separate, more generous budget) and
			// every issued token is reserved under the caller's outstanding
			// budget, so one ip cannot stockpile tokens and later flood the
			// single-use store past capacity, locking out other logins.
			let ipKey = "ip:\(peerIP)"
			guard loginPageThrottle.record(ipKey) else {
				return try await loginResponse(channel: channel, status: .tooManyRequests, headers: [("Retry-After", "60")], body: "too many login pages — try again later")
			}
			let token = try CSRFProtection.token(for: "login", secret: csrfSecret)
			guard await loginTokenStore.reserve(token, expiresAt: CSRFProtection.expiry(of: token) ?? Date().timeIntervalSince1970, key: ipKey) else {
				return try await loginResponse(channel: channel, status: .tooManyRequests, headers: [("Retry-After", "60")], body: "too many outstanding login forms — submit one first")
			}
			try await loginResponse(channel: channel, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: renderLoginPage(error: nil, csrfToken: token))
		case (.POST, "/login"):
			try await handleLogin(head: head, body: body, peerIP: peerIP, channel: channel)
		case (.POST, "/logout"):
			try await handleLogout(head: head, body: body, channel: channel)
		case (.GET, "/logout"):
			// logout is POST-only (CSRF-protected); a plain GET is a CSRF
			// vector, so it gets no treatment.
			try await loginResponse(channel: channel, status: .methodNotAllowed, headers: [], body: "")
		case (.GET, "/"):
			try await handleIndex(head: head, channel: channel)
		case (_, "/ws"):
			// the upgrade path handles this; reaching here means no upgrade.
			try await loginResponse(channel: channel, status: .notFound, headers: [], body: "not found")
		default:
			try await loginResponse(channel: channel, status: .notFound, headers: [], body: "not found")
		}
	}

	private func handleLogin(head: HTTPRequestHead, body: [UInt8], peerIP: String, channel: Channel) async throws {
		func failure(_ message: String) async throws {
			let token = try CSRFProtection.token(for: "login", secret: csrfSecret)
			try await loginResponse(channel: channel, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: renderLoginPage(error: message, csrfToken: token))
		}
		func tooMany(_ message: String) async throws {
			try await loginResponse(channel: channel, status: .tooManyRequests, headers: [("Retry-After", "60")], body: message)
		}

		// the only accepted encoding is the browser's urlencoded form POST.
		guard let contentType = head.headers.first(name: "content-type")?.lowercased(),
		      contentType.hasPrefix("application/x-www-form-urlencoded") else {
			try await loginResponse(channel: channel, status: .unsupportedMediaType, headers: [], body: "expected application/x-www-form-urlencoded")
			return
		}

		let bodyText = String(decoding: body, as: UTF8.self)
		guard let fields = try? URLEncodedForm.parse(bodyText),
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "login", secret: csrfSecret) else {
			return try await failure("invalid or expired form token — try again")
		}
		let username = fields["username"] ?? ""
		let password = fields["password"] ?? ""

		// single-use login tokens: the stateless HMAC token may only be
		// submitted once. a replayed or scraped token is rejected here, before
		// any KDF work is spent. consume also releases the issuer's outstanding
		// budget (keyed by the ip the token was reserved under).
		let ipKey = "ip:\(peerIP)"
		guard await loginTokenStore.consume(csrf, expiresAt: CSRFProtection.expiry(of: csrf) ?? Date().timeIntervalSince1970, key: ipKey) else {
			return try await failure("invalid or expired form token — try again")
		}

		// per-IP + per-account throttles key on the socket peer (no trusted
		// proxy is configured, so X-Forwarded-For is never honored here).
		guard loginThrottle.record(ipKey) else {
			return try await tooMany("too many attempts — try again later")
		}
		let userKey = "user:\(username.lowercased())"
		guard loginThrottle.record(userKey) else {
			return try await tooMany("too many attempts — try again later")
		}

		// username + password verification: constant-time username compare and
		// Argon2id verification against the precomputed demo record. the KDF is
		// the one-box DoS amplifier on a public endpoint, so it runs under a
		// global concurrency cap AND on a dedicated thread pool — a ~100-300 ms
		// synchronous hash must never stall the event loop every connection on
		// it shares (worst on a 4-core pi).
		let userMatches = constantTimeEquals([UInt8](username.utf8), [UInt8](Self.demoUsername.utf8))
		let passwordValid: Bool
		if userMatches {
			await argon2Limiter.wait()
			defer { argon2Limiter.signal() }
			passwordValid = try await argonPool.runIfActive {
				try PasswordVerifier.verify(password: [UInt8](password.utf8), record: adminPasswordRecord)
			}
		} else {
			// dummy-hash discipline: burn the same cost as a real verify so the
			// timing of "unknown user" equals "wrong password".
			await argon2Limiter.wait()
			defer { argon2Limiter.signal() }
			_ = try await argonPool.runIfActive {
				try PasswordVerifier.verify(password: [UInt8](password.utf8), record: adminPasswordRecord)
			}
			passwordValid = false
		}
		guard userMatches, passwordValid else {
			return try await failure("invalid credentials")
		}
		loginThrottle.reset(userKey)

		// establish the session: fresh token, hash-at-rest, in-memory store.
		let token = try SessionToken.generate()
		// the session id and csrf seed are entropy-minted like the token: a
		// silent `?? []` fallback would let two sessions collide on an empty id.
		guard let sessionID = SecureRandom.bytes(16),
		      let sessionSeed = SecureRandom.bytes(16) else {
			throw SessionToken.TokenError.entropyUnavailable
		}
		let session = AuthenticatedSession(
			id: sessionID,
			tokenHash: try SessionToken.hash(token),
			identityID: Self.demoUsername,
			csrfSeed: sessionSeed,
			createdAt: Date(),
			expiresAt: Date().addingTimeInterval(TimeInterval(DemoSession.maxAgeSeconds)),
			lastSeenAt: Date()
		)
		try await sessionStore.create(session)

		let cookie = try HTTPCookie(
			name: DemoSession.cookieName,
			value: Base64.encode(token),
			attributes: .init(maxAge: DemoSession.maxAgeSeconds, path: "/", httpOnly: true, sameSite: .lax)
		).setCookieHeaderValue()
		try await redirect(channel: channel, to: "/", setCookies: [("Set-Cookie", cookie)])
	}

	private func handleLogout(head: HTTPRequestHead, body: [UInt8], channel: Channel) async throws {
		// CSRF-protected POST logout: the token comes from the per-render
		// logout form on the dashboard (plan M2-T4 spirit).
		let bodyText = String(decoding: body, as: UTF8.self)
		guard let fields = try? URLEncodedForm.parse(bodyText),
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "logout", secret: csrfSecret) else {
			try await loginResponse(channel: channel, status: .forbidden, headers: [], body: "invalid or expired form token")
			return
		}

		var clearCookie: String?
		if let cookieHeader = head.headers.first(name: "cookie"),
		   let token = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName],
		   let tokenHash = try? SessionToken.hash(Self.decodeCookieToken(token)) {
			if let session = try? await sessionStore.find(tokenHash: tokenHash) {
				try? await sessionStore.invalidate(id: session.id)
				routers.remove(forTokenHash: tokenHash)
				// teardown: close every live socket bound to this session now,
				// not on the next client event. the per-event liveness check
				// remains as the backstop for sockets opened during the race.
				await connections.closeAll(forTokenHash: tokenHash)
			}
			clearCookie = try HTTPCookie(
				name: DemoSession.cookieName,
				value: "",
				attributes: .init(maxAge: 0, path: "/", httpOnly: true, sameSite: .lax)
			).setCookieHeaderValue()
		}
		var cookies: [(String, String)] = []
		if let clearCookie {
			cookies.append(("Set-Cookie", clearCookie))
		}
		try await redirect(channel: channel, to: "/login", setCookies: cookies)
	}

	private func handleIndex(head: HTTPRequestHead, channel: Channel) async throws {
		guard let (session, token) = await sessionDescription(for: head) else {
			try await redirect(channel: channel, to: "/login")
			return
		}
		let identity = Identity(id: session.identityID, roles: [Role.member, Role.admin])
		let auth = AuthContext(session: session, identity: identity)
		let logoutToken = try CSRFProtection.token(for: "logout", secret: csrfSecret)
		// a fresh render token per full page render: only pages minted for this
		// session can drive its sockets. entropy failure is fatal (fail loud).
		guard let renderTokenBytes = SecureRandom.bytes(16) else {
			throw SessionToken.TokenError.entropyUnavailable
		}
		let renderToken = Base64.encodeURL(renderTokenBytes)
		let (html, router) = renderDashboard(state: state, auth: auth, logoutToken: logoutToken, renderToken: renderToken)
		routers.set(router, forTokenHash: try SessionToken.hash(token), renderToken: renderToken)
		try await loginResponse(channel: channel, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: html)
	}
}

enum AuthUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, tokenHash: [UInt8]?)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}
