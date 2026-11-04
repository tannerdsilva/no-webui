import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Synchronization
import Testing
@testable import WebUIServer

// MARK: - instruments
//
// the bounded-memory claim is measured where it is made: inside the handler,
// on the bytes the route is holding. the client is a socket writer that never
// materializes the body, so a 64 MiB upload costs the test one 256 KiB chunk.
// two numbers together make the claim falsifiable:
//
//   - `peakRetained`: the largest set of body bytes the route held at once.
//     the loop keeps only the chunk it was handed, so a server that handed
//     over an accumulated body would report the whole 64 MiB here.
//   - `clientWrittenAtFirstChunk`: how much of the body the client had handed
//     the socket when the first chunk arrived. a server that buffered the
//     whole body before dispatching cannot produce a chunk until the client
//     is done, so this would be 64 MiB; a streamed body arrives at ~one read.

/// the client's write cursor: body bytes handed to the socket so far.
final class UploadWriteCursor: Sendable {
	private let bytes = Mutex(0)

	/// body bytes handed to the socket so far.
	var written: Int { bytes.withLock { $0 } }

	func advanced(by count: Int) { bytes.withLock { $0 += count } }
}

/// what the route observed while consuming one body.
struct UploadObservation: Sendable {
	/// the path the route matched.
	var path = ""
	/// the declared content length, or -1 when the body is chunked.
	var declaredLength = -1
	/// body bytes the handler consumed.
	var total = 0
	/// how many chunks carried them.
	var chunks = 0
	/// the most body bytes the route held at one time.
	var peakRetained = 0
	/// client progress when the first chunk arrived; -1 when none did.
	var clientWrittenAtFirstChunk = -1
	/// whether the handler ran at all.
	var invoked = false
	/// the error the body's iteration threw, or "" when it ended clean.
	///
	/// this is the field a cancellation test rests on: a server that ends a
	/// disconnected client's body as if it were complete leaves this empty,
	/// and a host that seals a truncated upload looks exactly like that.
	var failure = ""
	/// whether the iteration finished instead of throwing. the contract is a
	/// throw on a disconnect; a `true` here with the client gone is the defect.
	var completed = false
	/// whether the handler ever held a body chunk.
	var sawFirstChunk = false
}

final class UploadProbe: Sendable {
	private let state = Mutex(UploadObservation())

	func record(_ observation: UploadObservation) {
		state.withLock { $0 = observation }
	}

	var observation: UploadObservation { state.withLock { $0 } }
}

// MARK: - the client

enum UploadTestError: Error, CustomStringConvertible {
	case noResponse
	case transport(String)

	var description: String {
		switch self {
		case .noResponse: return "no response"
		case .transport(let detail): return "transport: \(detail)"
		}
	}
}

/// the steps a run passed through, kept for a failure message: an errno
/// alone does not say how far the socket got.
final class StateLog: Sendable {
	private let lines = Mutex<[String]>([])

	func add(_ line: String) { lines.withLock { $0.append(line) } }

	var text: String { lines.withLock { $0.joined(separator: " → ") } }
}

/// a raw http/1.1 client for one request: a declared content length (or a
/// chunked body), bytes written in fixed chunks (each send awaited, so the
/// socket's own backpressure paces the writer), and the response read to its
/// declared length.
///
/// `URLSession` cannot carry a body this test can count. `httpBodyStream`
/// rejects a swift `InputStream` subclass — CFNetwork throws
/// `_NSRequestConcreteObject` in `CFReadStreamSetClient` the moment it starts
/// the body — and `httpBody` would materialize all 64 MiB in the client. a raw
/// socket writes exactly what it is handed, when it is handed it, so `cursor`
/// is the client's true progress.
///
/// the socket is POSIX rather than Network.framework so this suite runs on the
/// deployment envelope (linux) as well as on darwin: `NWConnection` is
/// apple-only, and a suite that exists solely on the machine that is not the
/// target cannot see a regression there.
///
/// two serial lanes carry the blocking syscalls — one for writes, one for
/// reads — each bridged back with a continuation. one lane per direction,
/// deliberately: a `recv` parked on a slow response must not hold up a `send`,
/// and a `send` parked on the socket's own buffer must not hold up a `recv`.
/// the lanes are the only dispatch queues in this file and exist solely to
/// keep a blocking call off a cooperative thread. a receive/send timeout
/// bounds every syscall, so a server that never answers fails the test
/// instead of hanging it.
final class ChunkedUploadClient {
	/// the socket, or -1 before `openConnection()` and after `closeConnection()`.
	private let handle = Mutex<Int32>(-1)
	/// writes, one at a time: the lane the socket's backpressure paces.
	private let writes = DispatchQueue(label: "no-webui.upload-test.writes")
	/// reads, one at a time, independent of `writes`.
	private let reads = DispatchQueue(label: "no-webui.upload-test.reads")
	private let log = StateLog()
	private let port: Int

