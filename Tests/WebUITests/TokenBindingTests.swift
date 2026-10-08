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
import WebUIServer

// the render-token binding
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W0.1; AGENTS.md
// security invariant 11).
//
// before this, `WebUIServer` destructured the incoming token as `_` and routed
// every frame into one process-wide handler table. the invariant was documented,
// and implemented — but only inside `WebUIAuthExample`'s hand-rolled NIO server,
// so a host that used the framework's own server did not get it.
//
// the websocket leg is apple-only: `URLSessionWebSocketTask` does not exist in
// swift-corelibs-foundation. on linux the same path is driven by the
// `fullstack-smoke` gate.

/// the token the server minted for the last render, captured by the render
/// closure so the test can speak as that page.
private final class TokenBox: Sendable {
	private let value = Mutex<String?>(nil)

	func set(_ token: String) { value.withLock { $0 = token } }

	/// block until the render has happened.
	func wait(timeout: Duration = .seconds(5)) async -> String? {
		let deadline = ContinuousClock.now + timeout
		while ContinuousClock.now < deadline {
			if let token = value.withLock({ $0 }) { return token }
			try? await Task.sleep(for: .milliseconds(20))
		}
		return value.withLock { $0 }
	}
}

#if !os(Linux)

@Suite("render-token binding", .serialized)
struct TokenBindingTests {

	/// a page whose one control wires itself through `controlAttributes`, so its
	/// handler lands in the render's own session.
	private func pageWithControl(request: WebUIServerRequest, box: TokenBox) -> String {
		box.set(request.renderToken.value)
		let attrs = controlAttributes(id: "ctrl", handler: { _ in
			[FragmentUpdate(id: "hit", html: "hit")]
		})
		return WebUIDocument(title: "token test", body: "<div\(attrs)>x</div>").render()
	}

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

	@Test("the token a render minted routes to that render's handlers")
	func mintedTokenRoutes() async throws {
		let router = EventRouter()
		let box = TokenBox()

		try await withServer(
			requestRender: { request in pageWithControl(request: request, box: box) },
			router: router,
			assets: [],
			requireRenderToken: true,
			portBase: 26_000
		) { port in
			// render the page so the server mints a token and opens the session.
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			#expect(page.contains("data-component-id=\"ctrl\""))

			guard let token = await box.wait() else {
				Issue.record("the render never reported a token")
				return
			}
			#expect(!token.isEmpty)

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			let envelope = """
			{"type":"event","component":"ctrl","event":"click","data":{},"token":"\(token)"}
			"""
			try await socket.send(.string(envelope))
			let reply = try await receiveText(socket)
			#expect(reply.contains("\"update\""), "the page's own token must route: got \(reply)")
			#expect(reply.contains("hit"))
		}
	}

	@Test("a token this server never minted is refused and the socket is closed")
	func forgedTokenIsRefused() async throws {
		let router = EventRouter()
		let box = TokenBox()

		try await withServer(
			requestRender: { request in pageWithControl(request: request, box: box) },
			router: router,
			assets: [],
			requireRenderToken: true,
			portBase: 26_000
		) { port in
			_ = try await get("http://127.0.0.1:\(port)/")
			_ = await box.wait()

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			let envelope = """
			{"type":"event","component":"ctrl","event":"click","data":{},"token":"forged"}
			"""
			try await socket.send(.string(envelope))
			let reply = try await receiveText(socket)
			#expect(reply.contains("\"error\""))
			#expect(reply.contains("token"))

			// the refusal closes the connection, so the next read must fail.
			var closed = false
			do { _ = try await socket.receive() } catch { closed = true }
			#expect(closed, "a refused token must close the socket")
		}
	}

	@Test("a frame with no token is refused while enforcement is on")
	func missingTokenIsRefused() async throws {
		let router = EventRouter()
		let box = TokenBox()

		try await withServer(
			requestRender: { request in pageWithControl(request: request, box: box) },
			router: router,
			assets: [],
			requireRenderToken: true,
			portBase: 26_000
		) { port in
			_ = try await get("http://127.0.0.1:\(port)/")
			_ = await box.wait()

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			try await socket.send(.string(
				"{\"type\":\"event\",\"component\":\"ctrl\",\"event\":\"click\",\"data\":{}}"
			))
			let reply = try await receiveText(socket)
			#expect(reply.contains("\"error\""))
		}
	}

	@Test("with enforcement off, a tokenless frame still routes (1.x behaviour)")
	func enforcementOffKeepsCompatibility() async throws {
		let router = EventRouter()
		// the pre-session path: a host registers into the shared default session
		// and its page never carries a token.
		router.register({ _ in
			[FragmentUpdate(id: "legacy", html: "legacy-ok")]
		}, for: ComponentID("legacy-ctrl"))

		try await withServer(
			requestRender: { _ in
				WebUIDocument(title: "legacy", body: "<div>x</div>").render()
			},
			router: router,
			assets: [],
			requireRenderToken: false,
			portBase: 26_000
		) { port in
			_ = try await get("http://127.0.0.1:\(port)/")

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			try await socket.send(.string(
				"{\"type\":\"event\",\"component\":\"legacy-ctrl\",\"event\":\"click\",\"data\":{}}"
			))
			let reply = try await receiveText(socket)
			#expect(reply.contains("legacy-ok"), "a 1.x host must keep working: got \(reply)")
		}
	}
}

#endif