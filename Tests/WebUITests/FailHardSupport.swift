import Foundation
import Logging
import NIOCore
import NIOEmbedded
import NIOPosix
import Synchronization
import Testing
import WebUI
import WebUIServer

// MARK: - fail-hard support
//
// the three instruments design C's gates need:
//
// 1. a `LogHandler` that keeps what it saw, so "the refusal is logged at
//    `.error`" is an assertion rather than a claim about stdout.
// 2. `FailHardRoute` — the server's *one catch*, mirrored. C3/C4/C5's HTTP
//    status lives in `WebUIServer.swift`, which stage 2's agent E does not own,
//    so the mapping a page route needs is written here as the exact code the
//    seam request asks agent D to paste. a gate that cannot be driven through
//    the real route still gets to pin the decision.
// 3. a raw tcp client, because a capacity refusal is only observable on the
//    wire: `URLSession` cannot tell a 503 from a closed socket, and a client
//    that holds a slot open needs a connection nobody else will reuse.

// MARK: - captured log lines

/// one line a `CapturingLogHandler` kept.
struct CapturedLine: Sendable, Equatable {
	let level: Logger.Level
	let message: String
}

/// a `LogHandler` that keeps every line it is handed.
///
/// `Logger` is a value over a handler, so a test that passes this factory's
/// logger into a server or a router observes exactly the lines that component
/// emits — no global logging state, no stdout scraping.
final class CapturingLogHandler: LogHandler, Sendable {
	private struct Store: Sendable {
		var metadata: Logger.Metadata = [:]
		var lines: [CapturedLine] = []
	}

	private let store = Mutex(Store())
	private let level = Mutex(Logger.Level.trace)

	init() {}

	var metadata: Logger.Metadata {
		get { store.withLock { $0.metadata } }
		set { store.withLock { $0.metadata = newValue } }
	}

	var logLevel: Logger.Level {
		get { level.withLock { $0 } }
		set { level.withLock { $0 = newValue } }
	}

	subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { store.withLock { $0.metadata[key] } }
		set { store.withLock { $0.metadata[key] = newValue } }
	}

	func log(
		level: Logger.Level,
		message: Logger.Message,
		metadata: Logger.Metadata?,
		source: String,
		file: String,
		function: String,
		line: UInt
	) {
		store.withLock { $0.lines.append(CapturedLine(level: level, message: message.description)) }
	}

	/// every line kept so far.
	var lines: [CapturedLine] { store.withLock { $0.lines } }

	/// whether a kept line is at `level` and contains `needle`.
	func saw(_ level: Logger.Level, containing needle: String) -> Bool {
		lines.contains { $0.level == level && $0.message.contains(needle) }
	}
}

/// a logger whose output a test can read back, plus the handler to read it from.
func capturingLogger(_ label: String = "webui.tests.failhard") -> (Logger, CapturingLogHandler) {
	let handler = CapturingLogHandler()
	handler.logLevel = .trace
	return (Logger(label: label) { _ in handler }, handler)
}

/// the `WebUIFailure` `body` threw, or `nil` when it threw nothing.
///
/// a thrown non-`WebUIFailure` is recorded as an issue rather than reported as
/// `nil`, so a test cannot pass because the wrong error was thrown.
func thrownFailure(_ body: () throws -> Void) -> WebUIFailure? {
	do {
		try body()
		return nil
	} catch let failure as WebUIFailure {
		return failure
	} catch {
		Issue.record("expected a WebUIFailure, got \(error)")
		return nil
	}
}

/// whether a channel's `closeFuture` has completed.
///
/// `EmbeddedChannel.isActive` cannot answer this: an embedded channel is never
/// *active* (it was never connected), so `isActive == false` is true before and
/// after a close. the close future is the signal that actually moves.
final class ClosedFlag: Sendable {
	private let closed = Mutex(false)