	init(port: Int) {
		self.port = port
	}

	/// open the socket and connect it to `127.0.0.1:port`.
	func openConnection() async throws {
		#if os(Linux)
		let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
		#else
		let fd = socket(AF_INET, SOCK_STREAM, 0)
		#endif
		guard fd >= 0 else {
			throw UploadTestError.transport("socket: errno \(errno)")
		}
		handle.withLock { $0 = fd }
		log.add("socket(\(fd))")
		#if !os(Linux)
		// darwin raises SIGPIPE on a write to a peer that left; linux takes the
		// flag per send instead (`sendFlags`). the test must observe a
		// transport error, never die of a signal.
		var noSignal: Int32 = 1
		_ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
		#endif
		// a bounded syscall: every lane fails rather than waits forever.
		var timeout = timeval()
		timeout.tv_sec = 10
		timeout.tv_usec = 0
		let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
		_ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, timeoutSize)
		_ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, timeoutSize)

		let target = self.port
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			writes.async {
				var address = sockaddr_in()
				address.sin_family = sa_family_t(AF_INET)
				address.sin_port = in_port_t(UInt16(target).bigEndian)
				address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
				#if !os(Linux)
				address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
				#endif
				let connected = withUnsafePointer(to: address) { pointer in
					pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
						connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
					}
				}
				if connected == 0 {
					continuation.resume()
				} else {
					continuation.resume(
						throwing: UploadTestError.transport(
							"connect to 127.0.0.1:\(target) failed: errno \(errno)"
						)
					)
				}
			}
		}
		log.add("connected")
	}

	/// hand `bytes` to the socket and wait until it has taken all of them.
	/// `send` may accept a prefix, so the loop is the backpressure: the caller
	/// cannot start the next chunk until this one is in the kernel's buffer.
	func write(_ bytes: [UInt8]) async throws {
		guard !bytes.isEmpty else { return }
		let fd = handle.withLock { $0 }
		guard fd >= 0 else { throw UploadTestError.transport("write on a closed socket") }
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			let steps = log
			writes.async {
				var offset = 0
				while offset < bytes.count {
					let sent = bytes.withUnsafeBytes { raw -> Int in
						guard let base = raw.baseAddress else { return 0 }
						return send(fd, base.advanced(by: offset), bytes.count - offset, Self.sendFlags)
					}
					if sent < 0 {
						let code = errno
						if code == EINTR { continue }
						continuation.resume(
							throwing: UploadTestError.transport(
								"send of \(bytes.count) bytes failed: errno \(code) [\(steps.text)]"
							)
						)
						return
					}
					offset += sent
				}
				continuation.resume()
			}
		}
	}

	/// close the socket. idempotent, so a test can close at the moment it means
	/// to and still leave a `defer` behind.
	func closeConnection() {
		let fd = handle.withLock { value -> Int32 in
			let open = value
			value = -1
			return open
		}
		guard fd >= 0 else { return }
		// a full shutdown, not just a close: the test's "the client went away"
		// has to reach the server as an end of input.
		shutdown(fd, SHUT_RDWR)
		close(fd)
		log.add("closed")
	}

	/// read one response: status and body, framed by its `Content-Length`.
	func readResponse() async throws -> (status: Int, body: Data) {
		var buffer = Data()
		var headEnd: Int?
		var expected: Int?
		while true {
			if headEnd == nil, let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
				headEnd = range.upperBound
				let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
				expected = Self.contentLength(in: head)
			}
			if let headEnd, let expected, buffer.count >= headEnd + expected { break }
			let (chunk, complete) = try await receive()
			if let chunk { buffer.append(chunk) }
			if complete { break }
		}
		guard let headEnd else { throw UploadTestError.noResponse }
		let statusLine = String(decoding: buffer[..<(headEnd - 4)], as: UTF8.self)
			.split(separator: "\r\n").first ?? ""
		let status = Int(statusLine.split(separator: " ").dropFirst().first ?? "") ?? 0
		// a response with no declared length has no framing but the close; take
		// whatever arrived after the head.
		let end = expected.map { min(headEnd + $0, buffer.count) } ?? buffer.count
		return (status, Data(buffer[headEnd..<end]))
	}

	/// one read off the socket; `(nil, true)` is the peer's eof.
	private func receive() async throws -> (Data?, Bool) {
		let fd = handle.withLock { $0 }
		guard fd >= 0 else { throw UploadTestError.transport("read on a closed socket") }
		return try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<(Data?, Bool), Error>) in
			let steps = log
			reads.async {
				var buffer = [UInt8](repeating: 0, count: 64 << 10)
				while true {
					let capacity = buffer.count
					let got = buffer.withUnsafeMutableBytes { raw -> Int in
						guard let base = raw.baseAddress else { return 0 }
						return recv(fd, base, capacity, 0)
					}
					if got < 0 {
						let code = errno
						if code == EINTR { continue }
						continuation.resume(
							throwing: UploadTestError.transport(
								"recv failed: errno \(code) [\(steps.text)]"
							)
						)
						return
					}
					if got == 0 {
						continuation.resume(returning: (nil, true))
						return
					}
					continuation.resume(returning: (Data(buffer[0..<got]), false))
					return
				}
			}
		}
	}

	private static func contentLength(in head: String) -> Int? {
		for line in head.split(separator: "\r\n") {
			let parts = line.split(separator: ":", maxSplits: 1)
			guard parts.count == 2, parts[0].lowercased() == "content-length" else { continue }
			return Int(parts[1].trimmingCharacters(in: .whitespaces))
		}
		return nil
	}

	/// linux refuses to raise SIGPIPE for one send; darwin is handled by
	/// `SO_NOSIGPIPE` at connect.
	private static let sendFlags: Int32 = {
		#if os(Linux)
		return MSG_NOSIGNAL
		#else
		return 0
		#endif
	}()
}

