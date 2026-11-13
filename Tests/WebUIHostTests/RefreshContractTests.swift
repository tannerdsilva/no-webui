import Foundation
import Logging
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
import WebUIServer
import WebUIState

// MARK: - S6b: the refresh contract
//
// the decision (§22.2 D2), verbatim in its four pieces: an **intent** on the
// render request, a **policy** with exclusions, a **session-scoped** fan-out,
// and **post-patch restoration** (the engine's afterPatch funnel, unchanged —
// proved here by the probe, not by adding server code).
//
// the outcome carries NO session: `HandlerOutcome.refresh` is applied to the
// session the event was dispatched in, so no value a handler returns can name
// another page. that is what these tests are built around — every page here is
// a real route over a real listener, every socket a real upgrade, and the
// frames are read off the wire.
//
//   (a) two sockets that speak for ONE render token both receive the refresh
//   (b) a socket in a different session receives nothing
//   (c) an excluded region does not ship while a sibling region does
//   (d) the intent door observes `.load`, `.navigate`, `.refresh`
//   (e) the remembered-page map is evicted with the session, bounded by
//       `maxSessions` (plan risk 6)
//   (f) a refresh whose re-render throws answers the session's sockets

#if !os(Linux)

// MARK: - instruments

/// the fixture state one page renders: the count the control moves, a switch
/// that makes the next render throw, and nothing else.
private final class RefreshFixture: Sendable {
	private struct Values {
		var count = 0
		var failNextRender = false
	}

	private let values = Mutex(Values())

	var count: Int { values.withLock { $0.count } }

	func bump() { values.withLock { $0.count += 1 } }

	var failNextRender: Bool {
		get { values.withLock { $0.failNextRender } }
		set { values.withLock { $0.failNextRender = newValue } }
	}

	/// read-and-clear: one render fails, the next one answers.
	func takeFailure() -> Bool {
		values.withLock { values in
			guard values.failNextRender else { return false }
			values.failNextRender = false
			return true
		}
	}
}

/// the throw a failing render raises: a host error, not a trap.
private struct RefreshRenderFailure: Error, CustomStringConvertible {
	var description: String { "the fixture's render failed on purpose" }
}

/// the renders a page route served, in order — the intent door's evidence.
private struct ObservedRender: Sendable, Equatable {
	let intent: RenderIntent
	let path: String
	let token: String
}

private final class RenderLog: Sendable {
	private let entries = Mutex<[ObservedRender]>([])

	func record(_ request: RenderRequest) {
		entries.withLock {
			$0.append(
				ObservedRender(
					intent: request.intent,
					path: request.path,
					token: request.renderToken.value
				)
			)
		}
	}

	var all: [ObservedRender] { entries.withLock { $0 } }
	func reset() { entries.withLock { $0.removeAll() } }
}

// MARK: - the pages

/// one control (`bump`) answering `.refresh`, and regions whose bytes the
/// count moves. `page` names which region carries the count so a test can
/// choose between "one region moved" and "two moved, one excluded".
///
/// the responder re-begins its session exactly as `WebUISmokeTest`'s fixture
/// does — a render pass is the session's, and registration is idempotent.
private struct RefreshCounterPage: Responder {
	let fixture: RefreshFixture
	let router: EventRouter
	/// when set, a second region carrying the same value is rendered beside
	/// the first, so an exclusion can be observed against a live sibling.
	let excludedRegion: String?

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		if fixture.takeFailure() { throw RefreshRenderFailure() }
		let session = RenderSessionID(request.renderToken.value)
		router.begin(session)
		router.register(outcome: { _ in
			fixture.bump()
			return .refresh
		}, for: ComponentID("bump"), in: session)
		// the second session's own answer: a socket that is never reached by a
		// refresh receives THIS as its next frame, which is how isolation is
		// asserted without a timeout (see the note at the top of the file).
		router.register(outcome: { _ in
			.fragments([
				FragmentUpdate(
					id: "local",
					html: "<span id=\"local\">local: \(fixture.count)</span>"
				),
			])
		}, for: ComponentID("local"), in: session)

