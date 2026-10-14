import Testing
import WebUI

// the render-session contract
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W0.1).
//
// the defect this pins: `.onClick(perform:)` mints its component id from a
// router-wide counter, so every render of every page appended a fresh `c0…cN`
// range to one shared handler table. on a long-lived server that table grew
// until `maxHandlers`, at which point `register` logged a warning and silently
// refused — the page's controls stopped routing with no error surfaced anywhere.
//
// verified against the pre-session implementation: the second render in
// `reRenderIsIdempotent` reports 4 handlers instead of 2, and `sessionsAreIsolated`
// cannot tell the two pages apart at all.

@Suite("render sessions")
struct RenderSessionTests {

    /// a page whose two controls are wired the auto-minted way — the shape that
    /// used to leak.
    @discardableResult
    private func renderAutoWiredPage(_ router: EventRouter, _ session: RenderSessionID) -> String {
        router.begin(session)
        let context = RenderContext(router: router, session: session)
        return RenderContext.$current.withValue(context) {
            Div {
                Div { Text("one") }.onClick { _ in [] }
                Div { Text("two") }.onClick { _ in [] }
            }.markup.html
        }
    }

    /// the same auto-wired page, rendered through a PRESERVING begin — the shape
    /// `WebUIServer`'s `navigate` answer uses. only the flag differs, so a
    /// difference in behaviour is attributable to the flag alone.
    @discardableResult
    private func renderAutoWiredPagePreserving(
        _ router: EventRouter,
        _ session: RenderSessionID
    ) -> String {
        router.begin(session, preservingRegistrations: true)
        let context = RenderContext(router: router, session: session)
        return RenderContext.$current.withValue(context) {
            Div {
                Div { Text("one") }.onClick { _ in [] }
                Div { Text("two") }.onClick { _ in [] }
            }.markup.html
        }
    }

