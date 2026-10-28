import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Synchronization
import Testing
import WebUI
import WebUIServer

// the two hosting seams, consulted — the half stage 0 only declared.
//
// stage 0 gave `WebUIServerConfig` an `authorizer` and a `socketObserver` and
// nothing read them. these tests are the proof that the server asks: a page
// route carries the principal the authorizer answered, an unconfigured server
// carries none and serves exactly as before, and a socket announces one open
// and one close to the observer — never for a connection that did not upgrade.
//
// the doubles are deliberately the shape a host writes: the authorizer resolves
// a cookie, the observer records liveness. nothing here names `WebUIAuth`.

// MARK: - doubles

/// what a seam double saw, in order.
private final class SeamLog: Sendable {
	enum Entry: Sendable, Equatable {
		case authorized(path: String)
		case opened(SessionKey)
		case closed(SessionKey)
	}

	private let entries = Mutex<[Entry]>([])

	func record(_ entry: Entry) {
		entries.withLock { $0.append(entry) }
	}

	var recorded: [Entry] {
		entries.withLock { $0 }
	}

	/// the lifecycle calls only, in order: the observer's own transcript.
	var announcements: [Entry] {
		recorded.filter {
			switch $0 {
			case .authorized: return false
			case .opened, .closed: return true
			}
		}
	}

	/// block until `count` announcements have landed, or the timeout passes.
	///
	/// a socket closing is asynchronous by nature, so the assertion waits for
	/// the event it is about rather than sleeping a fixed time and hoping.
	func waitAnnouncements(count: Int, timeout: Duration = .seconds(5)) async -> [Entry] {
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			let seen = announcements
			if seen.count >= count { return seen }
			try? await Task.sleep(for: .milliseconds(20))
		}
		return announcements
	}
}

/// resolves `sid=<name>` from the request's cookie header — a host authorizer
/// minus the store — and writes down every path it was asked about.
private struct CookieAuthorizer: RequestAuthorizer {
	let sessions: [String: SessionKey]
	let log: SeamLog

	func authorize(_ request: HTTPRequest) async -> SessionKey? {
		log.record(.authorized(path: request.path))
		guard let header = request.headers.first(name: "Cookie") else { return nil }
		for pair in header.split(separator: ";") {
			let field = pair.trimmingCharacters(in: .whitespaces)
			guard field.hasPrefix("sid=") else { continue }
			return sessions[String(field.dropFirst(4))]
		}
		return nil
	}
}

/// an observer that writes down what it was told, in order.
private struct LoggingObserver: SocketLifecycleObserver {
	let log: SeamLog

	func socketOpened(session: SessionKey, connection: UInt64, close: @escaping @Sendable () -> Void) async {
		log.record(.opened(session))
	}
	func socketClosed(session: SessionKey, connection: UInt64) async { log.record(.closed(session)) }
}

// MARK: - wire helpers

/// the wire spelling of a session key, so a response can carry it.
private func label(_ key: SessionKey) -> String {
	key.hash.map { String(format: "%02x", $0) }.joined(separator: "-")
}

/// a route that answers the principal it was handed: the responder's whole
/// view of identity, and the only thing these tests read off the page.
private func principalPage(_ request: HTTPRequest) -> HTTPResponse {
	HTTPResponse(body: .text(request.principal.map(label) ?? "none"))
}

