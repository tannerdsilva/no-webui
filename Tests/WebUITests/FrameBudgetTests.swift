import Foundation
import Logging
import NIOCore
import NIOPosix
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIServer

// MARK: - the frame budget
//
// the server declares a budget for one websocket frame (`maxFrameSize`, 256 KiB
// by default), publishes it to the page (`RuntimeConfig.maxFrameBytes`), and
// refuses — once, visibly — any frame that is over it anyway. the engine refuses
// such a frame locally instead, so a page that read the budget never spends its
// socket on a refusal.
//
// ports: this suite owns the 41 000 band. `WebUIServerTests` holds 34 000, the
// bounded-memory upload lane holds 37 000, `UploadStreamTests` holds
// 39 000–39 209, and the hosting-seam suites hold 49 000+; `freePort` steps by
// 11 from the base, so a suite's band is `base ..< base + 220`. a new suite
// picks a base nothing else probes, or two suites pick the same "free" port in
// the window before either binds.

// MARK: - instruments

enum FrameBudgetError: Error, CustomStringConvertible {
	case timedOut(String)

	var description: String {
		switch self {
		case .timedOut(let step): return "timed out waiting for \(step)"
		}
	}
}

/// poll `condition` until it holds, or fail the step by name.
///
/// the server answers asynchronously on its own event loop, so "the refusal
/// reached the counter" is a condition to wait for rather than a value to read
/// once; a fixed sleep would either flake or pad every run.
func pollFrameBudget(
	_ step: String,
	seconds: Int = 5,
	_ condition: () async throws -> Bool
) async throws {
	let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
	while ContinuousClock.now < deadline {
		if try await condition() { return }
		try await Task.sleep(for: .milliseconds(10))
	}
	throw FrameBudgetError.timedOut(step)
}

/// the bytes a probe socket received, shared between the handler and the test
/// (`Mutex` is noncopyable, so one owner is a reference, not a value).
final class ProbeInbox: Sendable {
	private let bytes = Mutex<[UInt8]>([])

	func append(_ chunk: [UInt8]) { bytes.withLock { $0.append(contentsOf: chunk) } }

	var snapshot: [UInt8] { bytes.withLock { $0 } }
}

/// the receiving half of a probe socket: everything the server writes lands here.
final class ProbeSink: ChannelInboundHandler, @unchecked Sendable {
	typealias InboundIn = ByteBuffer

	private let inbox: ProbeInbox

	init(inbox: ProbeInbox) {
		self.inbox = inbox
	}

	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		let buffer = Self.unwrapInboundIn(data)
		inbox.append(Array(buffer.readableBytesView))
	}
}

/// one server frame, as the probe read it.
struct ServerFrame: Sendable {
	let opcode: UInt8
	let payload: [UInt8]

	/// the 1009 a refused frame is answered with (`messageTooLarge`), or `nil`
	/// for a frame that is not a close.
	var closeCode: Int? {
		guard opcode == 0x8, payload.count >= 2 else { return nil }
		return Int(payload[0]) << 8 | Int(payload[1])
	}

	var text: String { String(decoding: payload, as: UTF8.self) }
}

/// a frame writer/reader on a raw socket.
///
/// `URLSessionWebSocketTask` cannot say how many bytes it puts in one frame —
/// it may fragment, and the test is about a frame of exactly one size — so the
/// client writes the bytes it means and reads what comes back.
final class FrameProbe: Sendable {
	private let group: MultiThreadedEventLoopGroup
	private let channel: any Channel
	private let inbox = ProbeInbox()

	private init(group: MultiThreadedEventLoopGroup, channel: any Channel) {
		self.group = group
		self.channel = channel
	}

	static func connect(port: Int) async throws -> FrameProbe {
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
		let probe = FrameProbe(group: group, channel: channel)
		try await channel.pipeline.addHandler(ProbeSink(inbox: probe.inbox)).get()
		return probe
	}

	func write(_ bytes: [UInt8]) async throws {
		var buffer = channel.allocator.buffer(capacity: bytes.count)
		buffer.writeBytes(bytes)
		try await channel.writeAndFlush(buffer).get()
	}

