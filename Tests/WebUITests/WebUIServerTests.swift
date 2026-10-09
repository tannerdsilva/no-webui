import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Testing
import WebUI
import WebUIDesignSystem
import WebUIServer

// MARK: - WebUIServer integration

@Suite("WebUIServer", .serialized)
struct WebUIServerTests {
	@Test("serves the page and assets, 404s, and round-trips a ws event")
	func serveAndRoundTrip() async throws {
		let router = EventRouter()
		router.register({ _ in
			[FragmentUpdate(id: "round-trip-target", html: "<span id=\"round-trip-target\">round-trip-ok</span>")]
		}, for: ComponentID("test-btn"))

		let render: @Sendable () -> String = {
			let body = VStack(spacing: 16) {
				WebUIButton("Go", variant: .primary)
			}
			.padding(24)
			.renderThroughBuffer()
			return WebUIDocument(title: "WebUI Server Test", body: body).renderThroughBuffer()
		}

		for offset in 0..<10 {
			let port = 19999 + offset * 7
			let server = WebUIServer(
				render: render,
				router: router,
				config: WebUIServerConfig(host: "127.0.0.1", port: port)
			)
			let serverTask = Task { try await server.start() }
			do {
				try await waitUntilReady(port: port)
				try await assertServing(port: port)
				await server.stop()
				serverTask.cancel()
				return
			} catch {
				await server.stop()
				serverTask.cancel()
			}
		}
		Issue.record("no free test port found")
	}

	// MARK: helpers

	private func waitUntilReady(port: Int) async throws {
		for _ in 0..<60 {
			if let (_, status) = try? await get("http://127.0.0.1:\(port)/"), status == 200 {
				return
			}
			try await Task.sleep(for: .milliseconds(50))
		}
		throw ServerTestError.notReady
	}

	private func assertServing(port: Int) async throws {
		let (pageHTML, status) = try await get("http://127.0.0.1:\(port)/")
		#expect(status == 200)
		#expect(pageHTML.contains("WebUI Server Test"))
		#expect(pageHTML.contains("<button"))

		let (css, cssStatus) = try await get("http://127.0.0.1:\(port)/__assets/css")
		#expect(cssStatus == 200)
		#expect(css.contains(".button"))

		// content-addressed route: served immutable.
		let (hashCSS, hashStatus) = try await get("http://127.0.0.1:\(port)\(DesignSystemAssets.stylesheetURL)")
		#expect(hashStatus == 200)
		#expect(hashCSS.contains(".button"))

		let (_, missingStatus) = try await get("http://127.0.0.1:\(port)/missing")
		#expect(missingStatus == 404)

		// `URLSessionWebSocketTask` does not exist in swift-corelibs-foundation,
		// so the websocket leg of this test is apple-only. the ws dispatch path
		// is still covered on linux, out of band: the verification workflow's
		// raw-socket bench drives `ping`/`event` frames against this same server
		// and asserts the `update` reply (`run-bench.sh`, ws + wsburst modes).
		#if !os(Linux)
		let socket = URLSession(configuration: .ephemeral)
			.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
		socket.resume()
		defer { socket.cancel(with: .normalClosure, reason: nil) }
		let envelope =
			"{\"type\":\"event\",\"component\":\"test-btn\",\"event\":\"click\",\"data\":{}}"
		try await socket.send(.string(envelope))
		let data = try await receiveData(socket)
		let text = String(decoding: data, as: UTF8.self)
		#expect(text.contains("\"update\""))
		#expect(text.contains("round-trip-ok"))
		#endif
	}

	private func get(_ url: String) async throws -> (String, Int) {
		var request = URLRequest(url: URL(string: url)!)
		request.timeoutInterval = 5
		let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
		return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
	}

	#if !os(Linux)
	private func receiveData(_ socket: URLSessionWebSocketTask) async throws -> Data {
		let message = try await socket.receive()
		switch message {
		case .data(let data):
			return data
		case .string(let string):
			return Data(string.utf8)
		@unknown default:
			return Data()
		}
	}
	#endif
}

// MARK: - W3.4 typed responses from a render

/// a render answers with a typed ``HTTPResponse`` now: status, headers,
/// cookies, redirect. these tests pin the four behaviours the wave names —
/// redirect → 303 + Location, the `.html` body still carrying the auto-CSP +
/// a fresh nonce, `Set-Cookie` surviving, and the deprecated String render
/// inits still compiling and serving their page. (plan w3.4)
@Suite("typed responses from a render", .serialized)
struct TypedResponseTests {

	@Test("a render returning .redirect yields 303 with the right Location")
	func redirectYields303() async throws {
		try await withRouterServer(
			Router {
				// "/" answers 200 so the harness's readiness probe (a GET
				// expecting 200) completes; the redirects live on routes
				// nobody else probes.
				Route.get("/") { _ in
					HTTPResponse(body: .text("ready"))
				}
				Route.get("/go") { _ in
					HTTPResponse(body: .redirect(to: "/login"))
				}
				Route.get("/moved") { _ in
					HTTPResponse(body: .redirect(to: "/elsewhere", status: HTTPStatus(302)))
				}
			},
			portBase: 34000
		) { port in
			let (_, status, headers) = try await getWithHeaders("http://127.0.0.1:\(port)/go")
			#expect(status == 303)
			#expect(headers["location"] == "/login")

			let (_, movedStatus, movedHeaders) = try await getWithHeaders("http://127.0.0.1:\(port)/moved")
			#expect(movedStatus == 302)
			#expect(movedHeaders["location"] == "/elsewhere")
		}
	}

