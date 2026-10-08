import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import WebUI
import WebUIServer

// handler outcomes
// (`.hermes/plans/2026-10-08_151549_GENERAL_WEB_CAPABILITY.md`, W0.2).
//
// `WSOutgoing.redirect`/`.state`/`.reload` have always been on the wire and the
// client engine has always handled them, but a handler could only return
// `[FragmentUpdate]` and `WebUIServer` only ever sent `.update` — so three
// messages were dead protocol, reachable by no shipped server. these tests pin
// both halves: the outcome→frame mapping, and that the frame actually leaves.

@Suite("handler outcomes")
struct HandlerOutcomeTests {

    // MARK: outcome → frame

    @Test("fragments map to one update frame")
    func fragmentsMapToUpdate() {
        let update = FragmentUpdate(id: "a", html: "<span>a</span>")
        let message = HandlerOutcome.fragments([update]).wireMessage
        guard case .update(let fragments, _)? = message else {
            Issue.record("expected an update frame, got \(String(describing: message))")
            return
        }
        #expect(fragments == [update])
    }

    @Test("an empty fragment list sends nothing — the pre-outcome behaviour")
    func emptyFragmentsAreSilent() {
        #expect(HandlerOutcome.fragments([]).wireMessage == nil)
    }

    @Test("a redirect maps to one redirect frame")
    func redirectMapsToRedirect() {
        guard case .redirect(let url, let replace)? = HandlerOutcome.redirect(to: "/next").wireMessage else {
            Issue.record("expected a redirect frame")
            return
        }
        #expect(url == "/next")
        #expect(replace == false)

        guard case .redirect(_, let replaceTrue)? = HandlerOutcome.redirect(to: "/x", replace: true).wireMessage else {
            Issue.record("expected a redirect frame")
            return
        }
        #expect(replaceTrue)
    }

    @Test("a state write maps to one state frame")
    func stateMapsToState() {
        guard case .state(let path, let value)? = HandlerOutcome.state(path: "user.tab", value: "billing").wireMessage else {
            Issue.record("expected a state frame")
            return
        }
        #expect(path == "user.tab")
        #expect(value == "billing")
    }

    @Test("a reload maps to one reload frame")
    func reloadMapsToReload() {
        guard case .reload? = HandlerOutcome.reload.wireMessage else {
            Issue.record("expected a reload frame")
            return
        }
    }

    @Test("a failure maps to one error frame carrying the code and message")
    func failureMapsToError() {
        guard case .error(let code, let message)? = HandlerOutcome.fail(code: "boom", message: "went wrong").wireMessage else {
            Issue.record("expected an error frame")
            return
        }
        #expect(code == "boom")
        #expect(message == "went wrong")
    }

    @Test("only redirect and reload count as navigation")
    func navigationClassification() {
        #expect(HandlerOutcome.redirect(to: "/a").navigates)
        #expect(HandlerOutcome.reload.navigates)
        #expect(!HandlerOutcome.fragments([]).navigates)
        #expect(!HandlerOutcome.state(path: "p", value: "v").navigates)
        #expect(!HandlerOutcome.fail(code: "c", message: "m").navigates)
    }

    // MARK: router wiring

    @Test("dispatch reports the full outcome; handle reports fragments")
    func dispatchAndHandleAgree() async {
        let router = EventRouter()
        router.register(outcome: { _ in .redirect(to: "/elsewhere") }, for: ComponentID("go"))
        router.register({ _ in [FragmentUpdate(id: "a", html: "A")] }, for: ComponentID("patch"))

        let navigated = await router.dispatch(EventData(component: ComponentID("go"), event: "click"))
        #expect(navigated.navigates)
        #expect(navigated.fragments.isEmpty)

        let patched = await router.dispatch(EventData(component: ComponentID("patch"), event: "click"))
        #expect(!patched.navigates)
        #expect(patched.fragments.count == 1)

        // the 1.x view still reads fragments.
        let viaHandle = await router.handle(EventData(component: ComponentID("patch"), event: "click"))
        #expect(viaHandle.first?.id == "a")

        // a fragment-only handler registered the old way is adapted, not lost.
        let adapted = await router.dispatch(EventData(component: ComponentID("patch"), event: "click"))
        #expect(adapted.fragments.first?.html == "A")
    }

    @Test("an unrouted component is an empty outcome, never a crash")
    func missingHandlerIsEmpty() async {
        let router = EventRouter()
        let outcome = await router.dispatch(EventData(component: ComponentID("nobody"), event: "click"))
        #expect(outcome.fragments.isEmpty)
        #expect(outcome.wireMessage == nil)
    }
}

#if !os(Linux)

/// the wire half: the frames must actually leave the server.
@Suite("handler outcomes over the wire", .serialized)
struct HandlerOutcomeWireTests {

    private func receiveText(_ socket: URLSessionWebSocketTask) async throws -> String {
        let message = try await socket.receive()
        switch message {
        case .data(let data): return String(decoding: data, as: UTF8.self)
        case .string(let string): return string
        @unknown default: return ""
        }
    }

    @Test("a redirect handler makes WebUIServer send a redirect frame")
    func redirectReachesTheWire() async throws {
        let router = EventRouter()
        // the pre-outcome server could not send this frame at all: this is the
        // C4 proof, on the wire rather than in a comment.
        router.register(outcome: { _ in .redirect(to: "/next") }, for: ComponentID("go"))

        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: router,
            assets: [],
            portBase: 27_000
        ) { port in
            _ = try await get("http://127.0.0.1:\(port)/")
            let socket = URLSession(configuration: .ephemeral)
                .webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(.string(
                "{\"type\":\"event\",\"component\":\"go\",\"event\":\"click\",\"data\":{}}"
            ))
            let reply = try await receiveText(socket)
            #expect(reply.contains("\"redirect\""), "got \(reply)")
            #expect(reply.contains("/next"))
        }
    }

    @Test("a state handler makes WebUIServer send a state frame")
    func stateReachesTheWire() async throws {
        let router = EventRouter()
        router.register(outcome: { _ in .state(path: "tab", value: "2") }, for: ComponentID("tab"))

        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: router,
            assets: [],
            portBase: 27_000
        ) { port in
            _ = try await get("http://127.0.0.1:\(port)/")
            let socket = URLSession(configuration: .ephemeral)
                .webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
            socket.resume()
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(.string(
                "{\"type\":\"event\",\"component\":\"tab\",\"event\":\"click\",\"data\":{}}"
            ))
            let reply = try await receiveText(socket)
            #expect(reply.contains("\"state\""), "got \(reply)")
            #expect(reply.contains("\"tab\""))
        }
    }
}

#endif