	var received: [UInt8] { inbox.snapshot }

	/// send the upgrade request and wait for its response head.
	func upgrade(port: Int) async throws -> String {
		let request = [
			"GET /ws HTTP/1.1",
			"Host: 127.0.0.1:\(port)",
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
			"Sec-WebSocket-Version: 13",
			"",
			"",
		].joined(separator: "\r\n")
		try await write(Array(request.utf8))
		var end = -1
		try await pollFrameBudget("the upgrade response") {
			end = Self.headEnd(in: self.received)
			return end >= 0
		}
		return String(decoding: received[..<end], as: UTF8.self)
	}

	/// the first frame the server wrote after the upgrade head.
	func awaitServerFrame() async throws -> ServerFrame {
		var frame: ServerFrame?
		try await pollFrameBudget("a frame from the server") {
			frame = Self.serverFrame(in: self.received)
			return frame != nil
		}
		guard let frame else { throw FrameBudgetError.timedOut("a frame from the server") }
		return frame
	}

	func shut() async {
		try? await channel.close().get()
		try? await group.shutdownGracefully()
	}

	/// the index just past the response head's `\r\n\r\n`, or -1.
	static func headEnd(in bytes: [UInt8]) -> Int {
		let delimiter: [UInt8] = [0x0d, 0x0a, 0x0d, 0x0a]
		guard bytes.count >= delimiter.count else { return -1 }
		let last = bytes.count - delimiter.count
		for index in 0...last where Array(bytes[index..<(index + delimiter.count)]) == delimiter {
			return index + delimiter.count
		}
		return -1
	}

	/// parse the first server frame out of `bytes`, after the upgrade head.
	static func serverFrame(in bytes: [UInt8]) -> ServerFrame? {
		let end = headEnd(in: bytes)
		guard end >= 0 else { return nil }
		guard bytes.count >= end + 2 else { return nil }
		let opcode = bytes[end] & 0x0f
		let masked = (bytes[end + 1] & 0x80) != 0
		var length = Int(bytes[end + 1] & 0x7f)
		var cursor = end + 2
		if length == 126 {
			guard bytes.count >= cursor + 2 else { return nil }
			length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
			cursor += 2
		} else if length == 127 {
			guard bytes.count >= cursor + 8 else { return nil }
			length = 0
			for index in cursor..<(cursor + 8) { length = length << 8 | Int(bytes[index]) }
			cursor += 8
		}
		var mask: [UInt8] = []
		if masked {
			guard bytes.count >= cursor + 4 else { return nil }
			mask = Array(bytes[cursor..<(cursor + 4)])
			cursor += 4
		}
		guard bytes.count >= cursor + length else { return nil }
		var payload = Array(bytes[cursor..<(cursor + length)])
		if masked {
			for index in payload.indices { payload[index] ^= mask[index % 4] }
		}
		return ServerFrame(opcode: opcode, payload: payload)
	}
}

/// the wire form of one client frame: final, masked, one length encoding.
enum ClientFrame {
	static func maskedText(_ payload: [UInt8]) -> [UInt8] {
		let mask: [UInt8] = [0x1a, 0x2b, 0x3c, 0x4d]
		var out: [UInt8] = [0x81]
		switch payload.count {
		case ..<126:
			out.append(0x80 | UInt8(payload.count))
		case ...0xffff:
			out.append(0x80 | 126)
			out.append(UInt8((payload.count >> 8) & 0xff))
			out.append(UInt8(payload.count & 0xff))
		default:
			out.append(0x80 | 127)
			let length = UInt64(payload.count)
			for shift in stride(from: 56, through: 0, by: -8) {
				out.append(UInt8((length >> UInt64(shift)) & 0xff))
			}
		}
		out.append(contentsOf: mask)
		for (index, byte) in payload.enumerated() {
			out.append(byte ^ mask[index % 4])
		}
		return out
	}

