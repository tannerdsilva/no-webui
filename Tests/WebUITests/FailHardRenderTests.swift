import Testing
import WebUI
import WebUIServer

// MARK: - C3 / C5 / C6: a render that cannot be honoured does not ship
//
// §7.1's silent paths 2, 5 and 3's lifecycle half:
//
// 2. the handler cap warned and returned, so a control was rendered with no
//    handler behind it. now the refusal is recorded on the session, logged at
//    `.error`, and `raisePendingFailure` throws it — the page is a `500`.
//
// 5. `RenderToken.mint()` returning nil shipped a page with no token, so every
//    event on it was refused and the page was silently inert. now entropy is a
//    thrown `entropyUnavailable` and the render fails.
//
// 6. sessions left the table only under pressure. now a socket close ends the
//    session (`sessionClosed`), so the table shrinks by lifecycle and the cap
//    is affordable without evicting a live page.

@Suite("fail hard: render failures")
struct FailHardRenderTests {

	/// a page with four auto-minted click controls — the shape that hits the
	/// handler cap.
	private func renderFourControls(router: EventRouter, session: RenderSessionID) -> String {
		let context = RenderContext(router: router, session: session)
		return RenderContext.$current.withValue(context) {
			Div {
				Div { Text("one") }.onClick { _ in [] }
				Div { Text("two") }.onClick { _ in [] }
				Div { Text("three") }.onClick { _ in [] }
				Div { Text("four") }.onClick { _ in [] }
			}.markup.html
		}
	}

	private func renderTwoControls(router: EventRouter, session: RenderSessionID) -> String {
		let context = RenderContext(router: router, session: session)
		return RenderContext.$current.withValue(context) {
			Div {
				Div { Text("one") }.onClick { _ in [] }
				Div { Text("two") }.onClick { _ in [] }
			}.markup.html
		}
	}

	// MARK: C3 — the handler cap

	@Test("the handler cap fails the render instead of dropping the registration")
	func handlerCapFailsRender() throws {
		let (logger, captured) = capturingLogger()
		let router = EventRouter(logger: logger, maxHandlers: 3)
		#expect(router.policy == .strict, "strict is the default: a cap never degrades silently")
		let session = RenderSessionID("cap")
		try router.beginStrict(session)

		let markup = renderFourControls(router: router, session: session)
		#expect(markup.contains("data-component-id"))

		// three landed; the fourth did not — and the page knows why
		#expect(router.handlerCount(in: session) == 3)
		#expect(router.pendingFailure(in: session) == .handlerCapReached(session: "cap", limit: 3))
		#expect(captured.saw(.error, containing: "handler cap reached (3)"))

		// the render is a failure: 500, and no byte of the page ships
		let answer = FailHardRoute.answer(rendering: markup, router: router, session: session)
		#expect(answer.status == 500)
		#expect(answer.reason == "Internal Server Error")
		#expect(answer.body.hasPrefix("500 — render refused:"))
		#expect(answer.body.contains("handlerCapReached"))
		#expect(answer.body.contains("data-component-id") == false, "no partial page may ship")

		// the failure was consumed: a pass fails once, and the next one is clean
		#expect(router.pendingFailure(in: session) == nil)
		#expect(throws: Never.self) { try router.raisePendingFailure(in: session) }
	}

	@Test("a re-render at the cap still registers its own ids")
	func reRenderAtCapStillRegisters() throws {
		let router = EventRouter(maxHandlers: 2)
		let session = RenderSessionID("cap")
		router.begin(session)
		_ = renderTwoControls(router: router, session: session)
		#expect(router.handlerCount(in: session) == 2)

		// the same page renders again: the same ids are overwritten, which does
		// not grow the table — so the cap must not refuse them. the old code
		// refused the overwrite too, which is how a saturated page stopped
		// routing altogether rather than merely stopping growth.
		router.begin(session)
		_ = renderTwoControls(router: router, session: session)
		#expect(router.pendingFailure(in: session) == nil)
		#expect(router.handlerCount(in: session) == 2)
		#expect(throws: Never.self) { try router.raisePendingFailure(in: session) }
	}

	@Test("the degrade policy keeps the 1.x warning-only shape")
	func degradePolicyWarns() throws {
		let (logger, captured) = capturingLogger()
		let router = EventRouter(logger: logger, maxHandlers: 3, policy: .degrade)
		let session = RenderSessionID("cap")
		router.begin(session)

		_ = renderFourControls(router: router, session: session)
		#expect(router.handlerCount(in: session) == 3)
		#expect(router.pendingFailure(in: session) == nil, "degrade records nothing to raise")
		#expect(captured.saw(.warning, containing: "handler cap reached"))
		#expect(FailHardRoute.answer(rendering: "page", router: router, session: session).status == 200)
	}

	// MARK: C5 — entropy

	@Test("entropy failure is a 500, never a tokenless page")
	func entropyFailureFailsRender() throws {
		// the seam reports the failure rather than inventing a token
		#expect(RenderToken.mint(using: DeadEntropy()) == nil)
		// the strict door throws the one vocabulary's word
		#expect(
			thrownFailure { _ = try SecureRandom.requireBytes(16, using: DeadEntropy()) }
				== .entropyUnavailable
		)
		// the render's token decision: no token ⇒ no page
		let answer = FailHardRoute.answer(
			mintingFrom: DeadEntropy(),
			rendering: "<html><body>page</body></html>"
		)
		#expect(answer.status == 500)
		#expect(answer.reason == "Internal Server Error")
		#expect(answer.body.contains("entropyUnavailable"))
		#expect(answer.body.contains("<html>") == false, "a tokenless page must never ship")
	}

	@Test("the platform source still mints a token")
	func systemEntropyStillMints() throws {
		let token = try FailHardRoute.token(using: SystemSecureRandom())
		#expect(token.value.isEmpty == false)
		#expect(token.value.count == 22, "16 random bytes is 22 base64url characters")
	}

	// MARK: C6 — socket close ends the session

	@Test("a socket close ends the session without an eviction")
	func socketCloseEndsSession() throws {
		let router = EventRouter(maxSessions: 8)
		let page = RenderSessionID("page")
		try router.beginStrict(page)
		router.markLive(page)
		router.register(outcome: { _ in .fragments([]) }, for: ComponentID("c0"), in: page)
		#expect(router.sessionCount == 1)
		#expect(router.handlerCount(in: page) == 1)

		#expect(router.sessionClosed(page) == 1)

		#expect(router.sessionCount == 0, "the table shrank because the page ended")
		#expect(router.isLive(page) == false)
		#expect(router.contains(page) == false)
		#expect(router.handlerCount == 0)
		// and no newcomer rendered: nothing was evicted to make this happen
		#expect(router.pendingFailure(in: page) == nil)
		// closing twice is a no-op, not a second reap
		#expect(router.sessionClosed(page) == 0)
	}

	@Test("the lifecycle reap is what makes the cap affordable")
	func lifecycleMakesTheCapAffordable() throws {
		let router = EventRouter(maxSessions: 1)
		let first = RenderSessionID("first")
		try router.beginStrict(first)
		router.markLive(first)
		#expect(
			thrownFailure { try router.beginStrict(RenderSessionID("second")) }
				== .atCapacity(kind: .sessions, limit: 1)
		)

		// the socket closes: no pressure, no eviction, and the next render fits
		router.sessionClosed(first)
		try router.beginStrict(RenderSessionID("second"))
		#expect(router.contains(RenderSessionID("second")))
		#expect(router.sessionCount == 1)
	}
}
