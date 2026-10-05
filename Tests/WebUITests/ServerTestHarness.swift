import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Logging
import Synchronization
import Testing
import WebUI
import WebUIDesignSystem
@testable import WebUIServer

// MARK: - shared wiring fixtures

// the server-booting harness, hoisted out of `WebUIServerSeamsTests` so every suite that
// asserts the wire drives the same helpers (the protocol suite's shipped-asset test is the
// second caller). file-scope internal: visible across the test target by construction.

/// a fixed payload/gzip pair (`.probe{color:teal}`, 38 compressed bytes) shared by the
/// host-asset negotiation tests. the server never compresses, so every variant asserted
/// against it is bytes a build produced — embedded rather than compressed at test time.
/// the vector is `gzip -n -9` output (no timestamp, no name, level 9), i.e. exactly what
/// `WebUIBuild.gzip` produces for the same payload.
let probePlain = ".probe{color:teal}"
// `printf '.probe{color:teal}' | gzip -n -9 -c`
let probeGzip: [UInt8] = [
	0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03,
	0xd3, 0x2b, 0x28, 0xca, 0x4f, 0x4a, 0xad, 0x4e, 0xce, 0xcf,
	0xc9, 0x2f, 0xb2, 0x2a, 0x49, 0x4d, 0xcc, 0xa9, 0x05, 0x00,
	0x19, 0xff, 0x10, 0x08, 0x12, 0x00, 0x00, 0x00,
]

// MARK: - harness

/// a raw HTTP GET through `curl`, returning `(headers, body)`.
///
/// `URLSession` decompresses a `Content-Encoding: gzip` response transparently and hides
/// the header, so it cannot observe the wire bytes this test is about. curl is the
/// instrument that does not lie about what arrived.
func rawGET(_ url: String, acceptEncoding: String) async throws -> (String, Data) {
	guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else {
		Issue.record("curl is not available — the wire bytes cannot be observed")
		throw SeamTestError.notReady
	}
	let headerFile = FileManager.default.temporaryDirectory
		.appendingPathComponent("seam-headers-\(UUID().uuidString)")
	defer { try? FileManager.default.removeItem(at: headerFile) }

	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
	process.arguments = [
		"-s", "-D", headerFile.path, "-o", "-",
		"-H", "Accept-Encoding: \(acceptEncoding)", url,
	]
	let pipe = Pipe()
	process.standardOutput = pipe
	try process.run()
	// drain before waiting, or a body larger than the pipe buffer deadlocks.
	let body = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	let headers = (try? String(contentsOf: headerFile, encoding: .utf8)) ?? ""
	return (headers, body)
}

/// start a server on a free port, run `body`, then stop it.
///
/// `portBase` exists because swift-testing runs suites concurrently: two suites that both
/// boot servers must probe disjoint port bands or they can pick the same "free" port in the
/// window before either binds.
func withServer(
	requestRender: @escaping WebUIServer.RequestRender,
	router: EventRouter,
	assets: [WebUIServerAsset],
	themeSheet: ThemeSheet? = nil,
	regions: WebUILiveRegions? = nil,
	portBase: Int = 21000,
	_ body: (Int) async throws -> Void
) async throws {
	let port = try await freePort(base: portBase)
	let server = WebUIServer(
		requestRender: requestRender,
		router: router,
		config: WebUIServerConfig(
			host: "127.0.0.1", port: port, themeSheet: themeSheet, assets: assets
		),
		regions: regions
	)
	let task = Task { try await server.start() }
	_ = try await waitForServe(port: port)
	do {
		try await body(port)
	} catch {
		await server.stop()
		task.cancel()
		throw error
	}
	await server.stop()
	task.cancel()
	// prove the listener is gone from the outside. awaiting the start task
	// instead would block the suite whenever the accept loop outlives the
	// close, so the socket is the observable — not the task handle.
	try await assertClosed(port: port)
}

/// probe upward for a port nothing is listening on.
func freePort(base: Int = 21000) async throws -> Int {
	for offset in 0..<20 {
		let port = base + offset * 11
		if (try? await get("http://127.0.0.1:\(port)/")) == nil {
			return port
		}
	}
	Issue.record("no free test port found")
	throw SeamTestError.notReady
}

func waitForServe(port: Int) async throws -> (String, Int) {
	for _ in 0..<80 {
		if let result = try? await get("http://127.0.0.1:\(port)/"), result.1 == 200 {
			return result
		}
		try await Task.sleep(for: .milliseconds(50))
	}
	throw SeamTestError.notReady
}

