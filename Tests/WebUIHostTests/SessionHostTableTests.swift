import Foundation
import Logging
import Synchronization
import Testing
import WebUI
import WebUIServer

// MARK: - S6a: the host table and its seal
//
// the defect this slice closes, in one sentence: `register(_:for:)` — the
// hand-wired shape a host uses in its `init`, and the shape arc's ~64 boot
// registrations use — wrote into the mutable `.default` SESSION, so a page's
// render-time handler and a boot-wired handler shared one table that meant two
// different things. a stale page's event could reach a shape registered for
// another page, and a session reset could delete the boot wiring.
//
// the decision (§22.1 D1): ONE host table beside the per-session tables.
// registrations without a session land there; a server seals it after the
// host's boot wiring and before it serves; dispatch resolves the SESSION first
// and the HOST second, so a render-time registration shadows a boot id. `.default`
// stays a real session for tokenless pages and is no longer the host's bucket.
//
// what these tests pin, in the plan's own order: one mixed page with both
// populations, a colliding id (session wins), two concurrent sessions that
// never cross, an unknown/stale session that reaches no other session, a sealed
// table that refuses a late registration at `.error`, and the memory arithmetic
// (N host handlers do not become N × M).
//
// the instruments are two: a tag log, so "which handler ran" is an assertion
// rather than an inference from a reply string, and a capturing `LogHandler`, so
// "refused at error level" is read off the logger instead of stdout.

// MARK: - instruments

/// the order handler bodies actually ran in.
///
/// a reply alone cannot prove *which* registration answered — a shadowing
/// handler could return the same markup — so every handler in this suite records
/// its own tag and the assertions read the list.
private final class TagLog: Sendable {
	private let entries = Mutex<[String]>([])

	func record(_ tag: String) { entries.withLock { $0.append(tag) } }
	var all: [String] { entries.withLock { $0 } }
	func count(of tag: String) -> Int { entries.withLock { $0.filter { $0 == tag }.count } }
}

/// one line a ``CapturingLines`` kept.
private struct CapturedLine: Sendable, Equatable {
	let level: Logger.Level
	let message: String
}

/// a `LogHandler` that keeps every line it is handed.
///
/// `Logger` is a value over a handler, so a router built with this factory's
/// logger emits exactly the lines a test reads — no global logging state and no
/// stdout scraping.
private final class CapturingLines: LogHandler, Sendable {
	private struct Store: Sendable {
		var metadata: Logger.Metadata = [:]
		var lines: [CapturedLine] = []
	}

	private let store = Mutex(Store())
	private let level = Mutex(Logger.Level.trace)

	init() {}

	var metadata: Logger.Metadata {
		get { store.withLock { $0.metadata } }
		set { store.withLock { $0.metadata = newValue } }
	}

	var logLevel: Logger.Level {
		get { level.withLock { $0 } }
		set { level.withLock { $0 = newValue } }
	}

	subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { store.withLock { $0.metadata[key] } }
		set { store.withLock { $0.metadata[key] = newValue } }
	}

	func log(
		level: Logger.Level,
		message: Logger.Message,
		metadata: Logger.Metadata?,
		source: String,
		file: String,
		function: String,
		line: UInt
	) {
		store.withLock { $0.lines.append(CapturedLine(level: level, message: message.description)) }
	}

	var lines: [CapturedLine] { store.withLock { $0.lines } }

	func saw(_ level: Logger.Level, containing needle: String) -> Bool {
		lines.contains { $0.level == level && $0.message.contains(needle) }
	}

	func count(containing needle: String) -> Int {
		lines.filter { $0.message.contains(needle) }.count
	}
}

/// a router whose log output a test can read back, plus the handler to read it from.
private func capturingRouter(_ label: String = "webui.tests.hosttable") -> (EventRouter, CapturingLines) {
	let captured = CapturingLines()
	captured.logLevel = .trace
	return (EventRouter(logger: Logger(label: label) { _ in captured }), captured)
}

/// a payload-free action family, for the host-family dispatch branch: the
/// reserved key a typed registration lands under is reachable only through the
/// router's family path, so the test drives it with a wire id equal to the
/// family name.
private struct Ping: Action {
	static let family = "ping"
	let key: ActionKey

