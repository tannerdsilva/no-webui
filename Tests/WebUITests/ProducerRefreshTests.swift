import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIServer

// the producer's refresh door (`.hermes/plans/2026-11-13_101839-arc-overlay-elimination-program.md`
// Phase 2, Task 2.2; plan §8, D-8).
//
// `HandlerOutcome.refresh` needs an event to answer: the outcome carries no
// session, so the dispatch session is the authority and no handler can name
// another page. a producer — a file that landed, a background job that finished,
// a store another writer owns — has no event of its own. `WebUIServer.refresh(session:)`
// is that door, and it must be the SAME pass: the remembered page, the
// remembered principal, this session's diff baseline, `fanOut` to this session's
// sockets. these tests are the acceptance as bytes on a real socket, not as a
// claim about the call graph:
//
//   a. two renders are two sessions; a socket bound by ping receives an `update`
//      carrying the mutated value after a refresh with NO client event
//   b. the second session receives nothing — asserted by frame ORDER (its next
//      frame is the pong that follows our own ping), never by waiting for silence
//   c. a session whose remembered page was evicted answers its sockets with the
//      existing `refresh` error frame
//
// the websocket leg is apple-only: `URLSessionWebSocketTask` does not exist in
// swift-corelibs-foundation.

#if !os(Linux)

@Suite("producer refresh — WebUIServer.refresh(session:)", .serialized)
struct ProducerRefreshTests {

	// MARK: the page

	/// the value the page reads — `Mutex`-backed because the render closure is
	/// `@Sendable` and the test mutates the same counter from its own task.
	final class Counter: Sendable {
		private let value = Mutex(0)

		func read() -> Int { value.withLock { $0 } }

		func bump() { value.withLock { $0 += 1 } }
	}

	// MARK: - the generated registrar

	/// a compiled `@WireGroup` fixture whose handler answers `HandlerOutcome`.
	///
	/// this is the one path neither the expansion snapshot nor the router-level
	/// dispatch covers: the macro's emitted `register(outcome:)` closure, called
	/// by a live server dispatching a socket frame, returning `.refresh`, and
	/// the same session re-render shipping the diff back over that socket.
	@WireGroup("producer_e2e")
	struct ProducerE2EWiring {
		let counter: Counter

		@Wired("e2e-refresh", events: [.click])
		func refresh(_ event: EventData) async -> HandlerOutcome {
			counter.bump()
			return .refresh
		}
	}

	/// every render token this server minted, in render order.
	///
	/// an ARRAY, not one box: two renders are two sessions, and a refresh is
	/// addressed by the token a page was rendered under. recording the count
	/// before a render is also what makes the harness's own readiness probe
	/// harmless — it renders the page once before the test body starts, so
	/// offsets, not absolute indices, are the honest addressing.
	private final class TokenJournal: Sendable {
		private let tokens = Mutex<[String]>([])

		func record(_ token: String) {
			tokens.withLock { $0.append(token) }
		}

		func count() -> Int { tokens.withLock { $0.count } }

		/// the token of the render at `index`, waiting for it to land.
		func token(at index: Int, timeout: Duration = .seconds(5)) async -> String? {
			let deadline = ContinuousClock.now + timeout
			while ContinuousClock.now < deadline {
				if let token = tokens.withLock({ $0.indices.contains(index) ? $0[index] : nil }) {
					return token
				}
				try? await Task.sleep(for: .milliseconds(20))
			}
			return tokens.withLock { $0.indices.contains(index) ? $0[index] : nil }
		}
	}

	/// the page: one addressable region (`id` AND `data-component-id`, because
	/// the default region policy keys by the component attribute and the client
	/// patches by DOM id) whose text is the counter.
	///
	/// the token the render was minted with is echoed into the runtime config, so
	/// a refresh — which re-renders with the SAME token — reproduces the head
	/// byte for byte and only the counter's region can move.
	private func page(
		_ request: WebUIServerRequest,
		counter: Counter,
		journal: TokenJournal
	) -> String {
		journal.record(request.renderToken.value)
		let value = counter.read()
		let body = """
		<div id="webui-page"><p id="counter" data-component-id="counter">\(value)</p></div>
		"""
		return WebUIDocument(
			title: "producer refresh",
			body: .trusted(body),
			runtimeConfig: RuntimeConfig(renderToken: request.renderToken.value)
		).markup.html
	}

	// MARK: the wire

	private func openSocket(port: Int) -> URLSessionWebSocketTask {
		let socket = URLSession(configuration: .ephemeral)
			.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
		socket.resume()
		return socket
	}

	private func receiveText(_ socket: URLSessionWebSocketTask) async throws -> String {
		let message = try await socket.receive()
		switch message {
		case .data(let data): return String(decoding: data, as: UTF8.self)
		case .string(let string): return string
		@unknown default: return ""
		}
	}

