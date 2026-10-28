import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import WebUI
import WebUIState

// MARK: - HostLab
//
// the transport half of the host's suite: a real listener on a real port, a
// real GET carrying a real cookie, and a real websocket that speaks the wire
// protocol the engine speaks. nothing here fakes a socket — the composition
// these tests are about only exists once a page has a connection.
//
// every wait is bounded. a gate that hangs is a gate nobody reads, so a
// missing answer is a recorded failure with the thing that was waited for,
// never an indefinite block.

enum HostLabError: Error {
	/// the listener never answered.
	case notReady(port: Int)
	/// the listener answered after it was told to stop.
	case stillServing(port: Int)
	/// the answer did not arrive inside the bound.
	case timedOut(String)
	/// a frame the test could not read.
	case wire(String)
}

// MARK: - ports

/// a port in this suite's band that nothing is listening on.
///
/// the band is the suite's own (52 000+): two test targets that both boot a
/// server must probe disjoint ranges, or they can pick the same "free" port in
/// the window before either binds.
func hostFreePort(base: Int = 52_000) async throws -> Int {
	for offset in 0..<24 {
		let port = base + offset * 7
		if (try? await hostGet("/", port: port, cookie: nil)) == nil { return port }
	}
	Issue.record("no free port in the 52 000 band")
	throw HostLabError.notReady(port: base)
}

/// wait until `port` answers anything at all (a 303 counts: it is listening).
func hostWaitForListening(port: Int, cookie: String? = nil) async throws {
	for _ in 0..<120 {
		if let answer = try? await hostGet("/", port: port, cookie: cookie) {
			_ = answer
			return
		}
		try await Task.sleep(for: .milliseconds(25))
	}
	throw HostLabError.notReady(port: port)
}

/// wait until `port` refuses: the listener is gone, which is what "stopped"
/// means from the outside.
func hostAssertClosed(port: Int) async throws {
	for _ in 0..<80 {
		if (try? await hostGet("/", port: port, cookie: nil)) == nil { return }
		try await Task.sleep(for: .milliseconds(25))
	}
	Issue.record("the server still answers on :\(port) after shutdown")
	throw HostLabError.stillServing(port: port)
}

// MARK: - http

/// a session delegate that refuses redirects.
///
/// `URLSession` follows a 303 automatically, so a `data(for:)` against a page
/// that redirects answers the *destination's* status — `/login` here, which no
/// route carries, and the test reads a 404 for a redirect it never saw. the
/// redirect itself is what the gate is about, so the client must not follow it.
/// stateless by construction: it answers "no" and holds nothing.
final class HostNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
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

private let hostNoRedirects = HostNoRedirects()

/// one GET, with the cookie header a browser would send.
///
/// `URLSession` owns cookie storage and may rewrite or drop a manually set
/// `Cookie`, so the session is configured not to touch cookies at all: the
/// header the server sees is the header this test set.
func hostGet(
	_ path: String,
	port: Int,
	cookie: String?,
	cookieName: String = "auth"
) async throws -> (body: String, status: Int, location: String?) {
	guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
		throw HostLabError.wire("bad url for \(path)")
	}
	var request = URLRequest(url: url)
	request.timeoutInterval = 5
	let configuration = URLSessionConfiguration.ephemeral
	configuration.httpShouldSetCookies = false
	configuration.httpCookieStorage = nil
	if let cookie {
		request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
	}
	let session = URLSession(
		configuration: configuration,
		delegate: hostNoRedirects,
		delegateQueue: nil
	)
	defer { session.finishTasksAndInvalidate() }
	let (data, response) = try await session.data(for: request)
	let http = response as? HTTPURLResponse
	return (
		body: String(decoding: data, as: UTF8.self),
		status: http?.statusCode ?? 0,
		location: http?.value(forHTTPHeaderField: "Location")
	)
}

// MARK: - a bounded wait

/// run `body`, or fail with `what` after `seconds`.
///
/// the bound is the assertion: a service that does not stop, or a socket that
/// never answers, is a recorded failure rather than a stuck test process.
func hostRun<T: Sendable>(
	bounded seconds: Duration = .seconds(10),
	_ what: String,
	_ body: @escaping @Sendable () async throws -> T
) async throws -> T {
	try await withThrowingTaskGroup(of: T.self) { group in
		group.addTask { try await body() }
		group.addTask {
			try await Task.sleep(for: seconds)
			throw HostLabError.timedOut(what)
		}
		do {
			guard let value = try await group.next() else {
				throw HostLabError.timedOut(what)
			}
			group.cancelAll()
			return value
		} catch {
			group.cancelAll()
			throw error
		}
	}
}

// MARK: - websocket

#if !os(Linux)
/// a real websocket connection to a real listener, presenting a real cookie.
///
/// the engine's own client is javascript; this is the same protocol spoken from
/// swift so the bytes a page would receive can be counted. a frame it sends is
/// exactly what `webui-engine.js` sends (`{"type":"event",…,"token":…}`).
final class HostSocket: Sendable {
	private let task: URLSessionWebSocketTask
	private let session: URLSession