		let count = fixture.count
		var regions = "<span id=\"counter\" data-component-id=\"counter\">count: \(count)</span>"
		if let excludedRegion {
			regions = "<div id=\"\(excludedRegion)\" data-component-id=\"\(excludedRegion)\">turn: \(count)</div>"
				+ "<div id=\"sibling\" data-component-id=\"sibling\">sibling: \(count)</div>"
		}
		// static on purpose: the span is the second session's patch TARGET, and
		// its bytes must not move with the count — a changing byte outside every
		// region moves the residue, which escalates the diff to a whole page and
		// would make the region assertions below prove nothing.
		regions += "<span id=\"local\">local</span>"
			+ "<button id=\"local-btn\" data-component-id=\"local\" data-event=\"click\">local</button>"
		// the token travels the door every real page uses: the document's
		// runtime config, which is where the engine reads it from.
		let html = WebUIDocument(
			title: "refresh",
			body: .trusted(
				regions
					+ "<button id=\"bump\" data-component-id=\"bump\" data-event=\"click\">bump</button>"
			),
			clientMode: ClientBoot(config: RuntimeConfig(renderToken: request.renderToken.value))
		).markup.html
		return HTTPResponse(body: .html(UnsafeMarkup.trusted(html)))
	}
}

// MARK: - the harness

/// boot a real listener, run `body` against it, and always stop it.
///
/// the readiness probe is a real GET, so a page fixture's state must tolerate
/// one extra render; the intent suite resets its log after readiness for
/// exactly that reason.
private func withRefreshServer<T: Sendable>(
	_ label: String,
	basePort: Int,
	pageRouter: Router,
	eventRouter: EventRouter,
	config: WebUIServerConfig = WebUIServerConfig(),
	_ body: @Sendable (WebUIServer, Int) async throws -> T
) async throws -> T {
	let port = try await hostFreePort(base: basePort)
	var cfg = config
	cfg.host = "127.0.0.1"
	cfg.port = port
	// ONE router: the page registers into `eventRouter`, and the server must
	// dispatch through that same table — a server that mints its own answers
	// every event with an empty fragment list (the classic two-router bug).
	let server = WebUIServer(
		router: pageRouter,
		eventRouter: eventRouter,
		config: cfg,
		// the label names the boot in the server's own log lines; the handler
		// keeps the suite's output to the assertions.
		logger: Logger(label: label) { _ in SwiftLogNoOpLogHandler() }
	)
	let task = Task { try await server.start() }
	do {
		try await hostWaitForListening(port: port)
		let value = try await body(server, port)
		await server.stop()
		task.cancel()
		_ = try? await hostRun(bounded: .seconds(10), "the server to stop") { try await task.value }
		try await hostAssertClosed(port: port)
		return value
	} catch {
		await server.stop()
		task.cancel()
		throw error
	}
}

func trace(_ what: String) {
}

private func pingFrame(token: String) -> String {
	"{\"type\":\"ping\",\"token\":\"\(token)\"}"
}

private func navigateFrame(_ url: String) -> String {
	"{\"type\":\"navigate\",\"url\":\"\(url)\"}"
}

/// a frame that did not arrive inside the deadline.
private struct FrameDeadline: Error, CustomStringConvertible {
	let what: String
	var description: String { "no frame within the deadline: \(what)" }
}

/// resume a continuation exactly once, from whichever of the two racing tasks
/// gets there first.
private final class ResumeOnce: Sendable {
	private let slot: Mutex<CheckedContinuation<String, any Error>?>

	init(_ continuation: CheckedContinuation<String, any Error>) {
		self.slot = Mutex(continuation)
	}

	func resume(_ result: Result<String, any Error>) {
		let pending = slot.withLock { slot -> CheckedContinuation<String, any Error>? in
			defer { slot = nil }
			return slot
		}
		pending?.resume(with: result)
	}
}

/// the next frame, or a recorded failure after `seconds`.
///
/// `URLSessionWebSocketTask.receive` does not observe task cancellation, so a
/// structured `withThrowingTaskGroup` race would block on the abandoned
/// receive until the socket closed — a wedged suite instead of a failed case.
/// the race is therefore two UNSTRUCTURED tasks and a continuation resumed
/// once: the loser is abandoned, and the test always finishes.
private func nextFrame(
	_ socket: HostSocket,
	within seconds: Double = 5,
	_ what: String
) async throws -> String {
	try await withCheckedThrowingContinuation { continuation in
		let once = ResumeOnce(continuation)
		Task {
			do {
				once.resume(.success(try await socket.receiveText(bounded: .seconds(3_600))))
			} catch {
				once.resume(.failure(error))
			}
		}
		Task {
			try? await Task.sleep(for: .seconds(seconds))
			once.resume(.failure(FrameDeadline(what: what)))
		}
	}
}