// MARK: - the wire tests

@Suite("upload body streaming", .serialized)
struct UploadStreamTests {
	/// the body the route must consume: 64 MiB.
	static let totalBytes = 64 << 20
	/// the client's fixed write: 256 KiB, so the body is 256 writes and the
	/// client's whole footprint is one of them.
	static let clientChunk = 256 << 10
	/// the bound the route's window must stay under, whatever the body size.
	static let memoryBound = 4 << 20

	/// the band `waitForServe` polls. it must be one no other suite uses: the
	/// harness's port probe is not a lock, so two suites sharing a base can both
	/// see a port free, one binds, the other's `start()` throws unobserved, and
	/// the survivor's `stop()` then resets the loser's connection mid-request.
	/// bands live 20 probes × 11 apart, so a new one needs ~210 clear numbers.
	/// `34_000` belongs to another suite and `37_000` is this suite's streaming
	/// band, so the limit and cancellation cases take `39_000`, which no other
	/// suite in this target probes.
	static let portBase = 37_000
	/// the band the limit and cancellation cases run on — a second band,
	/// disjoint from `portBase`, so a test that starts a server on `37_000`
	/// cannot collide with one on `39_000` even if the suite's serialization
	/// is ever relaxed.
	static let limitPortBase = 39_000

	/// one http/1.1 chunk: its length in hex, the bytes, and the delimiter.
	static func frame(_ bytes: [UInt8]) -> [UInt8] {
		Array("\(String(bytes.count, radix: 16))\r\n".utf8) + bytes + [0x0d, 0x0a]
	}

	/// the zero-length chunk that ends a chunked body.
	static let chunkTerminator: [UInt8] = Array("0\r\n\r\n".utf8)

