import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
#if !os(Linux)
import Network
#endif
import Synchronization
import Testing
@testable import WebUIServer

#if !os(Linux)

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

/// the connection states a run passed through, kept for a failure message:
/// an errno alone does not say whether the connection ever became ready.
final class StateLog: Sendable {
	private let lines = Mutex<[String]>([])

	func add(_ line: String) { lines.withLock { $0.append(line) } }

	var text: String { lines.withLock { $0.joined(separator: " → ") } }
}

/// a raw http/1.1 client for one request: a declared content length, a body
/// written in fixed chunks (each send awaited, so the socket's own backpressure
/// paces the writer), and the response read to its declared length.
///
/// `URLSession` cannot carry a body this test can count. `httpBodyStream`
/// rejects a swift `InputStream` subclass — CFNetwork throws
/// `_NSRequestConcreteObject` in `CFReadStreamSetClient` the moment it starts
/// the body — and `httpBody` would materialize all 64 MiB in the client. a raw
/// connection writes exactly what it is handed, when it is handed it, so
/// `cursor` is the client's true progress.
final class ChunkedUploadClient {
	private let connection: NWConnection
	private let queue = DispatchQueue(label: "no-webui.upload-stream-test")
	private let log = StateLog()

	init(port: Int) {
		connection = NWConnection(
			host: .ipv4(.loopback),
			port: NWEndpoint.Port(rawValue: UInt16(port))!,
			using: .tcp
		)
	}

	/// wait until the connection is ready to carry bytes.
	func connect() async throws {
		let states = AsyncThrowingStream<NWConnection.State, Error> { continuation in
			connection.stateUpdateHandler = { [log] state in
				log.add("\(state)")
				continuation.yield(state)
			}
			connection.start(queue: queue)
		}
		for try await state in states {
			switch state {
			case .ready:
				return
			case .failed(let error):
				throw UploadTestError.transport("connection failed: \(error) [\(log.text)]")
			case .cancelled:
				throw CancellationError()
			default:
				continue
			}
		}
		throw CancellationError()
	}

	/// hand `bytes` to the connection and wait until the transport has them.
	func send(_ bytes: [UInt8]) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			connection.send(content: Data(bytes), completion: .contentProcessed { [log] error in
				if let error {
					continuation.resume(
						throwing: UploadTestError.transport(
							"send of \(bytes.count) bytes failed: \(error) [\(log.text)]"
						)
					)
				} else {
					continuation.resume()
				}
			})
		}
	}

	func close() { connection.cancel() }

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

	private func receive() async throws -> (Data?, Bool) {
		try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) {
				data, _, complete, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: (data, complete))
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
}

// MARK: - the wire test

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
	static let portBase = 37_000

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
			defer { client.close() }
			try await client.connect()
			let head = "POST /upload/stream HTTP/1.1\r\n"
				+ "Host: 127.0.0.1:\(port)\r\n"
				+ "Content-Type: application/octet-stream\r\n"
				+ "Content-Length: \(Self.totalBytes)\r\n"
				+ "\r\n"
			try await client.send(Array(head.utf8))
			let chunk = [UInt8](repeating: 0x61, count: Self.clientChunk)
			var written = 0
			while written < Self.totalBytes {
				try await client.send(chunk)
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
}

#endif
