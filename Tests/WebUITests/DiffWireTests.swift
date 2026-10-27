import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
import WebUIServer

// design E's wire gate (plan §9.5 E4, §14 N25): mutate one of a page's ten
// regions, navigate in place, and exactly one `FragmentUpdate` must arrive —
// a small fraction of the page. mutate nothing and no frame arrives at all.
//
// the page is a real `WebUIDocument`, so every render mints a fresh csp nonce
// and a fresh render token. both live in the `<head>`, which is exactly the
// bytes a byte diff must not look at; a differ that hashed the whole document
// would answer every navigate with the full page and this gate would fail.
//
// the socket is a raw `URLSessionWebSocketTask`: the engine is not in the loop,
// so nothing the page does can mask what the server sent.

#if !os(Linux)

@Suite("design e — diff wiring", .serialized)
struct DiffWireTests {

	// MARK: the page

	/// the state a rendered page reads, and what its controls mutate.
	private final class Board: Sendable {
		struct State: Sendable {
			var headline = "board"
			var cells: [String] = (0..<10).map { "cell \($0)" }
		}

		private let state = Mutex(State())

		func read() -> State { state.withLock { $0 } }

		func setCell(_ index: Int, _ value: String) {
			state.withLock { state in
				guard state.cells.indices.contains(index) else { return }
				state.cells[index] = value
			}
		}

		func setHeadline(_ value: String) {
			state.withLock { $0.headline = value }
		}

		/// the page. `wrapped` puts the patchable root in, which is what the
		/// in-place update path targets.
		func page(renderToken: String, wrapped: Bool) -> WebUIDocument {
			let state = read()
			var body = ""
			if wrapped { body += "<div id=\"webui-page\">" }
			body += "<h1 class=\"board-headline\">\(state.headline)</h1>"
			for (index, cell) in state.cells.enumerated() {
				let attributes = controlAttributes(id: "cell-\(index)") { _ in
					// an interaction that changes the page: the re-render is
					// what the navigate answer diffs.
					self.setCell(index, "cell \(index) clicked")
					return []
				}
				body += "<button\(attributes)>\(cell)</button>"
			}
			// bulk, so one control is unambiguously a small slice of the page.
			body += String(repeating: "<p>filler text for a page that is not tiny</p>", count: 300)
			if wrapped { body += "</div>" }
			return WebUIDocument(
				title: "diff wire",
				body: .trusted(body),
				runtimeConfig: RuntimeConfig(renderToken: renderToken)
			)
		}
	}

	// MARK: harness

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

	/// the token the page minted, read out of its own `webui-config` meta.
	///
	/// the meta's content is html-escaped (`htmlEscape` on the config json), so
	/// the quotes around the value arrive as `&quot;`.
	private func renderToken(in page: String) -> String? {
		guard let marker = page.range(of: "renderToken") else { return nil }
		let rest = page[marker.upperBound...]
		guard let colon = rest.firstIndex(of: ":") else { return nil }
		var value = rest[rest.index(after: colon)...]
		for prefix in ["&quot;", "\""] where value.hasPrefix(prefix) {
			value = value.dropFirst(prefix.count)
			break
		}
		guard let end = value.firstIndex(where: { $0 == "&" || $0 == "\"" || $0 == "<" }) else {
			return nil
		}
		let token = String(value[..<end])
		return token.isEmpty ? nil : token
	}

	private func fragments(in frame: String) -> [[String: Any]] {
		guard let data = frame.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let fragments = object["fragments"] as? [[String: Any]]
		else { return [] }
		return fragments
	}

