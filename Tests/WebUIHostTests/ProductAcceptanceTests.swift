import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - the product acceptance gate
//
// the gate, verbatim: "an authenticated, stateful page, over a **real socket**,
// receives a mutation and ships **less than 2 % of the page's bytes**, and
// applying the fragment to the previous render reproduces the new render
// byte-for-byte."
//
// this is the only test in the tree that has all three halves at once: an
// authenticated session (the catalog resolved it), a stateful page (the store is
// the host's, not the test's), and a real connection (frames over tcp, not a
// value handed to a double). `WebUIState`'s own suites measure the differ,
// `WebUIHost`'s measure the ports, and the example measures neither — the seams
// existed side by side and never multiplied. this is the multiplication.
//
// the mutation is a click on `counter-value`, whose bound value lives *inside*
// the element carrying the routing attributes. that is not decoration: the
// differ patches elements carrying `data-component-id`, so a heading bound to
// `state.count` would move `residue` and the differ would correctly answer a
// full page (N05). the gate is about the composition working, not about
// relaxing the differ until a number looks good.

#if !os(Linux)
@Suite("product acceptance", .serialized)
struct ProductAcceptanceTests {

	/// the whole claim, in one run: bytes on the wire, then bytes of the page.
	@Test("a click over a real socket ships under 2 % of the page and reproduces the render")
	func clickShipsAFragment() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_400)
		let task = try await fixture.start()

		// 1. the page, as the browser receives it.
		let served = try await fixture.page()
		#expect(served.status == 200)
		let pageBytes = served.body.utf8.count
		let token = try await fixture.renderToken()
		#expect(served.body.contains(token))

		// 2. the socket the page opens, presenting the cookie that rendered it.
		let socket = try HostSocket(port: fixture.port, cookie: fixture.cookie)
		defer { socket.cancel() }

		// 3. one click, the frame the engine sends for it.
		try await socket.send(hostEventFrame(component: "counter-value", token: token))
		let frame = try await socket.receiveText()
		let update = try #require(try wireUpdate(frame), "the mutation must answer an update frame, got: \(frame.prefix(200))")

		// 4. one fragment, addressed by the element's own id — which is what the
		//    engine's `getElementById` needs, and what `data-component-id` has to
		//    equal for a real client to apply it.
		#expect(update.fragments.count == 1, "one control moved, so one fragment ships")
		let fragment = try #require(update.fragments.first)
		#expect(fragment.id == "counter-value")
		#expect(fragment.html.contains("id=\"counter-value\""))
		#expect(fragment.html.contains("data-component-id=\"counter-value\""))
		#expect(fragment.html.contains("<span>1</span>"), "the fragment carries the new value")

		// 5. the byte gate: the frame the socket carried, against the page.
		// measured on this page (220 rows, 25,070 B): the update frame is 185 B
		// and its fragment 113 B — 0.74 % and 0.45 % of the page. the bound
		// below is the gate's, and the byte cap beside it catches a regression
		// that a ratio could hide behind a bigger page.
		let frameShare = Double(update.frameBytes) / Double(pageBytes)
		let fragmentShare = Double(update.fragmentBytes) / Double(pageBytes)
		#expect(update.fragmentBytes < 256, "one control's bytes, not a page's")
		#expect(update.frameBytes < 512, "the frame's envelope is 72 B; 512 is generous")
		#expect(
			frameShare < 0.02,
			"the update frame is \(update.frameBytes) B of a \(pageBytes) B page (\(frameShare) %) — over the 2 % gate"
		)
		#expect(
			fragmentShare < 0.02,
			"the fragments are \(update.fragmentBytes) B of a \(pageBytes) B page (\(fragmentShare) %)"
		)

		// 6. DOM equality: apply the fragment to the render the client already
		//    had, and the result must be the render a full page request produces.
		//    a second GET renders the same session's store at the same revision,
		//    so this compares bytes, not intent.
		let reloaded = try await fixture.page()
		#expect(reloaded.status == 200)
		let previous = bodyMarkup(of: served.body)
		let next = bodyMarkup(of: reloaded.body)
		#expect(previous != next, "the mutation must have changed the page, or the gate proves nothing")
		let patched = try applyingFragments(update.fragments, to: previous)
		#expect(
			patched == next,
			"applying the fragment to the previous render must reproduce the new render byte for byte"
		)

		try await fixture.stop(task)
	}

	/// the baseline survives a second mutation: one loop per session, not one
	/// per pass. an example that rebuilt its loop every render shipped a whole
	/// page every time — this is the test that would have caught it.
	@Test("a second click is still one fragment, because the session keeps its baseline")
	func secondClickStillPatches() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_450)
		let task = try await fixture.start()
		let served = try await fixture.page()
		let pageBytes = served.body.utf8.count
		let token = try await fixture.renderToken()

		let socket = try HostSocket(port: fixture.port, cookie: fixture.cookie)
		defer { socket.cancel() }

		try await socket.send(hostEventFrame(component: "counter-value", token: token))
		let first = try #require(try wireUpdate(try await socket.receiveText()))

		try await socket.send(hostEventFrame(component: "counter-value", token: token))
		let second = try #require(try wireUpdate(try await socket.receiveText()))

		#expect(first.fragments.count == 1)
		#expect(second.fragments.count == 1)
		#expect(second.fragments.first?.html.contains("<span>2</span>") == true)
		#expect(second.frameBytes < pageBytes / 50, "the second patch is still a fragment, not a page")

		try await fixture.stop(task)
	}

	/// B3's socket half: logout ends the connection a page was holding.
	///
	/// the observer hands the host a `close` handle for every socket it
	/// announces, so the host registers each connection with its revocation bus
	/// and a logout closes it outright. the earlier shape — refuse the next frame
	/// and let the server close on the refusal — left a logged-out browser
	/// holding a live socket until it happened to speak, which is exactly the
	/// window the revocation exists to close.
	@Test("logout closes the live socket")
	func logoutEndsTheLiveSocket() async throws {
		let fixture = try await HostedFixture.make(portBase: 52_500)
		let task = try await fixture.start()
		let served = try await fixture.page()
		let token = try await fixture.renderToken()
		#expect(served.status == 200)

		let socket = try HostSocket(port: fixture.port, cookie: fixture.cookie)
		defer { socket.cancel() }

		// the upgrade resolves the same session the page did: a socket carries
		// no token and no query before its first frame, so the cookie on the
		// upgrade request is its only identity — the authorizer reads it, and
		// the observer marks that session live.
		try await hostRun(bounded: .seconds(5), "the socket to register its session") {
			while !fixture.host.stores.isLive(fixture.login.sessionKey) {
				try await Task.sleep(for: .milliseconds(10))
			}
			return true
		}

		// a frame that works, so the socket is proven live before the logout.
		try await socket.send(hostEventFrame(component: "counter-value", token: token))
		let live = try #require(try wireUpdate(try await socket.receiveText()))
		#expect(live.fragments.count == 1)

		// logout over http, the way a sign-out form does.
		_ = try await fixture.host.signOut(for: Fixture.request("/", cookie: fixture.cookie))

		// the store and the handler table are gone the moment `signOut` returns,
		// and the session is no longer live either.
		#expect(fixture.host.stores.count == 0)
		#expect(!fixture.host.stores.isLive(fixture.login.sessionKey))
		#expect(await fixture.table.renderTokens(for: fixture.login.sessionKey).isEmpty)

		// and the socket the page was holding ends now, without the peer
		// sending anything: the closer the server handed the observer is the
		// one the bus calls on revoke.
		let closed = try await socket.awaitClose(bounded: .seconds(5))
		#expect(closed, "logout closes the live socket; the peer sees it without sending a frame")
		#expect(fixture.host.stores.count == 0)

		try await fixture.stop(task)
	}
}
#endif