/// shutdown proof: the listener must refuse connections.
func assertClosed(port: Int) async throws {
	for _ in 0..<40 {
		if (try? await get("http://127.0.0.1:\(port)/")) == nil { return }
		try await Task.sleep(for: .milliseconds(50))
	}
	Issue.record("server still answering on :\(port) after shutdown")
	throw SeamTestError.stillServing
}

func get(_ url: String) async throws -> (String, Int) {
	let (data, status) = try await getData(url)
	return (String(decoding: data, as: UTF8.self), status)
}

func getData(_ url: String) async throws -> (Data, Int) {
	var request = URLRequest(url: URL(string: url)!)
	request.timeoutInterval = 5
	let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
	return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

func post(_ url: String) async throws -> (Data, Int) {
	var request = URLRequest(url: URL(string: url)!)
	request.httpMethod = "POST"
	request.timeoutInterval = 5
	let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
	return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}

enum SeamTestError: Error {
	case notReady
	case stillServing
}

// MARK: - live-region harness helpers (lane R, DX-13/DX-16)
//
// four helpers shared by the LiveRegions sockets tests: `regions:` on
// `withServer` (above), await-next-frame-with-timeout, zero-frames-in-window
// (both on `HarnessSocket`), and the byte counter (I8).

/// a thread-safe byte accumulator for received frame payloads. the I8 check
/// (a region push ≤ its rendered html + 512 B) reads `total`.
final class ByteCounter: Sendable {
	private let state = Mutex<Int>(0)

	func add(_ text: String) { state.withLock { $0 += text.utf8.count } }
	func add(_ data: Data) { state.withLock { $0 += data.count } }

	var total: Int { state.withLock { $0 } }
}

#if !os(Linux)
/// a thread-safe frame buffer. a reference type, so the socket's reader task can
/// capture it (a `Mutex` is noncopyable and cannot be captured).
final class FrameBuffer: Sendable {
	private let frames = Mutex<[String]>([])

	func append(_ text: String) {
		frames.withLock { buffer in
			if buffer.count < 4096 { buffer.append(text) }
		}
	}

	func takeFirst() -> String? {
		frames.withLock { $0.isEmpty ? nil : $0.removeFirst() }
	}

	func drain() -> [String] {
		frames.withLock { buffer in
			let all = buffer
			buffer.removeAll()
			return all
		}
	}

	var count: Int { frames.withLock { $0.count } }
}

/// an apple-only websocket test socket whose frames are drained by ONE reader
/// task into a locked buffer. awaiting a frame with a timeout therefore never
/// cancels an in-flight `receive()` (which would poison the next one) and never
/// loses a buffered frame to the timeout race.
final class HarnessSocket: Sendable {
	let task: URLSessionWebSocketTask
	private let buffer: FrameBuffer
	private let reader: Task<Void, Never>

	init(url: URL) {
		let socket = URLSession(configuration: .ephemeral).webSocketTask(with: url)
		let buffer = FrameBuffer()
		self.task = socket
		self.buffer = buffer
		socket.resume()
		// capture the buffer (not `self`) so the reader task can be built before
		// all members are initialized.
		self.reader = Task {
			while !Task.isCancelled {
				do {
					let message = try await socket.receive()
					let text: String
					switch message {
					case .string(let value): text = value
					case .data(let data): text = String(decoding: data, as: UTF8.self)
					@unknown default: continue
					}
					buffer.append(text)
				} catch {
					return
				}
			}
		}
	}

	func send(_ text: String) async throws {
		try await task.send(.string(text))
	}

	/// the next frame within `timeout`, or `nil` on timeout. polls the buffer, so
	/// a frame that arrived at the boundary is never lost.
	func nextFrame(timeout: Duration) async -> String? {
		let clock = ContinuousClock()
		let deadline = clock.now + timeout
		while clock.now < deadline {
			if let frame = buffer.takeFirst() { return frame }
			try? await Task.sleep(for: .milliseconds(5))
		}
		return buffer.takeFirst()
	}

	/// every frame arriving within `window`, draining the buffer. empty = silence.
	func framesWithin(_ window: Duration) async -> [String] {
		try? await Task.sleep(for: window)
		return buffer.drain()
	}

	/// frames buffered but not yet read.
	var pendingFrames: Int { buffer.count }

	func close() {
		reader.cancel()
		task.cancel(with: .normalClosure, reason: nil)
	}
}
#endif