	init(port: Int, cookie: String, cookieName: String = "auth") throws {
		guard let url = URL(string: "ws://127.0.0.1:\(port)/ws") else {
			throw HostLabError.wire("bad ws url for port \(port)")
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 5
		request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.httpCookieStorage = nil
		let session = URLSession(configuration: configuration)
		self.session = session
		self.task = session.webSocketTask(with: request)
		task.resume()
	}

	/// send one text frame.
	func send(_ text: String) async throws {
		try await task.send(.string(text))
	}

	/// the next text frame, or a failure after `seconds`.
	func receiveText(bounded seconds: Duration = .seconds(10)) async throws -> String {
		let task = self.task
		return try await hostRun(bounded: seconds, "a websocket frame") {
			while true {
				let message = try await task.receive()
				switch message {
				case .string(let text): return text
				case .data(let data): return String(decoding: data, as: UTF8.self)
				@unknown default: return ""
				}
			}
		}
	}

	/// the next frame, whatever it is: the close path reports itself as a throw.
	/// true when the connection ended, false when another frame arrived first.
	func awaitClose(bounded seconds: Duration = .seconds(10)) async throws -> Bool {
		let task = self.task
		return try await hostRun(bounded: seconds, "the socket to close") {
			do {
				_ = try await task.receive()
				return false
			} catch {
				return true
			}
		}
	}

	func cancel() {
		task.cancel(with: .normalClosure, reason: nil)
		session.finishTasksAndInvalidate()
	}
}
#endif

// MARK: - the wire frames a host's page exchanges

/// the event frame the engine sends for a click on `component`.
func hostEventFrame(component: String, event: String = "click", token: String) -> String {
	"""
	{"type":"event","component":"\(component)","event":"\(event)","token":"\(token)"}
	"""
}

/// what one `update` frame said, decoded the way the client decodes it.
struct WireUpdate: Sendable {
	struct Fragment: Sendable {
		let id: String
		let html: String
	}

	let fragments: [Fragment]
	/// the frame's own byte count — what the socket actually carried.
	let frameBytes: Int
	/// the fragments' bytes — the page content the frame delivered.
	let fragmentBytes: Int
}

/// decode an `update` frame, or nil when the frame is something else.
func wireUpdate(_ text: String) throws -> WireUpdate? {
	guard let data = text.data(using: .utf8) else { throw HostLabError.wire("frame is not utf-8") }
	guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
		throw HostLabError.wire("frame is not a json object: \(text.prefix(120))")
	}
	guard object["type"] as? String == "update" else { return nil }
	guard let raw = object["fragments"] as? [[String: Any]] else {
		throw HostLabError.wire("update frame carries no fragments: \(text.prefix(120))")
	}
	let fragments = try raw.map { entry -> WireUpdate.Fragment in
		guard let id = entry["id"] as? String, let html = entry["html"] as? String else {
			throw HostLabError.wire("fragment without id/html: \(entry)")
		}
		return WireUpdate.Fragment(id: id, html: html)
	}
	return WireUpdate(
		fragments: fragments,
		frameBytes: text.utf8.count,
		fragmentBytes: fragments.reduce(0) { $0 + $1.html.utf8.count }
	)
}

/// the `code` of an error frame, or nil when the frame is something else.
func wireErrorCode(_ text: String) -> String? {
	guard let data = text.data(using: .utf8),
	      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
	      object["type"] as? String == "error"
	else { return nil }
	return object["code"] as? String
}

// MARK: - the document a hosted page renders

/// the `<body>` subtree of a rendered document, as bytes.
///
/// the differ is body-scoped — a document mints a fresh csp nonce and embeds
/// the render token in the head, so the head differs on every render and can
/// never be part of a byte diff — and this is the same scope, read the same
/// way, from the outside.
func bodyMarkup(of document: String) -> String {
	let snapshot = RenderSnapshot.derived(fromMarkup: document)
	return String(decoding: snapshot.bytes[snapshot.root], as: UTF8.self)
}

/// apply one fragment to a previous render, addressed by element id — what the
/// engine's `replaceElement(id:html:)` does.
///
/// the previous render's own bytes for that region are the string replaced, so
/// this is an `outerHTML` swap and nothing else: no re-parse, no normalization,
/// and a region that is not unique is a recorded failure rather than a silent
/// first-match.
func applyingFragments(_ fragments: [WireUpdate.Fragment], to previous: String) throws -> String {
	var markup = previous
	for fragment in fragments {
		let snapshot = RenderSnapshot.derived(fromMarkup: markup)
		guard let region = snapshot.regionHTML(RegionID(rawValue: fragment.id)) else {
			throw HostLabError.wire("no element with data-component-id=\"\(fragment.id)\" in the previous render")
		}
		let occurrences = markup.components(separatedBy: region).count - 1
		guard occurrences == 1 else {
			throw HostLabError.wire("region \(fragment.id) appears \(occurrences) times, so an id-addressed patch is ambiguous")
		}
		markup = markup.replacingOccurrences(of: region, with: fragment.html)
	}
	return markup
}
