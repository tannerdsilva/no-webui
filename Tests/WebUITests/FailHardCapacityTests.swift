import Logging
import NIOEmbedded
import NIOCore
import Testing
import WebUI
import WebUIServer

// MARK: - C2 / C4: capacity refuses loudly
//
// §7.1's silent paths 1 and 3, made loud:
//
// 1. admission at `maxConnections` closed the channel with no status, no log
//    and no metric. now the refusal is counted, logged at `.error`, and the
//    connection's FIRST request is answered `503` + `Retry-After` from raw
//    bytes. a connect that sends nothing is still closed at the read-idle
//    window — there is no request to answer, and pretending otherwise would
//    mean writing an unsolicited response (plan §14 N12).
//
// 3. session LRU eviction deleted a live page's handlers to admit a newcomer.
//    now `beginStrict` refuses the newcomer with `atCapacity(.sessions)`; a
//    live incumbent is never the price of a newcomer (§7.2 rule 3).

@Suite("fail hard: capacity")
struct FailHardCapacityTests {

	private let session = RenderSessionID("cap-probe")

	// MARK: C2 — the connection cap

	@Test("a refusal is counted and logged at error, by default")
	func refusalIsCountedAndLogged() async throws {
		let (logger, captured) = capturingLogger()
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		// no explicit disposition: the default is the one the server gets.
		let admission = Admission(gate: gate, logger: logger)

		#expect(admission.disposition == .answer)
		guard case .refuse(let rejection) = admission.decide() else {
			Issue.record("a second acquisition against a cap of one must be refused")
			return
		}
		#expect(rejection.kind == .connections)
		#expect(rejection.limit == 1)
		#expect(admission.refusalCount == 1)
		#expect(captured.saw(.error, containing: "admission refused: connections at capacity (limit 1)"))
		#expect(gate.activeCount == 1, "a refusal must not take a slot")
	}

	@Test("a refused connection's first request is answered 503 with Retry-After")
	func refusedConnectionIsAnswered() throws {
		let (logger, _) = capturingLogger()
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		let admission = Admission(gate: gate, logger: logger)
		let channel = EmbeddedChannel()
		let closed = ClosedFlag(channel)
		#expect(admission.admit(channel) == false)
		// nothing is written to a connection that has not asked anything yet
		#expect(closed.value(channel) == false, "a refusal must not close before the first request")

		try channel.writeInbound(ByteBuffer(string: "GET / HTTP/1.1\r\nHost: failhard\r\n\r\n"))
		let written = try #require(try channel.readOutbound(as: ByteBuffer.self))
		let wire = String(buffer: written)
		#expect(wire.hasPrefix("HTTP/1.1 503 Service Unavailable\r\n"))
		#expect(wire.contains("\r\nRetry-After: 1\r\n"))
		#expect(wire.hasSuffix("service unavailable: connections at capacity (limit 1)\n"))

		// the response completes, then the connection closes: `Connection: close`
		// is a promise, and a pipelined second request is not served either.
		#expect(closed.value(channel), "the refusal must close once its 503 is written")
		try channel.writeInbound(ByteBuffer(string: "GET /again HTTP/1.1\r\n\r\n"))
		#expect(try channel.readOutbound(as: ByteBuffer.self) == nil, "a pipelined second request is not served")
		_ = try? channel.finish()
	}

	@Test("a refused connect that sends nothing is written nothing")
	func requestlessConnectIsNotAnswered() throws {
		let (logger, _) = capturingLogger()
		let gate = ConnectionGate(maximum: 1)
		#expect(gate.tryAcquire())
		let admission = Admission(gate: gate, logger: logger)
		let channel = EmbeddedChannel()
		let closed = ClosedFlag(channel)

		#expect(admission.admit(channel) == false)
		#expect(try channel.readOutbound(as: ByteBuffer.self) == nil)
		// a connect that sent nothing has no request to refuse: it is held for
		// the read-idle window, not written an unsolicited response
		#expect(closed.value(channel) == false)
		let idleContext = try channel.pipeline.context(handlerType: IdleStateHandler.self).wait()
		let idle = try #require(idleContext.handler as? IdleStateHandler)
		#expect(idle.readTimeout == .seconds(120))
		_ = try? channel.finish()
	}