	private func frameType(_ frame: String) -> String? {
		guard let data = frame.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }
		return object["type"] as? String
	}

	// MARK: the gate

	@Test("one changed region of ten ships one fragment, a fraction of the page")
	func oneChangeIsOneFragment() async throws {
		let board = Board()
		// the page's token comes from the server's own render, so the route
		// reads it off the request instead of minting one.
		let router = Router {
			Route.page("/") { (request: HTTPRequest) in
				board.page(renderToken: request.renderToken.value, wrapped: true)
			}
		}

		try await withRouterServer(router, portBase: 44_000) { port in
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			guard let token = renderToken(in: page) else {
				Issue.record("the page carried no render token: \(page.prefix(700))")
				return
			}

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			// bind the socket to the page's render session: the navigate frame
			// carries no token, so this is the binding it answers on.
			try await socket.send(.string("{\"type\":\"ping\",\"token\":\"\(token)\"}"))
			#expect(try await frameType(receiveText(socket)) == "pong")

			// the interaction: one of ten regions changes.
			board.setCell(3, "cell three, clicked")
			try await socket.send(.string("{\"type\":\"navigate\",\"url\":\"/\"}"))
			let reply = try await receiveText(socket)

			let updates = fragments(in: reply)
			#expect(frameType(reply) == "update", "a navigate with one changed region is an update: got \(reply.prefix(120))")
			#expect(updates.count == 1, "exactly one region moved, so exactly one fragment ships")
			#expect(updates.first?["id"] as? String == "cell-3")

			let payload = (updates.first?["html"] as? String)?.utf8.count ?? 0
			let pageBytes = page.utf8.count
			print("diff wire: \(payload) B of \(pageBytes) B page = \(String(format: "%.2f", Double(payload) * 100 / Double(pageBytes)))%")
			#expect(payload > 0)
			#expect(
				payload * 100 < pageBytes * 2,
				"the patch is \(payload) B of a \(pageBytes) B page — must stay under 2 %"
			)
		}
	}

	@Test("a navigate that changes nothing sends no frame")
	func noChangeIsNoFrame() async throws {
		let board = Board()
		let router = Router {
			Route.page("/") { (request: HTTPRequest) in
				board.page(renderToken: request.renderToken.value, wrapped: true)
			}
		}

		try await withRouterServer(router, portBase: 44_100) { port in
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			guard let token = renderToken(in: page) else {
				Issue.record("the page carried no render token: \(page.prefix(700))")
				return
			}

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }

			try await socket.send(.string("{\"type\":\"ping\",\"token\":\"\(token)\"}"))
			#expect(try await frameType(receiveText(socket)) == "pong")

			// no state moved: the re-render is byte-identical over the body.
			try await socket.send(.string("{\"type\":\"navigate\",\"url\":\"/\"}"))
			// a frame always follows this ping; if the navigate had answered,
			// the update would be the message that arrives first.
			try await socket.send(.string("{\"type\":\"ping\",\"token\":\"\(token)\"}"))
			let next = try await receiveText(socket)
			#expect(
				frameType(next) == "pong",
				"an unchanged re-render must send nothing; got \(next.prefix(120))"
			)
		}
	}

	@Test("a change outside every region is answered with the whole page")
	func outOfRegionChangeIsFullPage() async throws {
		let board = Board()
		let router = Router {
			Route.page("/") { (request: HTTPRequest) in
				board.page(renderToken: request.renderToken.value, wrapped: true)
			}
			// the same board without the patchable root: a full page has no
			// element to receive the bytes there, so the answer is a load.
			Route.page("/plain") { (request: HTTPRequest) in
				board.page(renderToken: request.renderToken.value, wrapped: false)
			}
		}

		try await withRouterServer(router, portBase: 44_200) { port in
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			guard let token = renderToken(in: page) else {
				Issue.record("the page carried no render token: \(page.prefix(700))")
				return
			}

			let socket = openSocket(port: port)
			defer { socket.cancel(with: .normalClosure, reason: nil) }
			try await socket.send(.string("{\"type\":\"ping\",\"token\":\"\(token)\"}"))
			#expect(try await frameType(receiveText(socket)) == "pong")

			// the headline renders outside every region: a patch cannot carry it.
			board.setHeadline("renamed board")
			try await socket.send(.string("{\"type\":\"navigate\",\"url\":\"/\"}"))
			let reply = try await receiveText(socket)
			let updates = fragments(in: reply)
			#expect(frameType(reply) == "update")
			#expect(updates.count == 1)
			#expect(updates.first?["id"] as? String == "webui-page")
			#expect((updates.first?["html"] as? String)?.contains("renamed board") == true)

			// a page with no patchable root: the whole page cannot be applied,
			// so the answer is a real navigation instead of a dropped frame.
			try await socket.send(.string("{\"type\":\"navigate\",\"url\":\"/plain\"}"))
			let plain = try await receiveText(socket)
			#expect(frameType(plain) == "redirect", "got \(plain.prefix(120))")
			#expect(plain.contains("/plain"))
		}
	}
}

#endif
