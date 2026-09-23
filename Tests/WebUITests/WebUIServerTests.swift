import Foundation
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
			.render()
			return WebUIDocument(title: "WebUI Server Test", body: body).render()
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

		// content-addressed route: served immutable, gzip-decodable.
		let (hashCSS, hashStatus) = try await get("http://127.0.0.1:\(port)\(DesignSystemAssets.stylesheetURL)")
		#expect(hashStatus == 200)
		#expect(hashCSS.contains(".button"))

		let (_, missingStatus) = try await get("http://127.0.0.1:\(port)/missing")
		#expect(missingStatus == 404)

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
	}

	private func get(_ url: String) async throws -> (String, Int) {
		var request = URLRequest(url: URL(string: url)!)
		request.timeoutInterval = 5
		let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
		return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
	}

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
}

enum ServerTestError: Error {
	case notReady
}