	/// `{"type":"ping"}` padded with json whitespace to exactly `bytes` bytes.
	///
	/// the padding is inside the document, so the server parses the frame and
	/// answers it: an accepted frame is proved by its answer, not by the socket
	/// staying open.
	static func paddedPing(bytes: Int) -> [UInt8] {
		let message = Array(#"{"type":"ping"}"#.utf8)
		precondition(bytes >= message.count, "a ping frame smaller than the message cannot exist")
		return message + [UInt8](repeating: 0x20, count: bytes - message.count)
	}
}

// MARK: - the harness

/// boot a server on this suite's port band, hand it (and its port) to `body`,
/// then stop it and prove the listener is gone.
func withBudgetServer(
	router: Router,
	config: WebUIServerConfig,
	logger: Logger,
	_ body: (Int, WebUIServer) async throws -> Void
) async throws {
	let port = try await freePort(base: 41_000)
	var serverConfig = config
	serverConfig.host = "127.0.0.1"
	serverConfig.port = port
	let server = WebUIServer(router: router, config: serverConfig, logger: logger)
	let task = Task { try await server.start() }
	_ = try await waitForServe(port: port)
	do {
		try await body(port, server)
	} catch {
		await server.stop()
		task.cancel()
		throw error
	}
	await server.stop()
	task.cancel()
	try await assertClosed(port: port)
}

func withFrameProbe<T>(port: Int, _ body: (FrameProbe) async throws -> T) async throws -> T {
	let probe = try await FrameProbe.connect(port: port)
	do {
		let value = try await body(probe)
		await probe.shut()
		return value
	} catch {
		await probe.shut()
		throw error
	}
}

/// the page the budget tests serve: it names the path it answered, so a frame
/// that reached the router is distinguishable from one that never did.
func budgetRouter() -> Router {
	Router {
		Route.get("/") { _ in
			HTTPResponse(body: .text("ok"))
		}
	}
}

// MARK: - the suite

/// serialized: every case boots a real listener, and three listeners probing
/// one port band at once bind the same "free" port before any of them is
/// listening — the band is shared with nothing, the *window* is the problem.
@Suite("websocket frame budget", .serialized)
struct FrameBudgetTests {
	/// the budget under test: ``WebUIServerConfig``'s default.
	static let budget = 256 * 1024

	@Test("a frame of exactly the budget is accepted and answered")
	func frameAtBudgetIsAccepted() async throws {
		let budget = Self.budget
		try await withBudgetServer(
			router: budgetRouter(),
			config: WebUIServerConfig(maxFrameSize: budget),
			logger: Logger(label: "webui.tests.framebudget.accept")
		) { port, server in
			try await withFrameProbe(port: port) { probe -> Void in
				let head = try await probe.upgrade(port: port)
				#expect(head.hasPrefix("HTTP/1.1 101"), "the socket must upgrade: \(head)")

				let payload = ClientFrame.paddedPing(bytes: budget)
				#expect(payload.count == budget)
				try await probe.write(ClientFrame.maskedText(payload))

				let frame = try await probe.awaitServerFrame()
				#expect(frame.opcode == 0x1, "an accepted ping is answered with text, not a close: \(frame)")
				#expect(frame.text == "{\"type\":\"pong\"}", "the frame reached the router: \(frame.text)")
			}
			let refusals = await server.refusedFrameCount
			#expect(refusals == 0, "a frame at the budget is not a refusal")
		}
	}