	init(_ channel: EmbeddedChannel) {
		// `Mutex` is noncopyable, so it is borrowed through `self` rather than
		// captured by value: `[self]` keeps the box alive for the future's
		// lifetime, which is the channel's.
		channel.closeFuture.whenComplete { [self] _ in closed.withLock { $0 = true } }
	}

	/// whether the channel has been closed, draining the embedded loop first so
	/// a close that completed asynchronously is visible.
	func value(_ channel: EmbeddedChannel) -> Bool {
		channel.embeddedEventLoop.run()
		return closed.withLock { $0 }
	}
}

// MARK: - the server's one catch, mirrored

/// the render decision a page route makes once the router has refused
/// something, written as the code the seam request hands to `WebUIServer.swift`.
///
/// the shape is deliberately one `switch`: `WebUIFailure` carries the status
/// (`atCapacity` is a `503` with `Retry-After`, everything else is a `500`),
/// so the server never parses a message to pick a status code.
enum FailHardRoute {
	/// one answer: a status and the body that ships.
	struct Answer: Sendable, Equatable {
		let status: Int
		let body: String

		/// the reason phrase the status implies, for the status line.
		var reason: String {
			switch status {
			case 200: return "OK"
			case 500: return "Internal Server Error"
			case 503: return "Service Unavailable"
			default: return "Unknown"
			}
		}
	}

	/// the status a failure answers with.
	static func status(for error: any Error) -> Int {
		guard let failure = error as? WebUIFailure else { return 500 }
		switch failure {
		case .atCapacity:
			return 503
		case .handlerCapReached, .entropyUnavailable, .unknownComponent, .renderThrew, .sessionEvicted:
			return 500
		@unknown default:
			// a new failure the route has not classified is still a refusal:
			// answering 200 would ship the page the failure forbids.
			return 500
		}
	}

	/// the body a failure answers with: the failure's own description, never the
	/// half-rendered page.
	static func body(for error: any Error) -> String {
		"\(status(for: error)) — render refused: \(String(describing: error))\n"
	}

	/// answer a render pass: raise whatever the pass recorded, and on a throw
	/// answer the error page — the rendered markup is discarded, so no partial
	/// page ships.
	static func answer(
		rendering page: @autoclosure () -> String,
		router: EventRouter,
		session: RenderSessionID
	) -> Answer {
		let rendered = page()
		do {
			try router.raisePendingFailure(in: session)
			return Answer(status: 200, body: rendered)
		} catch {
			return Answer(status: status(for: error), body: body(for: error))
		}
	}

	/// the token a render runs on, or ``WebUIFailure/entropyUnavailable``.
	///
	/// three lines that belong in `RenderToken.swift` as `mintStrict(using:)` —
	/// written here because that file, and the `WebUIServer.swift` call site
	/// that would use it, are stage 0's and agent D's respectively.
	static func token(using source: any SecureRandomSource) throws -> RenderToken {
		guard let token = RenderToken.mint(using: source) else {
			throw WebUIFailure.entropyUnavailable
		}
		return token
	}

	/// answer a render whose token must be minted: no token ⇒ no page.
	static func answer(
		mintingFrom source: any SecureRandomSource,
		rendering page: @autoclosure () -> String
	) -> Answer {
		do {
			_ = try token(using: source)
			return Answer(status: 200, body: page())
		} catch {
			return Answer(status: status(for: error), body: body(for: error))
		}
	}
}

// MARK: - entropy that always fails

/// a source that cannot produce bytes — the injected entropy failure C5 needs,
/// with no process-wide switch.
struct DeadEntropy: SecureRandomSource {
	func bytes(_ count: Int) -> [UInt8]? { nil }
}

// MARK: - raw tcp client