	init?(key: ActionKey, event: EventData) {
		guard key.family == Self.family else { return nil }
		self.key = key
	}
}

private func click(_ id: String) -> EventData {
	EventData(component: ComponentID(id), event: .click)
}

// MARK: - the router-level contract

@Suite("session host table")
struct SessionHostTableTests {

	// MARK: (a) a mixed page

	@Test("a mixed page routes both populations in one session")
	func mixedPageRoutesBothPopulations() async {
		let (router, lines) = capturingRouter()
		let tags = TagLog()

		// the boot wiring: no session argument, so this is the HOST table.
		let bootLanded = router.register({ _ in
			tags.record("host")
			return [FragmentUpdate(id: "host-out", html: "host")]
		}, for: ComponentID("boot-btn"))
		#expect(bootLanded, "a pre-seal host registration must land")

		// the render pass: an explicit session, which is a session table.
		let session = RenderSessionID("page-1")
		router.begin(session)
		router.register({ _ in
			tags.record("render")
			return [FragmentUpdate(id: "render-out", html: "render")]
		}, for: ComponentID("c0"), in: session)

		#expect(router.hostHandlerCount == 1)
		#expect(router.handlerCount(in: session) == 1, "the host table must not be counted as a session handler")

		let render = await router.dispatch(click("c0"), in: session)
		let host = await router.dispatch(click("boot-btn"), in: session)

		#expect(render.fragments.first?.id == "render-out", "the render-time handler must answer")
		#expect(host.fragments.first?.id == "host-out", "the host handler must answer the same page")
		#expect(tags.all == ["render", "host"], "each control reached exactly its own handler; got \(tags.all)")

		// the diagnostic names the case this slice exists for: a TOKEN-BOUND
		// dispatch that the session could not answer. one line, and it does not
		// change the answer above — the host table is the fallback, not a refusal.
		#expect(lines.count(containing: "mixed page") == 1, "one diagnostic for the host-answered token-bound miss")
		#expect(lines.saw(.debug, containing: "missed render session 'page-1'"))

		// a tokenless page is not a mixed page: `.default` is its own session, so
		// nothing was "missed". the diagnostic stays quiet.
		let tokenless = await router.dispatch(click("boot-btn"), in: .default)
		#expect(tokenless.fragments.first?.id == "host-out")
		#expect(lines.count(containing: "mixed page") == 1, "a tokenless dispatch must not be reported as a mixed page")
	}

	// MARK: (b) a colliding id

	@Test("a session registration shadows a host id, and the host still answers elsewhere")
	func sessionShadowsHost() async {
		let router = EventRouter()
		let tags = TagLog()

		router.register({ _ in
			tags.record("host")
			return [FragmentUpdate(id: "host-out", html: "host")]
		}, for: ComponentID("dup"))

		let session = RenderSessionID("page-shadow")
		router.begin(session)
		router.register({ _ in
			tags.record("render")
			return [FragmentUpdate(id: "render-out", html: "render")]
		}, for: ComponentID("dup"), in: session)

		let shadowed = await router.dispatch(click("dup"), in: session)
		#expect(shadowed.fragments.first?.id == "render-out", "the session's registration must win the id")
		#expect(tags.all == ["render"], "the shadowed host handler must not run; got \(tags.all)")

		// a page that did NOT register the id still reaches the host's handler:
		// shadowing is per-session, not a deletion.
		let other = RenderSessionID("page-plain")
		router.begin(other)
		let fromHost = await router.dispatch(click("dup"), in: other)
		#expect(fromHost.fragments.first?.id == "host-out")
		#expect(tags.all == ["render", "host"])
		#expect(router.hostHandlerCount == 1, "shadowing must not remove the host entry")
	}

	// MARK: (c) two concurrent sessions

