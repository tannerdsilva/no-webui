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

// the host-owned event-router seam
// (`WebUIServer.init(router:eventRouter:config:logger:)`).
//
// the typed `init(router:config:logger:)` mints its own event router, which is
// the right shape for a host whose handlers all register *during render*:
// `.onX` and `controlAttributes` write into the render's own session, and the
// server is the only thing that needs to hold the router.
//
// a host that wires handlers *explicitly* — `register(_:for:)`, whose default
// session is documented as the single-page host's path — has no handle on that
// minted router. its registrations land in a router nothing consults, and every
// interaction goes silently dead: no error, no warning, the page renders and
// the controls simply never answer.
//
// this suite pins the additive init that closes that hole. the second
// assertion is the one that fails if the seam regresses to minting its own
// router: the page still serves (a route table is a route table) while the
// click vanishes.

/// the flag a handler body sets, so the suite can assert the handler *ran*
/// rather than only that something was sent back.
private final class HitBox: Sendable {
	private let hit = Mutex(false)

	func mark() { hit.withLock { $0 = true } }
	var value: Bool { hit.withLock { $0 } }
}

#if !os(Linux)

// the websocket leg is apple-only: `URLSessionWebSocketTask` does not exist in
// swift-corelibs-foundation. on linux the same path is driven by the
// `fullstack-smoke` gate.

@Suite("host-owned event router", .serialized)
struct HostEventRouterSeamTests {

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

	@Test("a typed page route serves, and the host's own router receives the click")
	func hostOwnedRouterReceivesTheClick() async throws {
		let hits = HitBox()
		let eventRouter = EventRouter()
		// the 1.x registration shape: no session argument, so this lands in
		// `.default` — the documented single-page host's path, and the shape
		// arc-agent's ~64 hand-wired registrations use.
		eventRouter.register({ _ in
			hits.mark()
			return [FragmentUpdate(id: "hit", html: "hit")]
		}, for: "ctrl")

		let pageRouter = Router {
			Route.page("/") { _ in
				WebUIDocument(
					title: "seam",
					body: .trusted("<div id=\"ctrl\" data-component-id=\"ctrl\" data-event=\"click\">x</div>")
				)
			}
		}

		try await withHostRouterServer(pageRouter, eventRouter: eventRouter) { port in
			// 1. the typed route table answers the page.
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200, "the page route must serve; got \(status)")
			#expect(page.contains("data-component-id=\"ctrl\""), "got \(page.prefix(200))")

			// 2. the click reaches the handler the *host* registered. the frame
			// carries no token: the engine only stamps one when the page carried
			// a `RuntimeConfig(renderToken:)`, so with `requireRenderToken` off
			// (the default) this is the frame a token-less page really sends.
			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			let envelope = #"{"type":"event","component":"ctrl","event":"click","data":{}}"#
			try await socket.send(.string(envelope))
			let reply = try await receiveText(socket)
			#expect(reply.contains("\"update\""), "the host's handler must answer: got \(reply)")
			#expect(reply.contains("hit"))
		}

		// the reply alone would not prove dispatch — a fallback or an error frame
		// can also be non-empty — so the handler body's flag is the assertion.
		#expect(hits.value, "the handler body must have run")
	}

	@Test("pagePath does not mint a route on the typed path")
	func pagePathIsNotARoute() async throws {
		let eventRouter = EventRouter()
		let pageRouter = Router {
			Route.page("/") { _ in
				WebUIDocument(title: "root", body: .trusted("<p id=\"root\">root</p>"))
			}
			Route.page("/sole") { _ in
				WebUIDocument(title: "sole", body: .trusted("<p id=\"sole\">sole</p>"))
			}
		}

		// `pagePath` is still what the startup line reports, but on the typed path
		// the routes are the routing. this names a path nothing declares, so a
		// host that passes `pagePath:` expecting it to serve gets a 404 — which is
		// why the deprecated inits' `/index.html` alias is an explicit route here.
		var config = WebUIServerConfig()
		config.pagePath = "/other"

		try await withHostRouterServer(pageRouter, eventRouter: eventRouter, config: config) { port in
			let (root, rootStatus) = try await get("http://127.0.0.1:\(port)/")
			#expect(rootStatus == 200, "got \(rootStatus)")
			#expect(root.contains("id=\"root\""))

			let (sole, soleStatus) = try await get("http://127.0.0.1:\(port)/sole")
			#expect(soleStatus == 200, "a declared route beyond pagePath must serve; got \(soleStatus)")
			#expect(sole.contains("id=\"sole\""))

			let (_, otherStatus) = try await get("http://127.0.0.1:\(port)/other")
			#expect(otherStatus == 404, "pagePath must not mint a route on the typed path; got \(otherStatus)")
		}
	}
}
#endif