	@Test("a .html body still carries the auto-CSP + a fresh nonce, and Set-Cookie survives")
	func htmlKeepsCSPNonceAndCookies() async throws {
		try await withRouterServer(
			Router {
				Route.get("/") { _ in
					let html = WebUIDocument(
						title: "typed response page",
						body: "<main>ride-through</main>"
					).renderThroughBuffer()
					return HTTPResponse(
						cookies: [
							HTTPCookie(
								name: "sid",
								value: "abc123",
								attributes: HTTPCookie.Attributes(path: "/", httpOnly: true, sameSite: .lax)
							)
						],
						body: .html(html)
					)
				}
			},
			portBase: 34050
		) { port in
			let (html, status, headers) = try await getWithHeaders("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			// security invariant 1: the served document still carries the
			// auto-csp, and every inline script a nonce the policy names.
			#expect(html.contains("Content-Security-Policy"))
			guard let nonce = firstNonce(in: html) else {
				Issue.record("no nonce-carrying inline script found in the served document")
				return
			}
			#expect(html.contains("'nonce-\(nonce)'"))
			// a fresh render mints a fresh nonce: the second request differs.
			let (second, _, _) = try await getWithHeaders("http://127.0.0.1:\(port)/")
			if let secondNonce = firstNonce(in: second) {
				#expect(secondNonce != nonce)
			}
			// Set-Cookie survives through the typed response.
			#expect(headers["set-cookie"]?.contains("sid=abc123") == true)
		}
	}

	@Test("the deprecated String render inits still compile and serve their page")
	func deprecatedRenderInitsStillServe() async throws {
		// compiling through the deprecated `render:` and `requestRender:`
		// overloads is the claim that matters — the deprecation warnings are
		// the point, exactly as in DeprecatedVocabularyTests.
		let unbound = WebUIServer(
			render: {
				WebUIDocument(title: "deprecated render page", body: "<p>a</p>").renderThroughBuffer()
			},
			router: EventRouter()
		)
		let pathAware = WebUIServer(
			requestRender: { request in
				WebUIDocument(title: "deprecated requestRender page", body: "<p>\(request.path)</p>").renderThroughBuffer()
			},
			router: EventRouter()
		)
		_ = unbound
		_ = pathAware
		// and one of them serves end-to-end, the string wrapped as `.html`.
		try await withServer(
			requestRender: { _ in
				WebUIDocument(title: "deprecated requestRender page", body: "<p>b</p>").renderThroughBuffer()
			},
			router: EventRouter(),
			assets: [],
			portBase: 35000
		) { port in
			let (html, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			#expect(html.contains("deprecated requestRender page"))
		}
	}

	@Test("a websocket handler returning .response drives a redirect frame")
	func responseOutcomeRedirectsOnTheWire() {
		let outcome = HandlerOutcome.response(HTTPResponse(body: .redirect(to: "/signed-out")))
		guard case .redirect(let url, let replace)? = outcome.wireMessages.first else {
			Issue.record("expected a redirect frame, got \(outcome.wireMessages)")
			return
		}
		#expect(url == "/signed-out")
		#expect(replace == false)
		#expect(outcome.navigates)
		// a body-carrying response has no response head on a websocket: silent.
		let silent = HandlerOutcome.response(HTTPResponse(body: .text("hello")))
		#expect(silent.wireMessages.isEmpty)
		#expect(!silent.navigates)
	}

	// MARK: helpers

	private func firstNonce(in html: String) -> String? {
		guard let match = html.firstMatch(of: /nonce="([^"]+)"/) else { return nil }
		return String(match.1)
	}

	/// a session whose task delegate declines every http redirect, so the
	/// 3xx the render produced is the response the caller sees (its status and
	/// `Location`), not the final page.
	private static let nonRedirectingSession: URLSession = {
		let delegate = NonRedirectDelegate()
		return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
	}()

	private func getWithHeaders(_ url: String) async throws -> (String, Int, [String: String]) {
		var request = URLRequest(url: URL(string: url)!)
		request.timeoutInterval = 5
		let (data, response) = try await Self.nonRedirectingSession.data(for: request)
		let http = response as? HTTPURLResponse
		var headers: [String: String] = [:]
		for (key, value) in http?.allHeaderFields ?? [:] {
			headers[(key as? String)?.lowercased() ?? ""] = "\(value)"
		}
		return (String(decoding: data, as: UTF8.self), http?.statusCode ?? 0, headers)
	}
}

/// declines every http redirect a `303`/`302` render would otherwise make
/// `URLSession` follow transparently.
private final class NonRedirectDelegate: NSObject, URLSessionTaskDelegate {
	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		completionHandler(nil)
	}
}

enum ServerTestError: Error {
	case notReady
}