	@Test("a real server at its connection cap answers 503 and holds no page")
	func realServerAnswers503AtTheCap() async throws {
		let (logger, captured) = capturingLogger("webui.tests.failhard.server")
		let port = try await freePort(base: 42000)
		var config = WebUIServerConfig(host: "127.0.0.1", port: port, maxConnections: 1)
		config.readIdleSeconds = 30
		let server = WebUIServer(router: Router {}, config: config, logger: logger)
		let task = Task { try await server.start() }

		// the first connect is also the readiness probe: it HOLDS the only slot,
		// so there is no window in which a probe connection's release races the
		// refusal this test is about.
		let held = try await RawConnection.connect(port: port)
		let refused = try await RawConnection.connect(port: port)
		do {
			try await held.settle()
			#expect(await server.connectedPages == 0)

			// the second connection is refused, and its first request is answered.
			try await refused.send("GET / HTTP/1.1\r\nHost: failhard\r\nConnection: close\r\n\r\n")
			let wire = try await refused.awaitClose()

			#expect(wire.hasPrefix("HTTP/1.1 503 Service Unavailable\r\n"), "wire was: \(wire)")
			#expect(wire.contains("\r\nRetry-After: 1\r\n"))
			#expect(wire.contains("connections at capacity (limit 1)"))
			#expect(wire.contains("200 OK") == false, "the refused connection must not be served a page")

			// the cap refused a connection; it did not accept a page
			#expect(await server.connectedPages == 0)
			#expect(captured.saw(.error, containing: "admission refused: connections at capacity"))
		} catch {
			await refused.shut()
			await held.shut()
			await server.stop()
			task.cancel()
			throw error
		}
		await refused.shut()
		await held.shut()
		await server.stop()
		task.cancel()
	}

	// MARK: C4 — the session cap

	@Test("the session cap refuses the newcomer and never evicts a live incumbent")
	func sessionCapRefusesNewcomer() async throws {
		let router = EventRouter(maxSessions: 3)
		let incumbents = (0..<3).map { RenderSessionID("live-\($0)") }

		for (index, session) in incumbents.enumerated() {
			try router.beginStrict(session)
			router.markLive(session)
			router.register(
				outcome: { _ in .fragments([FragmentUpdate(id: "c0", html: "<b>\(index)</b>")]) },
				for: ComponentID("c0"),
				in: session
			)
		}
		#expect(router.sessionCount == 3)
		#expect(router.handlerCount == 3)

		// the fourth render is a newcomer: it is refused, not admitted by
		// deleting somebody's live page.
		let newcomer = RenderSessionID("newcomer")
		#expect(
			thrownFailure { try router.beginStrict(newcomer) }
				== .atCapacity(kind: .sessions, limit: 3)
		)
		#expect(router.contains(newcomer) == false)
		#expect(router.sessionCount == 3)

		for session in incumbents {
			#expect(router.contains(session), "a live incumbent must never be evicted")
			#expect(router.isLive(session))
			#expect(router.handlerCount(in: session) == 1)
		}

		// the incumbents still dispatch: refusing the newcomer broke nothing.
		for session in incumbents {
			let outcome = await router.dispatch(
				EventData(component: ComponentID("c0"), event: .click),
				in: session
			)
			#expect(outcome.fragments.count == 1)
		}
	}

	@Test("the refusal is a 503 through the route's one catch")
	func sessionCapAnswers503() throws {
		let router = EventRouter(maxSessions: 1)
		try router.beginStrict(session)
		router.markLive(session)

		let error = thrownFailure { try router.beginStrict(RenderSessionID("newcomer")) }
		let failure = try #require(error)
		let answer = FailHardRoute.Answer(
			status: FailHardRoute.status(for: failure),
			body: FailHardRoute.body(for: failure)
		)
		#expect(answer.status == 503)
		#expect(answer.reason == "Service Unavailable")
		#expect(answer.body.contains("atCapacity"))
	}

	@Test("a closed session is reaped to make room, a live one never is")
	func closedSessionMakesRoom() throws {
		let router = EventRouter(maxSessions: 1)
		let page = RenderSessionID("page")
		try router.beginStrict(page)
		router.markLive(page)

		// the live page blocks the newcomer
		#expect(thrownFailure { try router.beginStrict(RenderSessionID("newcomer")) } != nil)
		// its socket closes: now the newcomer fits. nothing live was evicted to
		// admit it — the closed page was reaped, which is what "reaped by
		// lifecycle, not by pressure" means.
		router.markClosed(page)
		try router.beginStrict(RenderSessionID("newcomer"))
		#expect(router.contains(RenderSessionID("newcomer")))
		#expect(router.contains(page) == false)
		#expect(router.sessionCount == 1)
	}

	@Test("a re-render of a known page is never refused, even at the cap")
	func reRenderAtCapIsAdmitted() throws {
		let router = EventRouter(maxSessions: 1)
		let page = RenderSessionID("page")
		try router.beginStrict(page)
		router.markLive(page)

		// refreshing the page you are looking at costs no new row
		try router.beginStrict(page, preservingRegistrations: true)
		try router.beginStrict(page)
		#expect(router.sessionCount == 1)
		#expect(router.isLive(page))
	}
}
