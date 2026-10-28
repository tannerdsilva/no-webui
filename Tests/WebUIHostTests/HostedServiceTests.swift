import Testing
import ServiceLifecycle
import WebUI
import WebUIServer
import WebUIHost

// MARK: - B1: the service hosts the product
//
// the gate, verbatim: "an authenticated page serves through the service; an
// unauthenticated request gets the catalog's 303; the service starts and stops
// cleanly."
//
// every case below drives a real listener on a real port. a service tested
// against a fake listener would prove the fake, and the whole reason this type
// exists is that the accept loop and the session table are easy to wire in a way
// that compiles and never serves.

@Suite("hosted service", .serialized)
struct HostedServiceTests {

	@Test("an authenticated page serves through the service")
	func authenticatedPageServes() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_000)
		let task = try await fixture.start()

		let response = try await fixture.page()
		#expect(response.status == 200, "a resolved principal must be served its page")
		#expect(response.body.contains("<h1>Member Dashboard</h1>"))
		// the control the page's state lives in, and the token the client echoes.
		#expect(response.body.contains("data-component-id=\"counter-value\""))
		#expect(response.body.contains("id=\"counter-value\""))
		let token = try await fixture.renderToken()
		#expect(response.body.contains(token), "the page must carry the token its socket will present")

		try await fixture.stop(task)
	}

	@Test("an unauthenticated request gets the catalog's 303")
	func anonymousRequestGetsRedirect() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_050)
		let task = try await fixture.start()

		let anonymous = try await hostGet("/", port: fixture.port, cookie: nil)
		let inProcess = try await fixture.host.respond(to: Fixture.request("/"))
		#expect(inProcess.status.code == 303, "the host's anonymous answer, in process")
		#expect(anonymous.status == 303)
		#expect(anonymous.location == "/login", "the catalog owns the anonymous answer, not the host")
		#expect(anonymous.body.isEmpty)

		try await fixture.stop(task)
	}

	@Test("the service starts and stops inside a ServiceGroup")
	func serviceRunsInAGroup() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_100)
		let service = fixture.service
		let port = fixture.port
		let cookie = fixture.cookie

		// the real construction: an outer group with one service, the way a
		// deployment's entry point writes it.
		let group = ServiceGroup(services: [service], logger: hostedTestLogger)
		let running = Task { try await group.run() }
		try await hostWaitForListening(port: port, cookie: cookie)

		// a page render, so stopping has state to clean up.
		let page = try await fixture.page()
		#expect(page.status == 200)
		#expect(fixture.host.stores.count == 1)

		await group.triggerGracefulShutdown()
		try await hostRun(bounded: .seconds(15), "the group to finish shutting down") {
			try await running.value
		}

		// from the outside, stopped means the listener refuses.
		try await hostAssertClosed(port: port)
		// and from the inside, the cleanup ran: no session's state survives the
		// service that owned it.
		#expect(fixture.host.stores.count == 0)
		#expect(fixture.host.stores.liveCount == 0)
	}

	@Test("a cancelled run stops the listener and leaves no session behind")
	func cancellationStopsTheService() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_150)
		let task = try await fixture.start()
		let page = try await fixture.page()
		#expect(page.status == 200)

		task.cancel()
		try await hostRun(bounded: .seconds(15), "the cancelled service to return") {
			try await task.value
		}

		try await hostAssertClosed(port: fixture.port)
		#expect(fixture.host.stores.count == 0, "the sweep at the end of run() owns the shutdown")
		#expect(await fixture.table.sessionCount == 0)
	}
}