	@Test("a 64 MiB body reaches the route chunk by chunk and is never accumulated")
	func boundedMemory() async throws {
		let cursor = UploadWriteCursor()
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/stream", limit: Self.totalBytes) { head, body in
				var observation = UploadObservation()
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				for try await chunk in body {
					if observation.clientWrittenAtFirstChunk < 0 {
						observation.clientWrittenAtFirstChunk = cursor.written
					}
					// the window is this chunk and nothing else: an implementation
					// that accumulated the body would report 64 MiB here.
					observation.peakRetained = max(observation.peakRetained, chunk.count)
					observation.total += chunk.count
					observation.chunks += 1
				}
				probe.record(observation)
				return HTTPResponse(
					body: .text("received \(observation.total) in \(observation.chunks) chunks")
				)
			}
		}
		try await withRouterServer(router, portBase: Self.portBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			let head = "POST /upload/stream HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Content-Length: \(Self.totalBytes)\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			let chunk = [UInt8](repeating: 0x61, count: Self.clientChunk)
			var written = 0
			while written < Self.totalBytes {
				try await client.write(chunk)
				written += chunk.count
				cursor.advanced(by: chunk.count)
			}
			let response = try await client.readResponse()
			#expect(response.status == 200, "status \(response.status)")
			#expect(
				String(decoding: response.body, as: UTF8.self)
					.hasPrefix("received \(Self.totalBytes) in ")
			)
		}
		let observation = probe.observation
		#expect(observation.path == "/upload/stream")
		#expect(
			observation.declaredLength == Self.totalBytes,
			"the head carries the declared length: \(observation.declaredLength)"
		)
		#expect(observation.total == Self.totalBytes)
		#expect(observation.chunks > 1)
		#expect(
			observation.peakRetained < Self.memoryBound,
			"the route held \(observation.peakRetained) body bytes at once; the window must stay under \(Self.memoryBound)"
		)
		#expect(observation.clientWrittenAtFirstChunk >= 0, "the route never received a chunk")
		#expect(
			observation.clientWrittenAtFirstChunk < Self.totalBytes / 2,
			"the first chunk arrived after the client had written \(observation.clientWrittenAtFirstChunk) bytes — the body was buffered before dispatch"
		)
	}

	/// the counted cap, at its boundary: a body with no declared length at all
	/// that lands exactly on the limit is accepted, and the route reports every
	/// byte of it. the count therefore comes from the wire — there is no
	/// `Content-Length` here to copy it from — and it is exact, not off by one.
	@Test("a body exactly at the limit is accepted, counted from the wire and not a declared length")
	func countsBytesActuallyConsumed() async throws {
		let limit = 64 << 10
		let chunk = 16 << 10
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/counted", limit: limit) { head, body in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				do {
					for try await part in body {
						observation.peakRetained = max(observation.peakRetained, part.count)
						observation.total += part.count
						observation.chunks += 1
					}
				} catch {
					observation.failure = "\(error)"
					probe.record(observation)
					throw error
				}
				probe.record(observation)
				return HTTPResponse(body: .text("received \(observation.total)"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			let head = "POST /upload/counted HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Transfer-Encoding: chunked\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			let piece = [UInt8](repeating: 0x62, count: chunk)
			var sent = 0
			while sent < limit {
				try await client.write(Self.frame(piece))
				sent += piece.count
			}
			try await client.write(Self.chunkTerminator)
			let response = try await client.readResponse()
			#expect(response.status == 200, "status \(response.status)")
			#expect(String(decoding: response.body, as: UTF8.self) == "received \(limit)")
		}
		let observation = probe.observation
		#expect(observation.invoked)
		#expect(
			observation.declaredLength == -1,
			"a chunked body declares no length, so the count cannot come from the head: \(observation.declaredLength)"
		)
		#expect(
			observation.total == limit,
			"the route consumed \(observation.total) of \(limit) allowed bytes"
		)
		#expect(observation.chunks > 1)
		#expect(observation.failure.isEmpty, "an at-limit body must not fail: \(observation.failure)")
	}

	/// a head that already declares more than the route allows is refused
	/// before the body is touched. the handler is the witness: it never reads,
	/// so any invocation at all means the server dispatched a request it had
	/// already decided to refuse.
	@Test("a declared length over the limit is refused before any body byte is read")
	func declaredOverLimitIsRefusedBeforeAnyRead() async throws {
		let limit = 64 << 10
		let declared = 1 << 20
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/declared", limit: limit) { head, _ in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				probe.record(observation)
				return HTTPResponse(body: .text("accepted"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			// a declared length and ZERO body bytes: the refusal has to come
			// from the head alone.
			let head = "POST /upload/declared HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Length: \(declared)\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			let response = try await client.readResponse()
			#expect(response.status == 413, "status \(response.status)")
			let text = String(decoding: response.body, as: UTF8.self)
			#expect(text.contains("413 — request body too large"), "body: \(text)")
			#expect(
				text.contains("\(limit) bytes"),
				"the refusal names the route's own limit (\(limit)): \(text)"
			)
		}
		#expect(
			probe.observation.invoked == false,
			"the handler ran for a body the head had already refused"
		)
	}

	/// the counted cap, mid-stream: the client declares nothing (chunked) and
	/// keeps sending. the route must hand the handler exactly the bytes the
	/// budget allows, then cut — and answer 413 naming the route's limit.
	@Test("a body that overruns mid-stream is cut at the limit and refused")
	func midStreamOverrunIsCutAndRefused() async throws {
		let limit = 32 << 10
		let piece = 8 << 10
		let sent = piece * 6
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/overrun", limit: limit) { head, body in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				do {
					for try await part in body {
						observation.peakRetained = max(observation.peakRetained, part.count)
						observation.total += part.count
						observation.chunks += 1
					}
				} catch {
					observation.failure = "\(error)"
					probe.record(observation)
					throw error
				}
				probe.record(observation)
				return HTTPResponse(body: .text("accepted \(observation.total)"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			let head = "POST /upload/overrun HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Transfer-Encoding: chunked\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			let frame = Self.frame([UInt8](repeating: 0x63, count: piece))
			var written = 0
			while written < sent {
				try await client.write(frame)
				written += piece
			}
			try await client.write(Self.chunkTerminator)
			let response = try await client.readResponse()
			#expect(response.status == 413, "status \(response.status)")
			let text = String(decoding: response.body, as: UTF8.self)
			#expect(text.contains("413 — request body too large"), "body: \(text)")
			#expect(
				text.contains("\(limit) bytes"),
				"the refusal names the route's own limit (\(limit)): \(text)"
			)
		}
		let observation = probe.observation
		#expect(observation.invoked)
		#expect(
			observation.total == limit,
			"the handler saw \(observation.total) bytes; the cut belongs at \(limit)"
		)
		#expect(
			observation.failure.isEmpty == false,
			"the handler was never told its body had been cut"
		)
		#expect(
			observation.peakRetained < Self.memoryBound,
			"the cut body still held \(observation.peakRetained) bytes at once"
		)
	}

	/// the one a host cannot recover from: a client that leaves mid-body. the
	/// handler's iteration must fail, not finish — a body that ends "cleanly"
	/// here is indistinguishable from a complete upload and would seal a
	/// truncated file.
	@Test("a client that disconnects mid-body fails the handler's iteration")
	func disconnectReachesTheHandler() async throws {
		let limit = 1 << 20
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/cancel", limit: limit) { head, body in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				do {
					for try await part in body {
						observation.total += part.count
						observation.chunks += 1
						observation.sawFirstChunk = true
						probe.record(observation)
					}
				} catch {
					observation.failure = "\(error)"
					probe.record(observation)
					throw error
				}
				// reaching here means the iteration finished. with the client
				// gone that is the defect: a body that reports completion is
				// indistinguishable from a whole upload.
				observation.completed = true
				probe.record(observation)
				return HTTPResponse(body: .text("accepted \(observation.total)"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			let head = "POST /upload/cancel HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Content-Length: \(limit)\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			try await client.write([UInt8](repeating: 0x64, count: 16 << 10))
			// the disconnect has to land mid-body, so wait until the handler
			// holds a chunk before taking the socket away.
			for _ in 0..<500 where !probe.observation.sawFirstChunk {
				try await Task.sleep(for: .milliseconds(10))
			}
			#expect(
				probe.observation.sawFirstChunk,
				"the handler never saw a chunk, so this is not a mid-body disconnect"
			)
			client.closeConnection()
			// the handler reports on the connection's own task: give it the
			// same bounded window. a hang here is the failure, not the wait.
			for _ in 0..<500 where probe.observation.failure.isEmpty {
				try await Task.sleep(for: .milliseconds(10))
			}
		}
		let observation = probe.observation
		#expect(observation.invoked)
		#expect(
			observation.failure.isEmpty == false,
			"the handler's body ended as if complete after the client left"
		)
		// the contract, not the wording: the iteration must THROW. what the
		// transport calls it is the transport's business — a catch ran, and
		// the loop never reported a finished body.
		#expect(
			observation.completed == false,
			"the body's iteration finished after the client left; a host would seal a truncated upload"
		)
	}

	/// the cap belongs to the route, not to the handler: a handler that reads
	/// the cut and answers anyway must not be able to turn a truncated body
	/// into a 200. a host that writes a file would seal it.
	@Test("a handler that swallows the cut is still refused")
	func swallowedOverrunIsStillRefused() async throws {
		let limit = 16 << 10
		let piece = 8 << 10
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/swallowed", limit: limit) { head, body in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				// the bad host: every failure is folded into a success.
				do {
					for try await part in body {
						observation.total += part.count
						observation.chunks += 1
					}
				} catch {
					observation.failure = "\(error)"
				}
				probe.record(observation)
				return HTTPResponse(body: .text("accepted \(observation.total)"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			defer { client.closeConnection() }
			try await client.openConnection()
			let head = "POST /upload/swallowed HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Transfer-Encoding: chunked\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			let frame = Self.frame([UInt8](repeating: 0x67, count: piece))
			try await client.write(frame)
			try await client.write(frame)
			try await client.write(frame)
			try await client.write(Self.chunkTerminator)
			let response = try await client.readResponse()
			#expect(response.status == 413, "status \(response.status)")
			let text = String(decoding: response.body, as: UTF8.self)
			#expect(text.contains("413 — request body too large"), "body: \(text)")
			#expect(text.contains("\(limit) bytes"), "the refusal names the route's limit: \(text)")
		}
		let observation = probe.observation
		#expect(observation.invoked)
		#expect(observation.total == limit, "the handler saw \(observation.total), the cut is at \(limit)")
	}

	/// the drain path: a handler may return without reading its body to the
	/// end. the server still owes the client an answer, and the leftover body
	/// parts must not be mistaken for a request — the next connection has to
	/// work.
	@Test("a handler that returns without draining its body still answers, and the next connection works")
	func handlerThatDoesNotDrainStillAnswers() async throws {
		let limit = 1 << 20
		let declared = 256 << 10
		let probe = UploadProbe()
		let router = Router {
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.upload("/upload/drain", limit: limit) { head, body in
				var observation = UploadObservation()
				observation.invoked = true
				observation.path = head.path
				observation.declaredLength = head.contentLength ?? -1
				// one chunk, then out: the remaining 248 KiB is never pulled.
				for try await part in body {
					observation.total += part.count
					observation.chunks += 1
					break
				}
				probe.record(observation)
				return HTTPResponse(body: .text("read \(observation.total)"))
			}
		}
		try await withRouterServer(router, portBase: Self.limitPortBase) { port in
			let client = ChunkedUploadClient(port: port)
			try await client.openConnection()
			let head = "POST /upload/drain HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Content-Length: \(declared)\r\n"
				+ "\r\n"
			try await client.write(Array(head.utf8))
			try await client.write([UInt8](repeating: 0x65, count: 8 << 10))
			// the answer must arrive without the remaining 248 KiB: a server
			// that drained before answering parks here until the socket's
			// receive timeout fails the test.
			let response = try await client.readResponse()
			#expect(response.status == 200, "status \(response.status)")
			// one chunk is one WIRE READ, not the client's write size: the
			// first read can be a small prefix because the transport
			// segmented the write, and that is correct behaviour. what matters
			// is that the handler was handed a real prefix of the body.
			let firstChunk = probe.observation.total
			#expect(firstChunk > 0, "the handler read no body byte before answering")
			#expect(
				firstChunk <= (8 << 10),
				"the handler was handed \(firstChunk) bytes for one wire read of at most \(8 << 10)"
			)
			#expect(String(decoding: response.body, as: UTF8.self) == "read \(firstChunk)")
			client.closeConnection()

			// a fresh connection after the abandoned body: listener, router and
			// connection loop all still healthy.
			let next = ChunkedUploadClient(port: port)
			try await next.openConnection()
			defer { next.closeConnection() }
			try await next.write(
				Array("GET / HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n".utf8)
			)
			let second = try await next.readResponse()
			#expect(second.status == 200, "status \(second.status)")
			#expect(String(decoding: second.body, as: UTF8.self) == "ok")
		}
		let observation = probe.observation
		#expect(observation.invoked)
		#expect(observation.declaredLength == declared)
		#expect(observation.chunks == 1, "the handler pulled \(observation.chunks) chunks, not one")
	}
}