	/// a frame await that cannot hang the suite.
	///
	/// `withThrowingTaskGroup` WAITS for a cancelled child, and
	/// `URLSessionWebSocketTask.receive()` does not return when its task is
	/// cancelled — so the textbook timeout shape wedges the run instead of failing
	/// it. here the continuation is resumed exactly once, by whichever finishes
	/// first: the read, or a deadline task. the losing read is left to unwind when
	/// the socket closes in the caller's `defer`.
	private func nextFrame(
		_ socket: URLSessionWebSocketTask,
		timeout: Duration = .seconds(5)
	) async throws -> String {
		let gate = ResumeGate()
		return try await withCheckedThrowingContinuation { continuation in
			gate.install(continuation)
			Task {
				do { gate.resume(.success(try await receiveText(socket))) }
				catch { gate.resume(.failure(error)) }
			}
			Task {
				try? await Task.sleep(for: timeout)
				gate.resume(.failure(FrameDeadlineExceeded()))
			}
		}
	}

	/// a `CheckedContinuation` resumed at most once, from either of two racing
	/// tasks. a second resume traps, so the guard is not optional politeness — it
	/// is what turns "the deadline fired" into a test failure instead of a crash.
	private final class ResumeGate: Sendable {
		private struct State: Sendable {
			var continuation: CheckedContinuation<String, any Error>?
			var resumed = false
		}

		private let state = Mutex(State())

		func install(_ continuation: CheckedContinuation<String, any Error>) {
			let alreadyResumed = state.withLock { state -> Bool in
				guard !state.resumed else { return true }
				state.continuation = continuation
				return false
			}
			if alreadyResumed { continuation.resume(throwing: FrameDeadlineExceeded()) }
		}

		func resume(_ result: Result<String, any Error>) {
			let continuation = state.withLock { state -> CheckedContinuation<String, any Error>? in
				guard !state.resumed else { return nil }
				state.resumed = true
				let pending = state.continuation
				state.continuation = nil
				return pending
			}
			guard let continuation else { return }
			continuation.resume(with: result)
		}
	}

	struct FrameDeadlineExceeded: Error, CustomStringConvertible {
		var description: String { "no frame arrived within the deadline" }
	}

