import Synchronization
import Testing
import WebUI
import WebUICore
import WebUIServer

// stage 0's hosting seams: the two protocols a host is written against, and the
// server's behaviour when neither is supplied.
//
// the imports are deliberately the *public* modules — this file is the proof
// that both protocols are conformable from outside `WebUIServer` with nothing
// but `HTTPRequest` and `SessionKey`, and that a config carrying neither still
// routes a request.

/// what an observer was told, in order.
private final class CallLog: Sendable {
	enum Entry: Sendable, Equatable {
		case opened(SessionKey)
		case closed(SessionKey)
	}

	private let entries = Mutex<[Entry]>([])

	func record(_ entry: Entry) {
		entries.withLock { $0.append(entry) }
	}

	var recorded: [Entry] {
		entries.withLock { $0 }
	}
}

/// an authorizer that answers one fixed key — the smallest double that proves
/// the protocol's shape (an async request in, a session key or nil out).
private struct FixedAuthorizer: RequestAuthorizer {
	let key: SessionKey?

	func authorize(_ request: HTTPRequest) async -> SessionKey? { key }
}

/// an observer that writes down what it was told.
private struct RecordingObserver: SocketLifecycleObserver {
	let log: CallLog

	func socketOpened(session: SessionKey, connection: UInt64, close: @escaping @Sendable () -> Void) async {
		log.record(.opened(session))
	}
	func socketClosed(session: SessionKey, connection: UInt64) async { log.record(.closed(session)) }
}

@Suite("stage 0 — hosting seams")
struct SpineHostingTests {
	@Test("both protocols are conformable from outside the server module")
	func protocolsAreConformable() async {
		let key = SessionKey(hash: [1, 2, 3])
		let request = HTTPRequest(path: "/app")

		#expect(await FixedAuthorizer(key: key).authorize(request) == key)
		#expect(await FixedAuthorizer(key: nil).authorize(request) == nil)

		let log = CallLog()
		let observer = RecordingObserver(log: log)
		await observer.socketOpened(session: key, connection: 1, close: {})
		await observer.socketClosed(session: key, connection: 1)
		#expect(log.recorded == [.opened(key), .closed(key)])
	}

	@Test("a config carries both seams, and both default to nil")
	func configCarriesTheSeams() {
		let bare = WebUIServerConfig()
		#expect(bare.authorizer == nil)
		#expect(bare.socketObserver == nil)

		let key = SessionKey(hash: [9])
		let supplied = WebUIServerConfig(
			authorizer: FixedAuthorizer(key: key),
			socketObserver: RecordingObserver(log: CallLog())
		)
		#expect(supplied.authorizer != nil)
		#expect(supplied.socketObserver != nil)
	}

	@Test("a server with no authorizer and no observer still routes")
	func nilSeamsStillRoute() async throws {
		// the nil path is the byte-identical path: the same config a host had
		// before this seam existed.
		let router = Router {
			Route.page("/") { _ in Text("routed") }
			Route.page("/app") { request in Text("routed \(request.path)") }
		}
		try await withRouterServer(router, portBase: 45_000) { port in
			let (body, status) = try await get("http://127.0.0.1:\(port)/app")
			#expect(status == 200)
			#expect(body.contains("routed /app"))
		}
	}
}