	@Test("two sessions with colliding ids each answer their own handler, concurrently")
	func sessionsNeverCross() async {
		let router = EventRouter()
		let tags = TagLog()

		let tenantA = RenderSessionID("tenant-a")
		let tenantB = RenderSessionID("tenant-b")
		router.begin(tenantA)
		router.begin(tenantB)
		router.register({ _ in
			tags.record("a")
			return [FragmentUpdate(id: "a-out", html: "a")]
		}, for: ComponentID("c0"), in: tenantA)
		router.register({ _ in
			tags.record("b")
			return [FragmentUpdate(id: "b-out", html: "b")]
		}, for: ComponentID("c0"), in: tenantB)

		// the same id in two sessions, in flight at the same time: the router's
		// state is behind one lock, so an interleaving that answered from the
		// wrong table would show up here rather than in a lucky serial run.
		for _ in 0..<25 {
			async let fromA = router.dispatch(click("c0"), in: tenantA)
			async let fromB = router.dispatch(click("c0"), in: tenantB)
			let (answeredA, answeredB) = await (fromA, fromB)
			#expect(answeredA.fragments.first?.id == "a-out")
			#expect(answeredB.fragments.first?.id == "b-out")
		}

		#expect(tags.count(of: "a") == 25, "tenant A's handler fired once per A dispatch; got \(tags.count(of: "a"))")
		#expect(tags.count(of: "b") == 25, "tenant B's handler fired once per B dispatch; got \(tags.count(of: "b"))")
	}

	// MARK: (d) a stale / unknown session

	@Test("an unknown session id reaches no other session's handler; the host may answer")
	func unknownSessionReachesNothingElse() async {
		let router = EventRouter()
		let tags = TagLog()

		let real = RenderSessionID("real")
		router.begin(real)
		router.register({ _ in
			tags.record("real")
			return [FragmentUpdate(id: "real-out", html: "real")]
		}, for: ComponentID("only-real"), in: real)
		router.register({ _ in
			tags.record("host")
			return [FragmentUpdate(id: "host-out", html: "host")]
		}, for: ComponentID("boot"))

		// a token the server never minted (or one whose session was reaped): the
		// id exists in ANOTHER session's table and must not resolve there.
		let stale = RenderSessionID("stale-token")
		let miss = await router.dispatch(click("only-real"), in: stale)
		#expect(miss.fragments.isEmpty, "a stale session must not borrow another session's handler")
		#expect(tags.all.isEmpty, "the real session's handler fired for a foreign session; got \(tags.all)")

		// the host table is not a session, so it still answers — that is the
		// boot-wired shape a tokenless page relies on.
		let host = await router.dispatch(click("boot"), in: stale)
		#expect(host.fragments.first?.id == "host-out")
		#expect(tags.all == ["host"])
	}

	// MARK: (e) the seal

	@Test("a sealed host table refuses a late registration at error level, and the count holds")
	func sealRefusesLateRegistration() async {
		let (router, lines) = capturingRouter()
		let tags = TagLog()

		let bootLanded = router.register({ _ in
			tags.record("boot")
			return [FragmentUpdate(id: "boot-out", html: "boot")]
		}, for: ComponentID("boot"))
		#expect(bootLanded)
		#expect(router.hostHandlerCount == 1)
		#expect(!router.hostRegistrationsSealed)

		router.sealHostRegistrations()
		#expect(router.hostRegistrationsSealed)
		#expect(lines.saw(.debug, containing: "host registrations sealed"), "the seal reports itself once")

		// idempotent: a second seal is not a second line.
		router.sealHostRegistrations()
		#expect(lines.count(containing: "host registrations sealed") == 1)

		let lateLanded = router.register({ _ in
			tags.record("late")
			return [FragmentUpdate(id: "late-out", html: "late")]
		}, for: ComponentID("late"))
		#expect(!lateLanded, "a registration after the seal must be refused")
		#expect(router.hostHandlerCount == 1, "the refused registration must not grow the table")
		#expect(lines.saw(.error, containing: "host registrations are sealed"), "the refusal is logged at error level")

		// a fallback is a host write too: refusing it silently would be the
		// silent drop this door exists to prevent.
		let lateFallback = router.register(fallback: { _ in [] }, for: ComponentID("late"))
		#expect(!lateFallback)
		#expect(lines.saw(.error, containing: "fallback for 'late'"))

		// and nothing landed: the late id routes nowhere, and its body never runs.
		let dropped = await router.dispatch(click("late"), in: .default)
		#expect(dropped.fragments.isEmpty)
		#expect(tags.all.isEmpty, "a refused registration must not be reachable; got \(tags.all)")

		// the boot wiring the seal was declared over is untouched.
		let boot = await router.dispatch(click("boot"), in: .default)
		#expect(boot.fragments.first?.id == "boot-out")
	}

