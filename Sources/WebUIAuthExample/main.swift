import Foundation
import Logging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import WebUI
import WebUIDesignSystem
import WebUIAuth

// MARK: - Session registry (per-session interactive routers)

// maps a session's token hash to the EventRouter of the last full render of
// its dashboard page. replaced on every GET / re-render (one router per render
// pass). reference-backed so the demo struct stays immutable across the async
// server loop while the map mutates safely.
final class RouterRegistry: @unchecked Sendable {
	private let lock = NSLock()
	private var routers: [Data: EventRouter] = [:]

	func router(forTokenHash hash: Data) -> EventRouter? {
		lock.lock(); defer { lock.unlock() }
		return routers[hash]
	}
	func set(_ router: EventRouter, forTokenHash hash: Data) {
		lock.lock(); defer { lock.unlock() }
		routers[hash] = router
	}
	func remove(forTokenHash hash: Data) {
		lock.lock(); defer { lock.unlock() }
		routers.removeValue(forKey: hash)
	}
}

// MARK: - Demo state (per-process interactive model, like WebUIExample)

final class AuthDemoState: @unchecked Sendable {
	private let lock = NSLock()
	private var _count: Int = 0
	private var _progress: Double = 0.25
	private var _echo: String = ""

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
func renderDashboard(state: AuthDemoState, auth: AuthContext, logoutToken: String) -> (html: String, router: EventRouter) {
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
	let document = WebUIDocument(title: "Member Dashboard", body: html).render()
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

struct WebUIAuthExample {
	// demo credentials (trivial by design — this is the demonstration login)
	static let demoUsername = "admin"
	static let demoPassword = "password"

	let state: AuthDemoState
	let sessionStore: InMemoryAuthSessionStore
	let csrfSecret: String
	let adminPasswordRecord: PasswordRecord
	let routers = RouterRegistry()

	// uploads beyond this are rejected with 413 — the demo accepts only tiny
	// urlencoded forms.
	static let maxBodyBytes = 16 * 1024

	// MARK: auth helpers

	func sessionDescription(for request: HTTPRequestHead) async -> (session: AuthenticatedSession, token: Data)? {
		guard let cookieHeader = request.headers.first(name: "cookie"),
		      let cookieValue = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName] else {
			return nil
		}
		let tokenData = Self.decodeCookieToken(cookieValue)
		guard let tokenHash = try? SessionToken.hash(tokenData) else { return nil }
		guard let session = try? await sessionStore.find(tokenHash: tokenHash),
		      !session.isExpired() else {
			return nil
		}
		return (session, tokenData)
	}

	func tokenHash(for request: HTTPRequestHead) -> Data? {
		guard let cookieHeader = request.headers.first(name: "cookie"),
		      let cookieValue = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName] else {
			return nil
		}
		return try? SessionToken.hash(Self.decodeCookieToken(cookieValue))
	}