/// a GET that carries a cookie header.
///
/// `URLSession` owns cookie storage and may rewrite or drop a manually set
/// `Cookie`, so the session is configured not to touch cookies at all: the
/// header the server sees is the header this test set.
private func cookieGET(_ url: String, sid: String?) async throws -> (String, Int) {
	guard let urlValue = URL(string: url) else {
		Issue.record("bad url in cookieGET: \(url)")
		return ("", 0)
	}
	var request = URLRequest(url: urlValue)
	request.timeoutInterval = 5
	let configuration = URLSessionConfiguration.ephemeral
	configuration.httpShouldSetCookies = false
	configuration.httpCookieStorage = nil
	if let sid { request.setValue("sid=\(sid)", forHTTPHeaderField: "Cookie") }
	let (data, response) = try await URLSession(configuration: configuration).data(for: request)
	return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// one GET carrying real websocket upgrade headers, through curl.
///
/// `URLSession` reserves the hop-by-hop headers and would not let the test send
/// `Connection`/`Upgrade`, so the refused-upgrade path is driven by the one
/// instrument that will.
///
/// a refused upgrade is currently left unanswered by the server (measured: curl
/// exits 28, its operation timeout, because the head is forwarded after the
/// upgrade handler has removed itself and nothing in that path answers it), so
/// the cap below is what keeps the attempt bounded. this helper asserts nothing
/// about the answer: the claim under test is the observer's silence.
@discardableResult
private func upgradeAttempt(_ url: String) throws -> Int32 {
	guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else {
		Issue.record("curl is not available — a refused upgrade cannot be driven")
		return -1
	}
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
	process.arguments = [
		"-s", "-m", "1", "-o", "/dev/null",
		"-H", "Connection: Upgrade",
		"-H", "Upgrade: websocket",
		"-H", "Sec-WebSocket-Version: 13",
		"-H", "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
		url,
	]
	process.standardOutput = Pipe()
	process.standardError = Pipe()
	try process.run()
	process.waitUntilExit()
	return process.terminationStatus
}

#if !os(Linux)
/// a websocket task that presents `sid` on the upgrade request, the way a
/// browser presents the cookie its page was rendered under.
private func openSocket(port: Int, sid: String) -> URLSessionWebSocketTask {
	var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/ws")!)
	request.setValue("sid=\(sid)", forHTTPHeaderField: "Cookie")
	let configuration = URLSessionConfiguration.ephemeral
	configuration.httpShouldSetCookies = false
	configuration.httpCookieStorage = nil
	let socket = URLSession(configuration: configuration).webSocketTask(with: request)
	socket.resume()
	return socket
}
#endif

// MARK: - the suite

@Suite("hosting seams — consulted", .serialized)
struct WireSeamTests {
	private let key = SessionKey(hash: [0xAB, 0xCD])

	/// the routes every case serves: `/` is what the harness probes with, and
	/// `/app` is the page a request for identity reads.
	private func routes() -> Router {
		Router {
			Route.get("/") { principalPage($0) }
			Route.get("/app") { principalPage($0) }
		}
	}

	@Test("a page route carries the principal the authorizer answered")
	func pageRouteStampsPrincipal() async throws {
		let log = SeamLog()
		let configuration = WebUIServerConfig(
			authorizer: CookieAuthorizer(sessions: ["alpha": key], log: log)
		)
		try await withRouterServer(routes(), portBase: 49_000, config: configuration) { port in
			let (body, status) = try await cookieGET("http://127.0.0.1:\(port)/app", sid: "alpha")
			#expect(status == 200)
			#expect(body == label(key), "the responder must see the principal the authorizer answered")
			#expect(log.recorded.contains(.authorized(path: "/app")))
		}
	}

	@Test("a request that presents no session is served with no principal")
	func anonymousRequestHasNoPrincipal() async throws {
		let log = SeamLog()
		let configuration = WebUIServerConfig(
			authorizer: CookieAuthorizer(sessions: ["alpha": key], log: log)
		)
		try await withRouterServer(routes(), portBase: 49_050, config: configuration) { port in
			let (body, status) = try await cookieGET("http://127.0.0.1:\(port)/app", sid: nil)
			#expect(status == 200)
			#expect(body == "none")
			#expect(log.recorded.contains(.authorized(path: "/app")))
		}
	}

	@Test("with no authorizer the principal is nil and the page still serves")
	func noAuthorizerLeavesPrincipalNil() async throws {
		try await withRouterServer(routes(), portBase: 49_100) { port in
			let (body, status) = try await cookieGET("http://127.0.0.1:\(port)/app", sid: "alpha")
			#expect(status == 200)
			#expect(body == "none", "an unconfigured server must not invent a session")
		}
	}

	#if !os(Linux)
	@Test("a socket is announced once on open and once on close, in that order")
	func socketAnnouncesOnce() async throws {
		let log = SeamLog()
		let configuration = WebUIServerConfig(
			authorizer: CookieAuthorizer(sessions: ["alpha": key], log: log),
			socketObserver: LoggingObserver(log: log)
		)
		try await withRouterServer(routes(), portBase: 49_200, config: configuration) { port in
			let socket = openSocket(port: port, sid: "alpha")
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			let opened = await log.waitAnnouncements(count: 1)
			#expect(opened == [.opened(key)], "the open must arrive once, before any frame")
			#expect(!opened.contains(.closed(key)))

			socket.cancel(with: .normalClosure, reason: nil)
			let ended = await log.waitAnnouncements(count: 2)
			#expect(
				ended == [.opened(key), .closed(key)],
				"exactly one open then one close, in that order: got \(ended)"
			)
		}
	}

	@Test("a connection that never upgrades is never announced")
	func refusedConnectionIsNotAnnounced() async throws {
		let log = SeamLog()
		let configuration = WebUIServerConfig(
			authorizer: CookieAuthorizer(sessions: ["alpha": key], log: log),
			socketObserver: LoggingObserver(log: log)
		)
		try await withRouterServer(routes(), portBase: 49_300, config: configuration) { port in
			// two ways to fail before a socket exists: a bare GET to the
			// upgrade path (nio never consults an upgrader without an
			// `upgrade` header), and a real upgrade attempt for a path the
			// upgrader refuses.
			_ = try? await cookieGET("http://127.0.0.1:\(port)/ws", sid: "alpha")
			try upgradeAttempt("http://127.0.0.1:\(port)/not-a-socket")
			#expect(log.announcements.isEmpty, "a connection that fails before upgrading owns no session")

			// positive control: the observer does speak for a socket that
			// upgrades, so the emptiness above is the refusal and not a seam
			// nobody calls.
			let socket = openSocket(port: port, sid: "alpha")
			defer { socket.cancel(with: .normalClosure, reason: nil) }
			let opened = await log.waitAnnouncements(count: 1)
			#expect(opened == [.opened(key)])

			socket.cancel(with: .normalClosure, reason: nil)
			let ended = await log.waitAnnouncements(count: 2)
			#expect(ended == [.opened(key), .closed(key)])
		}
	}
	#endif
}