	@Test("a host fallback answers a session's failing handler, behind the session's own fallback")
	func hostFallbackIsSecondInLine() async {
		let router = EventRouter()
		struct Boom: Error {}

		func fallbackFragments(_ outcome: HandlerOutcome) -> [FragmentUpdate] {
			if case .fail(_, _, let fallback) = outcome { return fallback }
			return []
		}

		router.register(fallback: { _ in [FragmentUpdate(id: "host-fallback", html: "host-fallback")] }, for: ComponentID("wired"))
		router.register(outcome: { _ in throw Boom() }, for: ComponentID("wired"))

		let session = RenderSessionID("page-fallback")
		router.begin(session)
		// the session registers a page-owned fallback for the same id: it wins.
		router.register(fallback: { _ in [FragmentUpdate(id: "session-fallback", html: "session-fallback")] }, for: ComponentID("wired"), in: session)

		let fromSession = await router.dispatch(click("wired"), in: session)
		#expect(fromSession.isFailure)
		#expect(fallbackFragments(fromSession).first?.id == "session-fallback", "the session's fallback must shadow the host's")

		// without a session fallback the host's answers, so a boot-wired
		// degradation still applies to a page that only used the id.
		let other = RenderSessionID("page-fallback-plain")
		router.begin(other)
		let fromHost = await router.dispatch(click("wired"), in: other)
		#expect(fromHost.isFailure)
		#expect(fallbackFragments(fromHost).first?.id == "host-fallback")
	}

	@Test("the host table is bounded by maxHandlers, and an overwrite at the cap still lands")
	func hostTableIsBounded() {
		let captured = CapturingLines()
		captured.logLevel = .trace
		let router = EventRouter(logger: Logger(label: "webui.tests.hosttable.cap") { _ in captured }, maxHandlers: 2)

		let first = router.register({ _ in [] }, for: ComponentID("a"))
		let second = router.register({ _ in [] }, for: ComponentID("b"))
		#expect(first && second)
		#expect(router.hostHandlerCount == 2)

		let third = router.register({ _ in [] }, for: ComponentID("c"))
		#expect(!third, "a NEW host id past the cap must be refused")
		#expect(router.hostHandlerCount == 2)
		#expect(captured.saw(.error, containing: "host handler cap reached"))

		// re-registering an id the table already carries is an overwrite, not
		// growth: the cap must not refuse it, or a host whose boot routine runs
		// twice would lose a control it already wired.
		let overwrite = router.register({ _ in [FragmentUpdate(id: "a2", html: "a2")] }, for: ComponentID("a"))
		#expect(overwrite)
		#expect(router.hostHandlerCount == 2)
	}

	@Test("a host-registered action family answers, and a session's family shadows it")
	func hostFamilyIsSecondInLine() async {
		let router = EventRouter()
		let tags = TagLog()

		// the no-session typed door: one registration under the reserved family
		// key, in the HOST table.
		let landed = router.on(Ping.self) { action, _ in
			tags.record("host-family")
			return [FragmentUpdate(id: "host-ping", html: "host-ping")]
		}
		#expect(landed)
		#expect(router.hostHandlerCount == 1, "a family registration is one reserved host key")

		let session = RenderSessionID("page-family")
		router.begin(session)
		let answered = await router.dispatch(click("ping"), in: session)
		#expect(answered.fragments.first?.id == "host-ping", "the host family must answer a page that wired no family")
		#expect(tags.all == ["host-family"])

		// the session's own family registration shadows the host's, exactly as an
		// exact id does.
		router.on(Ping.self, in: session) { _, _ in
			tags.record("session-family")
			return [FragmentUpdate(id: "session-ping", html: "session-ping")]
		}
		let shadowed = await router.dispatch(click("ping"), in: session)
		#expect(shadowed.fragments.first?.id == "session-ping")
		#expect(tags.all == ["host-family", "session-family"], "only the shadowing registration runs")

		// and the host's is still the answer for a page that did not register it.
		let other = RenderSessionID("page-family-plain")
		router.begin(other)
		let fromHost = await router.dispatch(click("ping"), in: other)
		#expect(fromHost.fragments.first?.id == "host-ping")
	}

	// MARK: (f) memory