	static func decodeCookieToken(_ token: String) -> Data {
		// sessions are minted as base64 of the raw 32-byte token; only that
		// form is accepted (no utf8 fallback — the encoding is unambiguous).
		Data(base64Encoded: token) ?? Data()
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

	func loginResponse(outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>, status: HTTPResponseStatus, headers: [(String, String)], body: String) async throws {
		var head = HTTPResponseHead(version: .http1_1, status: status)
		// clickjacking control — X-Frame-Options is header-only (the
		// frame-ancestors CSP directive is inert in a <meta> element).
		head.headers.replaceOrAdd(name: "X-Frame-Options", value: "SAMEORIGIN")
		for (name, value) in headers {
			head.headers.replaceOrAdd(name: name, value: value)
		}
		head.headers.replaceOrAdd(name: "Content-Length", value: "\(body.utf8.count)")
		head.headers.replaceOrAdd(name: "Connection", value: "close")
		var buf = ByteBuffer()
		buf.writeString(body)
		try await outbound.write(contentsOf: [.head(head), .body(buf), .end(nil)])
	}

	func redirect(outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>, to target: String, setCookies: [(String, String)] = []) async throws {
		var setCookieHeaders = setCookies
		setCookieHeaders.insert(("Location", target), at: 0)
		try await loginResponse(outbound: outbound, status: .seeOther, headers: setCookieHeaders, body: "")
	}

	// MARK: server

	static func main() async throws {
		let csrfSecret = CSRFProtection.generateSecret()
		let passwordRecord = PasswordRecord(
			salt: try PasswordVerifier.makeSalt(),
			hash: Data(),
			parameters: .interactive
		)
		let hash = try PasswordVerifier.hash(
			password: [UInt8](demoPassword.utf8),
			salt: [UInt8](passwordRecord.salt),
			parameters: .interactive
		)
		let record = PasswordRecord(salt: passwordRecord.salt, hash: hash, parameters: .interactive)

		let example = WebUIAuthExample(
			state: AuthDemoState(),
			sessionStore: InMemoryAuthSessionStore(),
			csrfSecret: csrfSecret,
			adminPasswordRecord: record
		)

		let logger = Logger(label: "webui.auth.example")
		logger.info("auth demo ready — sign in with '\(demoUsername)' / '\(demoPassword)'")

		let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 128)
			.serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

		let channel: NIOAsyncChannel<EventLoopFuture<AuthUpgradeResult>, Never> = try await bootstrap.bind(
			host: "0.0.0.0", port: 9091
		) { channel in
			channel.eventLoop.makeCompletedFuture {
				let upgrader = NIOTypedWebSocketServerUpgrader<AuthUpgradeResult>(
					shouldUpgrade: { channel, head in
						// the demo binds the socket to the page's per-session
						// router at upgrade time (cookie -> token hash -> router
						// registered by the last full render) and refuses
						// foreign origins. an unauthenticated or foreign-origin
						// upgrade is not upgraded (falls through to HTTP 404),
						// so pre-login / cross-site sockets are inert.
						let ok = head.method == .GET
							&& head.uri == "/ws"
							&& example.originMatchesHost(head: head)
						return channel.eventLoop.makeSucceededFuture(ok ? HTTPHeaders() : nil)
					},
						upgradePipelineHandler: { channel, head in
						channel.eventLoop.makeCompletedFuture {
							let ws = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(wrappingChannelSynchronously: channel)
							let tokenHash = example.tokenHash(for: head)
							let router = tokenHash.flatMap { example.routers.router(forTokenHash: $0) }
							return AuthUpgradeResult.websocket(ws, router: router, tokenHash: tokenHash)
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

		logger.info("auth demo on http://localhost:9091 (ws://localhost:9091/ws)")

		try await withThrowingDiscardingTaskGroup { group in
			try await channel.executeThenClose { inbound in
				for try await negotiationFuture in inbound {
					group.addTask {
						await example.handle(negotiationFuture)
					}
				}
			}
		}

		try await group.shutdownGracefully()
	}

	func handle(_ negotiationFuture: EventLoopFuture<AuthUpgradeResult>) async {
		do {
			switch try await negotiationFuture.get() {
			case .websocket(let ws, let router, let tokenHash):
				try await handleWebsocket(ws, router: router, tokenHash: tokenHash)
			case .http(let http):
				try await handleHTTP(http)
			}
		} catch {
			// connection error; ignore
		}
	}

	private func handleWebsocket(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, router: EventRouter?, tokenHash: Data?) async throws {
		try await channel.executeThenClose { inbound, outbound in
			try await withThrowingTaskGroup(of: Void.self) { tg in
				tg.addTask {
					for try await frame in inbound {
						switch frame.opcode {
						case .text:
							let payload = String(buffer: frame.unmaskedData)
							await self.dispatch(eventText: payload, router: router, tokenHash: tokenHash, outbound: outbound)
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

	// the socket carries no identity in its messages — the per-session router
	// bound at upgrade is the dispatch target (per-render router for the last
	// full page render of that session). revocation (logout) and expiry are
	// enforced **per event**: the session must still exist and be unexpired in
	// the store, or the client is redirected to /login and the socket closed —
	// an already-open socket has no residual power after logout.
	private func dispatch(eventText payload: String, router: EventRouter?, tokenHash: Data?, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async {
		guard let data = payload.data(using: .utf8) else { return }
		do {
			let msg = try JSONDecoder().decode(WSIncoming.self, from: data)
			switch msg {
			case .event(let component, let event, let data):
				if let tokenHash {
					let session = try? await sessionStore.find(tokenHash: tokenHash)
					guard session != nil, !(session?.isExpired() ?? true) else {
						try? await writeJSON(WSOutgoing.redirect(url: "/login", replace: true), outbound: outbound)
						try? await writeClose(outbound: outbound)
						return
					}
				}
				guard let router else { return }
				let eventData = EventData(component: ComponentID(component), event: event, data: data)
				let updates = await router.handle(eventData)
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

	private func writeClose(outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		var buf = ByteBuffer()
		buf.writeInteger(UInt16(1000))
		let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: buf)
		try await outbound.write(close)
	}

	private func writeJSON(_ msg: WSOutgoing, outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>) async throws {
		let data = try JSONEncoder().encode(msg)
		var buf = ByteBuffer()
		buf.writeBytes(data)
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
						try await loginResponse(outbound: outbound, status: .payloadTooLarge, headers: [], body: "request body too large")
					} else {
						try await self.route(head: head, body: Data(bodyBytes), outbound: outbound)
					}
					return
				}
			}
		}
	}

	private func route(head: HTTPRequestHead, body: Data, outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		// assets are public (the design system css + js runtime)
		switch (head.method, head.uri) {
		case (.GET, "/__assets/css"):
			try await loginResponse(outbound: outbound, status: .ok, headers: [("Content-Type", "text/css; charset=utf-8")], body: WebUIAssets.css)
			return
		case (.GET, "/__assets/js"):
			try await loginResponse(outbound: outbound, status: .ok, headers: [("Content-Type", "text/javascript; charset=utf-8")], body: WebUIAssets.js)
			return
		default:
			break
		}

		switch (head.method, head.uri) {
		case (.GET, "/login"):
			let token = CSRFProtection.token(for: "login", secret: csrfSecret)
			try await loginResponse(outbound: outbound, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: renderLoginPage(error: nil, csrfToken: token))
		case (.POST, "/login"):
			try await handleLogin(head: head, body: body, outbound: outbound)
		case (.POST, "/logout"):
			try await handleLogout(head: head, body: body, outbound: outbound)
		case (.GET, "/logout"):
			// logout is POST-only (CSRF-protected); a plain GET is a CSRF
			// vector, so it gets no treatment.
			try await loginResponse(outbound: outbound, status: .methodNotAllowed, headers: [], body: "")
		case (.GET, "/"):
			try await handleIndex(head: head, outbound: outbound)
		case (_, "/ws"):
			// the upgrade path handles this; reaching here means no upgrade.
			try await loginResponse(outbound: outbound, status: .notFound, headers: [], body: "not found")
		default:
			try await loginResponse(outbound: outbound, status: .notFound, headers: [], body: "not found")
		}
	}

	private func handleLogin(head: HTTPRequestHead, body: Data, outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		func failure(_ message: String) async throws {
			let token = CSRFProtection.token(for: "login", secret: csrfSecret)
			try await loginResponse(outbound: outbound, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: renderLoginPage(error: message, csrfToken: token))
		}

		// the only accepted encoding is the browser's urlencoded form POST.
		guard let contentType = head.headers.first(name: "content-type")?.lowercased(),
		      contentType.hasPrefix("application/x-www-form-urlencoded") else {
			try await loginResponse(outbound: outbound, status: .unsupportedMediaType, headers: [], body: "expected application/x-www-form-urlencoded")
			return
		}

		guard let bodyText = String(data: body, encoding: .utf8),
		      let fields = try? URLEncodedForm.parse(bodyText),
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "login", secret: csrfSecret) else {
			return try await failure("invalid or expired form token — try again")
		}
		let username = fields["username"] ?? ""
		let password = fields["password"] ?? ""

		// username + password verification: constant-time username compare and
		// Argon2id verification against the precomputed demo record.
		let userMatches = constantTimeEquals([UInt8](username.utf8), [UInt8](Self.demoUsername.utf8))
		let passwordValid: Bool
		if userMatches {
			passwordValid = try PasswordVerifier.verify(password: [UInt8](password.utf8), record: adminPasswordRecord)
		} else {
			// dummy-hash discipline: burn the same cost as a real verify so the
			// timing of "unknown user" equals "wrong password".
			_ = try PasswordVerifier.verify(password: [UInt8](password.utf8), record: adminPasswordRecord)
			passwordValid = false
		}
		guard userMatches, passwordValid else {
			return try await failure("invalid credentials")
		}

		// establish the session: fresh token, hash-at-rest, in-memory store.
		let token = try SessionToken.generate()
		let session = AuthenticatedSession(
			id: Data(SecureRandom.bytes(16) ?? []),
			tokenHash: try SessionToken.hash(token),
			identityID: Self.demoUsername,
			csrfSeed: Data(SecureRandom.bytes(16) ?? []),
			createdAt: Date(),
			expiresAt: Date().addingTimeInterval(TimeInterval(DemoSession.maxAgeSeconds)),
			lastSeenAt: Date()
		)
		try await sessionStore.create(session)

		let cookie = try HTTPCookie(
			name: DemoSession.cookieName,
			value: token.base64EncodedString(),
			attributes: .init(maxAge: DemoSession.maxAgeSeconds, path: "/", httpOnly: true, sameSite: .lax)
		).setCookieHeaderValue()
		try await redirect(outbound: outbound, to: "/", setCookies: [("Set-Cookie", cookie)])
	}

	private func handleLogout(head: HTTPRequestHead, body: Data, outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		// CSRF-protected POST logout: the token comes from the per-render
		// logout form on the dashboard (plan M2-T4 spirit).
		guard let bodyText = String(data: body, encoding: .utf8),
		      let fields = try? URLEncodedForm.parse(bodyText),
		      let csrf = fields["_csrf"],
		      CSRFProtection.validate(csrf, for: "logout", secret: csrfSecret) else {
			try await loginResponse(outbound: outbound, status: .forbidden, headers: [], body: "invalid or expired form token")
			return
		}

		var clearCookie: String?
		if let cookieHeader = head.headers.first(name: "cookie"),
		   let token = CookieParser.requestCookies(cookieHeader)[DemoSession.cookieName],
		   let tokenHash = try? SessionToken.hash(Self.decodeCookieToken(token)) {
			if let session = try? await sessionStore.find(tokenHash: tokenHash) {
				try? await sessionStore.invalidate(id: session.id)
				routers.remove(forTokenHash: tokenHash)
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
		try await redirect(outbound: outbound, to: "/login", setCookies: cookies)
	}

	private func handleIndex(head: HTTPRequestHead, outbound: NIOAsyncChannelOutboundWriter<HTTPPart<HTTPResponseHead, ByteBuffer>>) async throws {
		guard let (session, token) = await sessionDescription(for: head) else {
			try await redirect(outbound: outbound, to: "/login")
			return
		}
		let identity = Identity(id: session.identityID, roles: [Role.member, Role.admin])
		let auth = AuthContext(session: session, identity: identity)
		let logoutToken = CSRFProtection.token(for: "logout", secret: csrfSecret)
		let (html, router) = renderDashboard(state: state, auth: auth, logoutToken: logoutToken)
		routers.set(router, forTokenHash: try SessionToken.hash(token))
		try await loginResponse(outbound: outbound, status: .ok, headers: [("Content-Type", "text/html; charset=utf-8")], body: html)
	}
}

enum AuthUpgradeResult: Sendable {
	case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>, router: EventRouter?, tokenHash: Data?)
	case http(NIOAsyncChannel<HTTPServerRequestPart, HTTPPart<HTTPResponseHead, ByteBuffer>>)
}

// MARK: - Entry point

try await WebUIAuthExample.main()