/// consume the pong a ping is answered with — the proof a socket is bound and
/// alive before anything else is asserted about it.
private func expectPong(_ socket: HostSocket, _ what: String) async throws {
	let frame = try await nextFrame(socket, within: 5, "\(what) never answered the ping")
	#expect(frame.contains("pong"), "\(what): expected a pong, got \(frame.prefix(120))")
}

/// the next frame, decoded as an update.
private func expectUpdate(_ socket: HostSocket, _ what: String) async throws -> WireUpdate {
	let frame = try await nextFrame(socket, within: 5, "\(what) received no update")
	return try #require(
		try wireUpdate(frame),
		"\(what): expected an update frame, got \(frame.prefix(200))"
	)
}

// MARK: - (a) two tabs of one session

@Suite("refresh contract", .serialized)
struct RefreshContractTests {

	@Test("two sockets that speak for one render token both receive the refresh")
	func oneSessionTwoSockets() async throws {
		let fixture = RefreshFixture()
		let router = EventRouter()
		let page = RefreshCounterPage(fixture: fixture, router: router, excludedRegion: nil)

		try await withRefreshServer(
			"refresh.two-tabs",
			basePort: 54_000,
			pageRouter: Router { Route(method: .get, pattern: "/", responder: page) },
			eventRouter: router
		) { _, port in
			let served = try await hostGet("/", port: port, cookie: nil)
			#expect(served.status == 200)
			#expect(served.body.contains("count: 0"))
			let token = try renderToken(of: served.body)

			// two tabs of one page: both present the token its render minted.
			// a socket binds on its first token-bearing frame, which is why each
			// one pings before the other clicks.
			let first = try HostSocket(port: port, cookie: "")
			let second = try HostSocket(port: port, cookie: "")
			defer { first.cancel() }
			defer { second.cancel() }

			try await first.send(pingFrame(token: token))
			try await expectPong(first, "the first tab")
			try await second.send(pingFrame(token: token))
			try await expectPong(second, "the second tab")

			// one of the two clicks; the handler returns `.refresh`.
			try await first.send(hostEventFrame(component: "bump", token: token))

			let firstFrame = try await expectUpdate(first, "the clicking socket")
			#expect(firstFrame.fragments.map(\.id) == ["counter"])
			#expect(firstFrame.fragments.first?.html.contains("count: 1") == true)

			// the second tab did not click, and receives the same patch: the
			// refresh is the SESSION's, not the socket's.
			let secondFrame = try await expectUpdate(second, "the other socket of the same session")
			#expect(secondFrame.fragments.map(\.id) == ["counter"])
			#expect(
				secondFrame.fragments.first?.html.contains("count: 1") == true,
				"both tabs must be told the same new page"
			)
		}
	}

	// MARK: - (b) a second session receives nothing

	@Test("a socket in another session receives nothing from the refresh")
	func secondSessionIsIsolated() async throws {
		let fixture = RefreshFixture()
		let router = EventRouter()
		let page = RefreshCounterPage(fixture: fixture, router: router, excludedRegion: nil)

		try await withRefreshServer(
			"refresh.other-session",
			basePort: 54_100,
			pageRouter: Router { Route(method: .get, pattern: "/", responder: page) },
			eventRouter: router
		) { _, port in
			// two page loads, two tokens, two sessions.
			let firstPage = try await hostGet("/", port: port, cookie: nil)
			let secondPage = try await hostGet("/", port: port, cookie: nil)
			let tokenA = try renderToken(of: firstPage.body)
			let tokenB = try renderToken(of: secondPage.body)
			#expect(tokenA != tokenB, "two loads must mint two sessions, or the test proves nothing")

			let socketA = try HostSocket(port: port, cookie: "")
			let socketB = try HostSocket(port: port, cookie: "")
			defer { socketA.cancel() }
			defer { socketB.cancel() }

			// both sockets prove they are alive and bound before the click, so
			// the later silence cannot be read as "a broken connection".
			try await socketA.send(pingFrame(token: tokenA))
			try await expectPong(socketA, "session A's socket")
			try await socketB.send(pingFrame(token: tokenB))
			try await expectPong(socketB, "session B's socket")

			// 1. session A refreshes.
			try await socketA.send(hostEventFrame(component: "bump", token: tokenA))
			let update = try await expectUpdate(socketA, "the dispatching session's socket")
			#expect(update.fragments.map(\.id) == ["counter"])

			// 2. session B asks its own question. the answer it receives must be
			//    its OWN: frames are ordered, so a refresh fanned out to B would
			//    be queued ahead of this one and be the first frame B sees.
			try await socketB.send(hostEventFrame(component: "local", token: tokenB))
			let own = try await expectUpdate(socketB, "the second session's socket")
			#expect(
				own.fragments.map(\.id) == ["local"],
				"a refresh in one session must never reach another; got \(own.fragments.map(\.id))"
			)
		}
	}

	// MARK: - (c) exclusions

	@Test("an excluded region does not ship while its sibling does")
	func excludedRegionDoesNotShip() async throws {
		let fixture = RefreshFixture()
		let router = EventRouter()
		let page = RefreshCounterPage(
			fixture: fixture,
			router: router,
			excludedRegion: "live-turn-text"
		)
		// the policy names the token-owned region, exactly as arc does: the
		// streamer writes it on every token, so a refresh must never ship it —
		// nor let it make an ancestor look changed.
		let policy = RegionPolicy(excluded: ["live-turn-text"])

		try await withRefreshServer(
			"refresh.exclusions",
			basePort: 54_200,
			pageRouter: Router { Route(method: .get, pattern: "/", responder: page) },
			eventRouter: router,
			config: WebUIServerConfig(refreshPolicy: policy)
		) { _, port in
			let served = try await hostGet("/", port: port, cookie: nil)
			#expect(served.body.contains("turn: 0"))
			#expect(served.body.contains("sibling: 0"))
			let token = try renderToken(of: served.body)

			let socket = try HostSocket(port: port, cookie: "")
			defer { socket.cancel() }
			try await socket.send(pingFrame(token: token))
			try await expectPong(socket, "the excluded-region page")

			try await socket.send(hostEventFrame(component: "bump", token: token))
			let frame = try await expectUpdate(socket, "the excluded-region page's refresh")

			#expect(
				frame.fragments.map(\.id) == ["sibling"],
				"only the sibling region may ship; got \(frame.fragments.map(\.id))"
			)
			#expect(frame.fragments.first?.html.contains("sibling: 1") == true)
			let wire = frame.fragments.map(\.html).joined()
			#expect(!wire.contains("turn: 1"), "the excluded region's new bytes must never reach the wire")
		}
	}

	// MARK: - (d) the intent door

	@Test("the render door observes load, navigate and refresh")
	func intentDoorObservesAllThree() async throws {
		let fixture = RefreshFixture()
		let log = RenderLog()

		// the intent door, not `Route.get`: the host switches on why the page is
		// being rendered, which is how a load-only side effect stays load-only.
		let router = Router {
			Route.render("/") { request in
				log.record(request)
				Self.registerBump(fixture)
				return Self.intentPage(path: "/", count: fixture.count, token: request.renderToken.value)
			}
			Route.render("/other") { request in
				log.record(request)
				Self.registerBump(fixture)
				return Self.intentPage(path: "/other", count: fixture.count, token: request.renderToken.value)
			}
		}

		try await withRefreshServer(
			"refresh.intent",
			basePort: 54_300,
			pageRouter: router,
			eventRouter: EventRouter()
		) { _, port in
			// the readiness probe rendered `/` before this line; the sequence
			// under test starts at the request the browser would make.
			log.reset()

			let served = try await hostGet("/", port: port, cookie: nil)
			#expect(served.status == 200)
			let token = try renderToken(of: served.body)

			let socket = try HostSocket(port: port, cookie: "")
			defer { socket.cancel() }
			try await socket.send(pingFrame(token: token))
			try await expectPong(socket, "the intent page")

			// 2. the engine reports a client navigation.
			try await socket.send(navigateFrame("/other"))
			let navigateAnswer = try await nextFrame(socket, within: 5, "the navigate was never answered")
			#expect(!navigateAnswer.isEmpty, "a navigate must be answered (patch or redirect)")

			// 3. a control answers `.refresh`: the re-render is the remembered
			//    page, which by now is `/other`.
			try await socket.send(hostEventFrame(component: "bump", token: token))
			let refreshFrame = try await expectUpdate(socket, "the intent page's refresh")
			#expect(refreshFrame.fragments.map(\.id) == ["counter"])

			let observed = log.all
			#expect(
				observed.map(\.intent) == [.load, .navigate, .refresh],
				"the door must see load, navigate, refresh in that order; got \(observed)"
			)
			#expect(
				observed.map(\.path) == ["/", "/other", "/other"],
				"a refresh re-renders the page the session is on, not the one it started on"
			)
			#expect(
				observed.last?.token == token,
				"a refresh re-renders under the page's own token, so an echoed token stays stable"
			)
		}
	}

	/// register the fixture's control in the pass the server established.
	private static func registerBump(_ fixture: RefreshFixture) {
		guard let context = RenderContext.current else { return }
		context.router.register(outcome: { _ in
			fixture.bump()
			return .refresh
		}, for: ComponentID("bump"), in: context.session)
	}

	private static func intentPage(path: String, count: Int, token: String) -> HTTPResponse {
		let body = "<h1>\(path)</h1>"
			+ "<span id=\"counter\" data-component-id=\"counter\">count: \(count)</span>"
			+ "<button id=\"bump\" data-component-id=\"bump\" data-event=\"click\">bump</button>"
		let html = WebUIDocument(
			title: "intent",
			body: .trusted(body),
			clientMode: ClientBoot(config: RuntimeConfig(renderToken: token))
		).markup.html
		return HTTPResponse(body: .html(UnsafeMarkup.trusted(html)))
	}

	// MARK: - (e) the remembered page is evicted with the session

	@Test("the remembered-page map is bounded by maxSessions")
	func lastRenderIsEvictedWithTheSession() async throws {
		let fixture = RefreshFixture()
		let router = EventRouter()
		let page = RefreshCounterPage(fixture: fixture, router: router, excludedRegion: nil)

		// two sessions: more page loads than the cap, and the maps must stay at
		// the cap rather than growing one entry per load (plan risk 6).
		try await withRefreshServer(
			"refresh.eviction",
			basePort: 54_400,
			pageRouter: Router { Route(method: .get, pattern: "/", responder: page) },
			eventRouter: router,
			config: WebUIServerConfig(maxSessions: 2)
		) { server, port in
			for _ in 0..<5 {
				let served = try await hostGet("/", port: port, cookie: nil)
				#expect(served.status == 200)
			}
			let counts = await server.refreshStateCounts
			#expect(counts.renders == 2, "5 renders over a 2-session cap must leave 2 remembered pages, got \(counts.renders)")
			#expect(counts.baselines == 2, "and the baselines are capped by the same number, got \(counts.baselines)")
			#expect(counts.bindings == 0, "no socket connected, so no binding may linger")
		}
	}

	// MARK: - (f) a refresh that cannot render answers

	@Test("a refresh whose re-render throws answers the session's sockets with an error frame")
	func failedRefreshAnswersWithAnErrorFrame() async throws {
		let fixture = RefreshFixture()
		let router = EventRouter()
		// the page renders, then the click makes the re-render throw: the
		// failure is in the refresh path, after a successful load.
		let page = RefreshCounterPage(fixture: fixture, router: router, excludedRegion: nil)

		try await withRefreshServer(
			"refresh.failure",
			basePort: 54_500,
			pageRouter: Router { Route(method: .get, pattern: "/", responder: page) },
			eventRouter: router
		) { _, port in
			let served = try await hostGet("/", port: port, cookie: nil)
			let token = try renderToken(of: served.body)

			let socket = try HostSocket(port: port, cookie: "")
			defer { socket.cancel() }
			try await socket.send(pingFrame(token: token))
			try await expectPong(socket, "the failing page")

			// the *next* render throws — the refresh's own re-render.
			fixture.failNextRender = true
			try await socket.send(hostEventFrame(component: "bump", token: token))

			let frame = try await nextFrame(socket, within: 5, "a failed refresh answered nothing")
			#expect(
				wireErrorCode(frame) == "render",
				"the failure must arrive as a render error frame; got \(frame.prefix(200))"
			)

			// and the socket survives the failure: the page may try again.
			try await socket.send(pingFrame(token: token))
			try await expectPong(socket, "after a failed refresh")
		}
	}

	// MARK: - helpers

	/// the render token a served page published.
	///
	/// read out of the `<meta name="webui-config">` the document emits, which
	/// is where the engine reads it: a test that guessed the token could not
	/// prove the page's frames are answered in the session its render minted.
	/// the config is html-escaped inside the attribute, so the quotes in the
	/// marker are the escaped form.
	private func renderToken(of body: String) throws -> String {
		let marker = "&quot;renderToken&quot;:&quot;"
		let start = try #require(body.range(of: marker), "the page published no render token")
		let rest = body[start.upperBound...]
		let end = try #require(rest.range(of: "&quot;"), "the render token is unterminated")
		return String(rest[..<end.lowerBound])
	}
}

#endif