	@Test("the host table is stored once: 10 host handlers stay 10 across 50 sessions")
	func hostTableIsNotCopiedPerSession() {
		let router = EventRouter()
		for index in 0..<10 {
			let landed = router.register({ _ in [] }, for: ComponentID("host-\(index)"))
			#expect(landed)
		}
		#expect(router.hostHandlerCount == 10)

		for index in 0..<50 {
			router.begin(RenderSessionID("page-\(index)"))
		}

		#expect(router.sessionCount == 50)
		#expect(router.hostHandlerCount == 10, "N host handlers must not become N × M")
		for index in 0..<50 {
			#expect(
				router.handlerCount(in: RenderSessionID("page-\(index)")) == 0,
				"a fresh session must not be seeded with the host's copies"
			)
		}
		#expect(router.handlerCount == 0, "no session holds a copy of a host handler")
	}
}

// MARK: - the seal call site, over the wire

#if !os(Linux)

/// the server half of the contract: `start()` seals the host table AFTER the
/// host's boot wiring and BEFORE the listener accepts a frame, and a boot-wired
/// handler still answers a real frame afterwards.
///
/// the ordering is the whole assertion. sealing in `init` would refuse the
/// host's own wiring (the shape `init(router:eventRouter:…)` exists for);
/// sealing after `bind` would leave a window where a late registration lands
/// under a serving server. one call site satisfies both, and this test fails if
/// it moves.
@Suite("host table over the wire", .serialized)
struct HostTableServerTests {

	/// a page carrying one hand-wired control: no render-time registrations, so
	/// the click can only be answered by the host table.
	private static func pageRouter() -> Router {
		Router {
			Route.get("/") { _ in
				HTTPResponse(
					UnsafeMarkup.trusted(
						"""
						<!doctype html><html><body><div id="boot-btn" data-component-id="boot-btn" data-event="click">boot</div></body></html>
						"""
					)
				)
			}
		}
	}

	@Test("start() seals after boot wiring, and a boot-wired click still answers on the wire")
	func serverSealsAfterBootWiring() async throws {
		let (router, lines) = capturingRouter("webui.tests.hosttable.server")
		let tags = TagLog()

		let bootLanded = router.register({ _ in
			tags.record("boot")
			return [FragmentUpdate(id: "boot-out", html: "<span id=\"boot-out\">boot-ok</span>")]
		}, for: ComponentID("boot-btn"))
		#expect(bootLanded, "the host's boot wiring must land before the server starts")

		let port = try await hostFreePort(base: 53_100)
		var config = WebUIServerConfig(host: "127.0.0.1", port: port)
		config.requireRenderToken = false
		let server = WebUIServer(
			router: Self.pageRouter(),
			eventRouter: router,
			config: config,
			logger: hostedTestLogger
		)
		let task = Task { try await server.start() }

		do {
			try await hostWaitForListening(port: port)

			// THE ASSERTION: the listener is up, and the table is already shut.
			#expect(router.hostRegistrationsSealed, "start() must seal the host table before it serves")
			#expect(lines.saw(.debug, containing: "host registrations sealed"))
			#expect(router.hostHandlerCount == 1)

			// a registration arriving after serve is refused, not landed.
			let late = router.register({ _ in [] }, for: ComponentID("late"))
			#expect(!late)
			#expect(router.hostHandlerCount == 1)
			#expect(lines.saw(.error, containing: "host registrations are sealed"))

			// and the boot wiring the seal was declared over is live: the frame
			// carries no token, so the server resolves it to `.default` — which
			// holds no registration at all. the host table is the only thing that
			// can answer it.
			let socket = try HostSocket(port: port, cookie: "")
			defer { socket.cancel() }
			try await socket.send(hostEventFrame(component: "boot-btn", token: ""))
			let reply = try await socket.receiveText(bounded: .seconds(10))
			#expect(reply.contains("boot-out"), "the boot-wired handler must answer; got \(reply)")
			#expect(tags.all == ["boot"])
			#expect(router.handlerCount(in: .default) == 0, "the host table answered; `.default` holds nothing")
		} catch {
			await server.stop()
			task.cancel()
			throw error
		}

		await server.stop()
		task.cancel()
		_ = try? await hostRun(bounded: .seconds(10), "the server to stop") { try await task.value }
		try await hostAssertClosed(port: port)
	}
}

#endif