	private func frameType(_ frame: String) -> String? {
		guard let data = frame.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }
		return object["type"] as? String
	}

	private func fragments(in frame: String) -> [[String: Any]] {
		guard let data = frame.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let fragments = object["fragments"] as? [[String: Any]]
		else { return [] }
		return fragments
	}

	private func errorFields(in frame: String) -> (code: String?, message: String?) {
		guard let data = frame.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return (nil, nil) }
		return (object["code"] as? String, object["message"] as? String)
	}

	private func pingFrame(_ token: String) -> String {
		"{\"type\":\"ping\",\"token\":\"\(token)\"}"
	}

	// MARK: - a. the door reaches its own session

	@Test("refresh(session:) with no client event updates that session's page — and a second session receives nothing")
	func refreshReachesItsSession() async throws {
		let counter = Counter()
		let journal = TokenJournal()
		let router = EventRouter()

		try await withServerHandle(
			requestRender: { page($0, counter: counter, journal: journal) },
			router: router,
			assets: [],
			requireRenderToken: true,
			portBase: 52_000
		) { server, port in
			// render A, then render B: two renders, two tokens, two sessions.
			let indexA = journal.count()
			_ = try await get("http://127.0.0.1:\(port)/")
			guard let tokenA = await journal.token(at: indexA) else {
				Issue.record("render A reported no token")
				return
			}
			let indexB = journal.count()
			_ = try await get("http://127.0.0.1:\(port)/")
			guard let tokenB = await journal.token(at: indexB) else {
				Issue.record("render B reported no token")
				return
			}
			#expect(!tokenA.isEmpty && !tokenB.isEmpty)
			#expect(tokenA != tokenB, "two renders must mint two sessions")

			let socketA = openSocket(port: port)
			defer { socketA.cancel(with: .normalClosure, reason: nil) }
			let socketB = openSocket(port: port)
			defer { socketB.cancel(with: .normalClosure, reason: nil) }

			// binding is LAZY: a socket that only connects is not in the index.
			let bindingsBefore = await server.refreshStateCounts.bindings
			#expect(bindingsBefore == 0, "a connect-only socket must not be in the session index")

			try await socketA.send(.string(pingFrame(tokenA)))
			#expect(try await frameType(nextFrame(socketA)) == "pong")
			try await socketB.send(.string(pingFrame(tokenB)))
			#expect(try await frameType(nextFrame(socketB)) == "pong")

			let bindingsAfter = await server.refreshStateCounts.bindings
			#expect(bindingsAfter == 2, "both pings must have bound their socket; got \(bindingsAfter)")

			// the mutation happens server-side. no client event is sent: the
			// refresh below is the ONLY reason a frame would arrive.
			counter.bump()
			let refresh = Task { await server.refresh(session: RenderSessionID(tokenA)) }

			let frameA = try await nextFrame(socketA)
			print("producer refresh: A <- \(frameA)")
			#expect(
				frameType(frameA) == "update",
				"a producer refresh must answer its session with an update; got \(frameA.prefix(200))"
			)
			let updates = fragments(in: frameA)
			let region = updates.first { ($0["id"] as? String) == "counter" }
			let html = region?["html"] as? String ?? ""
			#expect(region != nil, "the changed region must ship by its own id; got \(updates)")
			#expect(html.contains(">1<"), "the fragment must carry the mutated value; got \(html)")
			#expect(!html.contains(">0<"), "the fragment must not carry the stale value; got \(html)")
			#expect(
				updates.count == 1,
				"one region moved, so exactly one fragment ships; got \(updates.count)"
			)

			// the refresh pass is complete before the order assertion on B: a
			// pending write to B's channel would otherwise race our own ping.
			await refresh.value

			// session B receives NOTHING from A's refresh. asserted by frame
			// ORDER: B's next frame is the pong to our own ping, never an update —
			// waiting for silence would pass on a stuck socket, which is exactly
			// the failure this suite is written not to have.
			try await socketB.send(.string(pingFrame(tokenB)))
			let frameB = try await nextFrame(socketB)
			#expect(
				frameType(frameB) == "pong",
				"a second session must receive nothing from A's refresh; got \(frameB.prefix(200))"
			)
		}
	}

	// MARK: - b. no page, no silence

	@Test("a session whose remembered page was evicted answers its sockets with the refresh error frame")
	func evictedSessionAnswersTheErrorFrame() async throws {
		let counter = Counter()
		let journal = TokenJournal()
		// the router and the config share the cap, like the typed init does: one
		// session is all this server can remember.
		let router = EventRouter(maxSessions: 1)

		try await withServerHandle(
			requestRender: { page($0, counter: counter, journal: journal) },
			router: router,
			assets: [],
			requireRenderToken: true,
			maxSessions: 1,
			portBase: 52_100
		) { server, port in
			let indexA = journal.count()
			_ = try await get("http://127.0.0.1:\(port)/")
			guard let tokenA = await journal.token(at: indexA) else {
				Issue.record("render A reported no token")
				return
			}

			let socketA = openSocket(port: port)
			defer { socketA.cancel(with: .normalClosure, reason: nil) }
			// bind while A is still the router's session: a ping naming an evicted
			// token is refused (requireRenderToken), so the order is load → bind →
			// evict, which is also a real page's order.
			try await socketA.send(.string(pingFrame(tokenA)))
			#expect(try await frameType(nextFrame(socketA)) == "pong")

			// render B: at `maxSessions: 1` this evicts A's remembered page and
			// A's router session. A's socket stays bound to A — the baseline is
			// gone, the binding is not.
			let indexB = journal.count()
			_ = try await get("http://127.0.0.1:\(port)/")
			guard await journal.token(at: indexB) != nil else {
				Issue.record("render B reported no token")
				return
			}

			await server.refresh(session: RenderSessionID(tokenA))

			let frame = try await nextFrame(socketA)
			print("producer refresh: evicted A <- \(frame)")
			#expect(
				frameType(frame) == "error",
				"a session with no page must be answered, never ignored; got \(frame.prefix(200))"
			)
			let error = errorFields(in: frame)
			#expect(error.code == "refresh", "the error frame's code names the door; got \(String(describing: error.code))")
			#expect(
				(error.message ?? "").contains("no page to refresh"),
				"the error frame's text names the reason; got \(String(describing: error.message))"
			)
		}
	}

	// MARK: - c. the generated registrar's outcome reaches the same pass

	@Test("a generated @Wired HandlerOutcome refreshes the page over a real socket")
	func generatedOutcomeRegistrarRefreshes() async throws {
		let counter = Counter()
		let journal = TokenJournal()
		let router = EventRouter()
		// the host table, before `start()` seals it — the registrar's documented
		// shape, and the table a tokenless dispatch consults.
		ProducerE2EWiring(counter: counter).wireGroup_producer_e2e(router)

		try await withServerHandle(
			requestRender: { page($0, counter: counter, journal: journal) },
			router: router,
			assets: [],
			requireRenderToken: true,
			portBase: 52_200
		) { _, port in
			let index = journal.count()
			_ = try await get("http://127.0.0.1:\(port)/")
			guard let token = await journal.token(at: index) else {
				Issue.record("the render reported no token")
				return
			}

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }
			try await socket.send(.string(pingFrame(token)))
			#expect(try await frameType(nextFrame(socket)) == "pong")

			// the only thing that moves the counter is the generated handler.
			let event = """
			{"type":"event","component":"e2e-refresh","event":"click","data":{},"token":"\(token)"}
			"""
			try await socket.send(.string(event))

			let frame = try await nextFrame(socket)
			print("producer refresh: generated outcome <- \(frame)")
			#expect(
				frameType(frame) == "update",
				"the outcome path must ship the refresh diff; got \(frame.prefix(200))"
			)
			let region = fragments(in: frame).first { ($0["id"] as? String) == "counter" }
			let html = region?["html"] as? String ?? ""
			#expect(region != nil, "the changed region must ship; got \(fragments(in: frame))")
			#expect(html.contains(">1<"), "the generated handler's mutation must be visible; got \(html)")
		}
	}
}

#endif