	@Test("a frame one byte over the budget is refused with 1009, logged once, counted once")
	func frameOverBudgetIsRefused() async throws {
		let budget = Self.budget
		let (logger, handler) = capturingLogger("webui.tests.framebudget.refuse")
		try await withBudgetServer(
			router: budgetRouter(),
			config: WebUIServerConfig(maxFrameSize: budget),
			logger: logger
		) { port, server in
			// the red observation this test is built around: nothing has been
			// refused before the over-budget frame exists.
			let before = await server.refusedFrameCount
			#expect(before == 0)

			let closeCode: Int? = try await withFrameProbe(port: port) { probe in
				let head = try await probe.upgrade(port: port)
				#expect(head.hasPrefix("HTTP/1.1 101"), "the socket must upgrade: \(head)")

				let payload = ClientFrame.paddedPing(bytes: budget + 1)
				#expect(payload.count == budget + 1)
				// the decoder refuses on the declared length, so the server may
				// close before the body is written: the answer is what this
				// asserts, not the write.
				try? await probe.write(ClientFrame.maskedText(payload))

				let frame = try await probe.awaitServerFrame()
				#expect(frame.opcode == 0x8, "a refused frame is answered with a close: \(frame)")
				return frame.closeCode
			}
			#expect(closeCode == 1009, "the close names messageTooLarge (1009): got \(String(describing: closeCode))")

			try await pollFrameBudget("the refusal to reach the counter") {
				await server.refusedFrameCount >= 1
			}
			let count = await server.refusedFrameCount
			#expect(count == 1, "one refused frame, one count")

			let warnings = handler.lines.filter { $0.level == .warning }
			#expect(warnings.count == 1, "one warning per refusal: \(warnings.map(\.message))")
			#expect(
				handler.saw(.warning, containing: "\(budget)-byte budget"),
				"the warning names the limit: \(warnings.map(\.message))"
			)
			#expect(
				handler.saw(.warning, containing: "1009"),
				"the warning names the close: \(warnings.map(\.message))"
			)
		}
	}

	@Test("the served page publishes the budget as maxFrameBytes")
	func pagePublishesBudget() async throws {
		let budget = Self.budget
		// an old page — one whose host never set the budget — emits exactly the
		// bytes it always did, so its engine keeps its pre-budget behaviour.
		#expect(RuntimeConfig().encodedJSON() == "{}")
		#expect(runtimeConfigKeyIsAbsent(from: ClientBoot().headMarkup()))
		#expect(RuntimeConfig(maxFrameBytes: budget).encodedJSON() == "{\"maxFrameBytes\":262144}")

		let router = Router {
			Route.get("/") { _ in
				HTTPResponse(body: .html(UnsafeMarkup.trusted(
					WebUIDocument(
						title: "budget",
						body: .trusted("<div id=\"app\">ok</div>"),
						runtimeConfig: RuntimeConfig(maxFrameBytes: budget)
					).markup.html
				)))
			}
		}
		try await withBudgetServer(
			router: router,
			config: WebUIServerConfig(maxFrameSize: budget),
			logger: Logger(label: "webui.tests.framebudget.page")
		) { port, _ in
			let (page, status) = try await get("http://127.0.0.1:\(port)/")
			#expect(status == 200)
			#expect(page.contains("<meta name=\"webui-config\""))
			// the meta's content is html-escaped, so the quotes ship as `&quot;`
			#expect(
				page.contains("&quot;maxFrameBytes&quot;:262144"),
				"the page must carry the number the server enforces"
			)
		}
	}

	@Test("the embedded engine refuses an over-budget frame before it is sent")
	func embeddedEngineRefusesLocally() async throws {
		// the built bytes, not the source file: what ships is what is pinned.
		let engine = WebUIAssets.engine
		#expect(engine.contains("maxFrameBytes: null"))
		#expect(engine.contains("function fitsBudget(frame)"))
		#expect(engine.contains("webui:frame-too-large"))
		// a page that never received the budget keeps sending: the guard is off
		// when the config carries nothing.
		#expect(engine.contains("if (!config.maxFrameBytes || config.maxFrameBytes <= 0) return true;"))

		guard let guardAt = engine.range(of: "if (!fitsBudget(frame)) return;") else {
			Issue.record("the engine has no pre-send budget guard")
			return
		}
		guard let sendAt = engine.range(of: "ws.send(frame);") else {
			Issue.record("the guarded send writes something other than the checked frame")
			return
		}
		#expect(
			guardAt.lowerBound < sendAt.lowerBound,
			"the guard must precede the write — otherwise a refused frame is already on the wire"
		)
		#expect(engine.contains("messageQueue.push(frame);"))
	}
}

/// whether a page's boot markup carries no frame budget at all.
private func runtimeConfigKeyIsAbsent(from head: String) -> Bool {
	head.contains("content=\"{}\"") && !head.contains("maxFrameBytes")
}
