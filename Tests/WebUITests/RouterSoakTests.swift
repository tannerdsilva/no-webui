import Testing
import WebUI

// the soak that proves the router's state is bounded
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W0.1 step 8).
//
// `RenderSessionTests` proves the *unit* contract. this proves the property the
// server actually depends on: rendering the same page for as long as a process
// lives must not accumulate routing state, and the page's controls must still
// work at the end. before sessions, this rendered 20,000 handlers for a 2-handler
// page and then started refusing registrations at the 10k cap.

@Suite("router soak")
struct RouterSoakTests {

    private static let renders = 10_000

    @Test("10k renders of a page keep its handler table at one page's worth")
    func stateIsBounded() {
        let router = EventRouter()
        let session = RenderSessionID("soak")

        for _ in 0..<Self.renders {
            router.begin(session)
            let context = RenderContext(router: router, session: session)
            _ = RenderContext.$current.withValue(context) {
                Div {
                    Div { Text("a") }.onClick { _ in [] }
                    Div { Text("b") }.onClick { _ in [] }
                }.markup.html
            }
        }

        #expect(router.handlerCount(in: session) == 2, "a 2-control page holds 2 handlers after 10k renders")
        #expect(router.handlerCount == 2)
        #expect(router.sessionCount == 1)
    }

    @Test("a control still routes on render 10,000")
    func stillRoutesAfterSoak() async {
        let router = EventRouter()
        let session = RenderSessionID("soak")

        for index in 0..<Self.renders {
            router.begin(session)
            let context = RenderContext(router: router, session: session)
            _ = RenderContext.$current.withValue(context) {
                Div { Text("\(index)") }.onClick { _ in
                    [FragmentUpdate(id: "alive", html: "\(index)")]
                }.markup.html
            }
        }

        let updates = await router.handle(
            EventData(component: ComponentID("c0"), event: "click"),
            in: session
        )
        #expect(updates.first?.id == "alive", "the last render's handler is live")
        #expect(updates.first?.html == "\(Self.renders - 1)")
    }
}