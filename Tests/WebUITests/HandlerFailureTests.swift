import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import WebUI
import WebUIServer

// handler failure
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W0.3; defect C3).
//
// `EventHandler` was `async -> [FragmentUpdate]`: it *could not* throw. so a
// handler whose work failed had exactly one way to report it — return an empty
// array — which the router treats as "handled, nothing changed". the interaction
// went dead and the page was never told. the server's own dispatch comment
// admitted the gap.
//
// now `OutcomeHandler` is `async throws`, the router catches the throw into
// `.fail(code:message:fallback:)`, and the failure reaches the observer funnel
// and (per policy) the page.

/// an observer that records what the router reports.
private final class EventRecorder: Observable {
    private let events = Mutex<[ObservableEvent]>([])

    func observe(_ event: ObservableEvent) {
        events.withLock { $0.append(event) }
    }

    /// the messages of every `.error` event seen.
    var errors: [String] {
        events.withLock { $0 }.compactMap {
            if case .error(let message) = $0 { return message }
            return nil
        }
    }
}

private struct Boom: Error, CustomStringConvertible {
    var description: String { "the database is on fire" }
}

@Suite("handler failure")
struct HandlerFailureTests {

    // MARK: the router

    @Test("a throwing handler becomes a failure outcome, not a silent empty list")
    func throwingHandlerBecomesFailure() async {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))

        let outcome = await router.dispatch(EventData(component: ComponentID("boom"), event: "click"))
        #expect(outcome.isFailure)
        guard case .fail(let code, let message, _) = outcome else {
            Issue.record("expected a failure outcome")
            return
        }
        #expect(code == "handler")
        #expect(message.contains("the database is on fire"), "got \(message)")
        #expect(message.isEmpty == false)
    }

    @Test("a failure reaches the observer funnel")
    func failureReachesObservers() async {
        let router = EventRouter()
        let recorder = EventRecorder()
        router.observers.add(recorder)
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))

        _ = await router.dispatch(EventData(component: ComponentID("boom"), event: "click"))

        let errors = recorder.errors
        #expect(errors.count == 1, "got \(errors)")
        #expect(errors.first?.contains("the database is on fire") == true)
    }

    @Test("a registered fallback rides along in the failure outcome")
    func fallbackRidesAlong() async {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))
        router.register(fallback: { _ in
            [FragmentUpdate(id: "boom", html: "<span>try again</span>")]
        }, for: ComponentID("boom"))

        let outcome = await router.dispatch(EventData(component: ComponentID("boom"), event: "click"))
        guard case .fail(_, _, let fallback) = outcome else {
            Issue.record("expected a failure outcome")
            return
        }
        #expect(fallback.count == 1)
        #expect(fallback.first?.html.contains("try again") == true)

        // the page gets both frames, error first.
        let frames = outcome.wireMessages
        #expect(frames.count == 2)
        guard case .error? = frames.first else {
            Issue.record("the error must lead")
            return
        }
    }

    @Test("a non-throwing handler is unaffected — no try required at the call site")
    func nonThrowingHandlersStillWork() async {
        let router = EventRouter()
        router.register(outcome: { _ in .redirect(to: "/fine") }, for: ComponentID("fine"))

        let outcome = await router.dispatch(EventData(component: ComponentID("fine"), event: "click"))
        #expect(!outcome.isFailure)
        #expect(outcome.navigates)
    }

    @Test("a failure carries no fragments when no fallback is registered")
    func noFallbackNoFragments() async {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))

        let outcome = await router.dispatch(EventData(component: ComponentID("boom"), event: "click"))
        #expect(outcome.fragments.isEmpty)
        // exactly one frame: the error. nothing is invented to fill the gap.
        #expect(outcome.wireMessages.count == 1)
    }
}

#if !os(Linux)

/// the wire half: "surfaced as a console log only" must stop being true.
@Suite("handler failure over the wire", .serialized)
struct HandlerFailureWireTests {

    private func receiveText(_ socket: URLSessionWebSocketTask) async throws -> String {
        let message = try await socket.receive()
        switch message {
        case .data(let data): return String(decoding: data, as: UTF8.self)
        case .string(let string): return string
        @unknown default: return ""
        }
    }

    private func openSocket(port: Int) -> URLSessionWebSocketTask {
        let socket = URLSession(configuration: .ephemeral)
            .webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        socket.resume()
        return socket
    }

    @Test("a throwing handler sends an error frame to the page")
    func failureReachesThePage() async throws {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))

        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: router,
            assets: [],
            portBase: 28_000
        ) { port in
            _ = try await get("http://127.0.0.1:\(port)/")
            let socket = openSocket(port: port)
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(.string(
                "{\"type\":\"event\",\"component\":\"boom\",\"event\":\"click\",\"data\":{}}"
            ))
            let reply = try await receiveText(socket)
            #expect(reply.contains("\"error\""), "got \(reply)")
            #expect(reply.contains("on fire"), "the message must name the cause: got \(reply)")
        }
    }

    @Test("a failure with a fallback sends the error and then the fallback fragment")
    func fallbackReachesThePage() async throws {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))
        router.register(fallback: { _ in
            [FragmentUpdate(id: "boom", html: "<span>try again</span>")]
        }, for: ComponentID("boom"))

        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: router,
            assets: [],
            portBase: 28_000
        ) { port in
            _ = try await get("http://127.0.0.1:\(port)/")
            let socket = openSocket(port: port)
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(.string(
                "{\"type\":\"event\",\"component\":\"boom\",\"event\":\"click\",\"data\":{}}"
            ))
            let first = try await receiveText(socket)
            #expect(first.contains("\"error\""), "got \(first)")
            let second = try await receiveText(socket)
            #expect(second.contains("\"update\""), "got \(second)")
            #expect(second.contains("try again"))
        }
    }

    @Test("under `.log` the page is not told, and the socket stays ordered and open")
    func logPolicySendsNothing() async throws {
        let router = EventRouter()
        router.register(outcome: { _ -> HandlerOutcome in throw Boom() }, for: ComponentID("boom"))

        try await withServer(
            requestRender: { _ in "<!DOCTYPE html><html><body>x</body></html>" },
            router: router,
            assets: [],
            handlerFailurePolicy: .log,
            portBase: 28_000
        ) { port in
            _ = try await get("http://127.0.0.1:\(port)/")
            let socket = openSocket(port: port)
            defer { socket.cancel(with: .normalClosure, reason: nil) }

            try await socket.send(.string(
                "{\"type\":\"event\",\"component\":\"boom\",\"event\":\"click\",\"data\":{}}"
            ))
            // the failing event must produce no frame, so the very next frame on
            // this ordered connection is the pong for the ping sent after it.
            try await socket.send(.string("{\"type\":\"ping\"}"))
            let reply = try await receiveText(socket)
            #expect(reply.contains("\"pong\""), "an error frame leaked past `.log`: got \(reply)")
        }
    }
}

#endif