/// a raw tcp connection a test can hold open, write to, and read the bytes back
/// from until the peer closes.
///
/// `@unchecked Sendable` because a channel handler is event-loop confined by
/// nio's own contract (`Admission.swift`'s handlers say the same): the only
/// mutable state is behind a `Mutex`, and the promise is only fulfilled from
/// the loop that owns it.
final class RawByteSink: ChannelInboundHandler, @unchecked Sendable {
	typealias InboundIn = ByteBuffer

	private let bytes = Mutex<[UInt8]>([])
	private let closed: EventLoopPromise<Void>

	init(closed: EventLoopPromise<Void>) {
		self.closed = closed
	}

	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let buffer = Self.unwrapInboundIn(data)
		let chunk = Array(buffer.readableBytesView)
		bytes.withLock { $0.append(contentsOf: chunk) }
	}

	func channelInactive(context: ChannelHandlerContext) {
		closed.succeed(())
		context.fireChannelInactive()
	}

	var collected: [UInt8] { bytes.withLock { $0 } }
}

/// one raw client connection: the channel, the bytes it received, and a future
/// that completes when the peer closes.
final class RawConnection: @unchecked Sendable {
	let group: MultiThreadedEventLoopGroup
	let channel: any Channel
	private let sink: RawByteSink
	private let closed: EventLoopPromise<Void>

	private init(
		group: MultiThreadedEventLoopGroup,
		channel: any Channel,
		sink: RawByteSink,
		closed: EventLoopPromise<Void>
	) {
		self.group = group
		self.channel = channel
		self.sink = sink
		self.closed = closed
	}

	/// connect to `port`. the returned connection holds whatever slot the server
	/// admitted it into, which is what a capacity test needs.
	static func connect(port: Int) async throws -> RawConnection {
		// several attempts: `bind` has returned by the time the listener accepts,
		// but the accept loop is its own task and may need a moment.
		var lastError: (any Error)?
		for _ in 0..<80 {
			do {
				return try await connectOnce(port: port)
			} catch {
				lastError = error
				try await Task.sleep(for: .milliseconds(50))
			}
		}
		throw lastError ?? FailHardSocketError.notReady
	}

	private static func connectOnce(port: Int) async throws -> RawConnection {
		let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
		let channel: any Channel
		do {
			channel = try await ClientBootstrap(group: group)
				.channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
				.connect(host: "127.0.0.1", port: port)
				.get()
		} catch {
			try await group.shutdownGracefully()
			throw error
		}
		let closed = channel.eventLoop.makePromise(of: Void.self)
		let sink = RawByteSink(closed: closed)
		try await channel.pipeline.addHandler(sink).get()
		return RawConnection(group: group, channel: channel, sink: sink, closed: closed)
	}

	/// wait until the server has had a chance to accept and admit this
	/// connection. admission runs in the child-channel initializer, so the slot
	/// is taken as soon as the accept is processed.
	func settle(milliseconds: Int = 150) async throws {
		try await Task.sleep(for: .milliseconds(milliseconds))
	}

	/// write one request.
	func send(_ request: String) async throws {
		var buffer = channel.allocator.buffer(capacity: request.utf8.count)
		buffer.writeString(request)
		try await channel.writeAndFlush(buffer).get()
	}

	/// the bytes received so far.
	var received: String { String(decoding: sink.collected, as: UTF8.self) }

	/// wait for the peer to close, then return everything it sent.
	func awaitClose(seconds: Int = 5) async throws -> String {
		let closed = self.closed.futureResult
		let timeout = Task {
			try await Task.sleep(for: .seconds(seconds))
			throw FailHardSocketError.timedOut
		}
		defer { timeout.cancel() }
		try await withThrowingTaskGroup(of: Void.self) { group in
			group.addTask { try await closed.get() }
			group.addTask { try await timeout.value }
			defer { group.cancelAll() }
			_ = try await group.next()
		}
		return received
	}

	/// close and tear the loop down.
	func shut() async {
		try? await channel.close().get()
		try? await group.shutdownGracefully()
	}
}

enum FailHardSocketError: Error {
	case notReady
	case timedOut
}