    @Test("a re-render in the same session does not grow the handler table")
    func reRenderIsIdempotent() {
        let router = EventRouter()
        let session = RenderSessionID("page-1")

        let first = renderAutoWiredPage(router, session)
        #expect(router.handlerCount(in: session) == 2)

        let second = renderAutoWiredPage(router, session)
        #expect(
            router.handlerCount(in: session) == 2,
            "re-rendering must overwrite the same ids, not append new ones"
        )
        #expect(
            first == second,
            "the same page must mint the same ids on every render, so the markup is identical"
        )
    }

    @Test("two page instances cannot fire each other's handlers")
    func sessionsAreIsolated() async {
        let router = EventRouter()
        let pageA = RenderSessionID("page-a")
        let pageB = RenderSessionID("page-b")

        func render(_ session: RenderSessionID, label: String) {
            router.begin(session)
            let context = RenderContext(router: router, session: session)
            _ = RenderContext.$current.withValue(context) {
                Div { Text(label) }.onClick { _ in
                    [FragmentUpdate(id: label, html: label)]
                }.markup.html
            }
        }
        render(pageA, label: "a")
        render(pageB, label: "b")

        // both pages minted `c0` — the id is scoped to the session, not global,
        // so the same id names a different handler in each page.
        let click = EventData(component: ComponentID("c0"), event: "click")
        let fromA = await router.handle(click, in: pageA)
        let fromB = await router.handle(click, in: pageB)

        #expect(fromA.first?.id == "a", "page A's c0 must route to page A's handler")
        #expect(fromB.first?.id == "b", "page B's c0 must route to page B's handler")
    }

    @Test("ending a session drops exactly its handlers")
    func endIsScoped() {
        let router = EventRouter()
        let pageA = RenderSessionID("a")
        let pageB = RenderSessionID("b")

        renderAutoWiredPage(router, pageA)
        renderAutoWiredPage(router, pageB)
        #expect(router.sessionCount == 2)
        #expect(router.handlerCount == 4)

        let removed = router.end(pageA)
        #expect(removed == 2, "end returns how many handlers went with the session")
        #expect(router.sessionCount == 1)
        #expect(router.handlerCount == 2)
        #expect(router.handlerCount(in: pageA) == 0)
        #expect(router.handlerCount(in: pageB) == 2)
    }

    @Test("the session-less path still routes through the shared default session")
    func defaultSessionIsUnchanged() async {
        let router = EventRouter()
        let context = RenderContext(router: router)
        _ = RenderContext.$current.withValue(context) {
            Div { Text("x") }.onClick { _ in [FragmentUpdate(id: "hit", html: "hit")] }.markup.html
        }

        let updates = await router.handle(EventData(component: ComponentID("c0"), event: "click"))
        #expect(updates.first?.id == "hit")
        #expect(router.handlerCount(in: .default) == 1)
    }

    @Test("sessions are bounded, and eviction takes the least-recently-used")
    func sessionsAreBounded() {
        let router = EventRouter(maxSessions: 3)
        for index in 0..<10 {
            router.begin(RenderSessionID("p\(index)"))
        }

        #expect(router.sessionCount == 3, "the cap holds")
        #expect(router.handlerCount(in: RenderSessionID("p0")) == 0, "the oldest page is gone")

        // the newest page is still live and still accepts registrations.
        let newest = RenderSessionID("p9")
        router.register({ _ in [] }, for: ComponentID("x"), in: newest)
        #expect(router.handlerCount(in: newest) == 1)
    }

    @Test("the LRU ledger does not grow with registrations")
    func lruLedgerStaysBounded() {
        let router = EventRouter()
        let session = RenderSessionID("churn")
        for _ in 0..<2_000 {
            renderAutoWiredPage(router, session)
        }
        // the observable contract: one session, one page's worth of handlers —
        // regardless of how many times the page rendered.
        #expect(router.sessionCount == 1)
        #expect(router.handlerCount(in: session) == 2)
    }

    // MARK: preserving begin (the navigate re-render)

    // `WebUIServer.answerNavigate` re-renders a live page's own region IN PLACE.
    // it must not discard the handlers a host registered outside a render pass —
    // that is the whole point of `init(router:eventRouter:…)`, and dropping them
    // silences every control in the session with nothing on the wire to say so
    // (arc-agent's "stuck in Settings" freeze, UX-60).

    @Test("preserving begin keeps the host's table and still restarts the mint counters")
    func preservingBeginKeepsRegistrations() async {
        let router = EventRouter()
        // the hand-wired shape: registered outside any render pass.
        router.register(
            { _ in [FragmentUpdate(id: "hit", html: "hit")] },
            for: ComponentID("boot"), in: .default
        )
        #expect(router.handlerCount(in: .default) == 1)

        router.begin(.default, preservingRegistrations: true)
        #expect(
            router.handlerCount(in: .default) == 1,
            "an in-place re-render must not drop handlers the render did not register"
        )

        let first = renderAutoWiredPagePreserving(router, .default)
        #expect(router.handlerCount(in: .default) == 3, "the host's handler + the render's c0, c1")
        let second = renderAutoWiredPagePreserving(router, .default)
        #expect(
            router.handlerCount(in: .default) == 3,
            "the mint counter must still restart — the render's c0/c1 are reused, not appended"
        )
        #expect(first == second, "the same page must mint the same ids on every render")

        // the host's handler still routes after the re-render.
        let out = await router.handle(EventData(component: ComponentID("boot"), event: "click"))
        #expect(out.first?.id == "hit")

        router.begin(.default)  // the plain reset is unchanged
        #expect(router.handlerCount(in: .default) == 0, "the default reset must still wipe")
    }

    @Test("a re-render's own registration replaces a preserved one for the same id")
    func rerenderRegistrationWins() async {
        // render-time semantics must be preserved: the render's handler is
        // authoritative for the id it mints.
        let router = EventRouter()
        router.register(
            { _ in [FragmentUpdate(id: "old", html: "old")] },
            for: ComponentID("c0"), in: .default
        )
        router.begin(.default, preservingRegistrations: true)
        router.register(
            { _ in [FragmentUpdate(id: "new", html: "new")] },
            for: ComponentID("c0"), in: .default
        )
        let out = await router.handle(EventData(component: ComponentID("c0"), event: "click"))
        #expect(out.first?.id == "new")
        #expect(router.handlerCount(in: .default) == 1)
    }

    @Test("preserving begin is bounded across many re-renders")
    func preservingBeginStaysBounded() {
        let router = EventRouter()
        let session = RenderSessionID("churn")
        router.register({ _ in [] }, for: ComponentID("boot"), in: session)
        for _ in 0..<2_000 {
            router.begin(session, preservingRegistrations: true)
            router.register({ _ in [] }, for: ComponentID("c0"), in: session)
        }
        #expect(router.handlerCount(in: session) == 2, "keys are overwritten, not appended")
    }
}