import Foundation
#if canImport(FoundationNetworking)
// swift-corelibs-foundation keeps URLSession/URLRequest/HTTPURLResponse in a
// separate module; without this the test target does not compile on linux.
import FoundationNetworking
#endif
import Testing
@testable import WebUIServer
import WebUISharedCore

// MARK: - SSEEvent framing (the newline trap)

@Suite("SSEEvent.encoded", .serialized)
struct SSEEventFramingTests {
	@Test("a single-field event frames as one data line plus the dispatcher")
	func singleDataLine() {
		#expect(SSEEvent(data: "hello").encoded() == "data: hello\n\n")
	}

	@Test("every field is emitted, id and event before data and retry")
	func everyField() {
		let event = SSEEvent(event: "add", data: "hi", id: "42", retryMs: 3000)
		#expect(event.encoded() == "id: 42\nevent: add\ndata: hi\nretry: 3000\n\n")
	}

	@Test("a nil event type omits the event line (the client's default message)")
	func nilEventOmitsLine() {
		let encoded = SSEEvent(data: "x").encoded()
		#expect(!encoded.contains("event:"))
		#expect(encoded == "data: x\n\n")
	}

	@Test("multi-line data becomes one data line per line")
	func multiLineData() {
		#expect(SSEEvent(data: "line1\nline2").encoded() == "data: line1\ndata: line2\n\n")
	}

	@Test("crlf and lone cr line endings are normalised like lf")
	func carriageReturnNormalisation() {
		let actual = SSEEvent(data: "a\r\nb\rc").encoded()
		#expect(actual == "data: a\ndata: b\ndata: c\n\n")
	}

	@Test("empty lines in the data survive as empty data lines, not an end-of-event")
	func emptyLinesSurvive() {
		#expect(SSEEvent(data: "a\n\nb").encoded() == "data: a\ndata: \ndata: b\n\n")
	}

	@Test("empty data is still one data field")
	func emptyData() {
		#expect(SSEEvent(data: "").encoded() == "data: \n\n")
	}

	@Test("a colon-leading payload stays a data line and never becomes a comment")
	func colonLeadingPayloadStaysData() {
		let encoded = SSEEvent(data: ": looks like a comment").encoded()
		#expect(encoded == "data: : looks like a comment\n\n")
		for line in encoded.split(separator: "\n") where !line.isEmpty {
			#expect(!line.hasPrefix(":"))
		}
	}

	@Test("newlines in event and id cannot manufacture a foreign field")
	func newlinesInEventAndID() {
		let event = SSEEvent(event: "a\nb", data: "x", id: "1\r\n2")
		let encoded = event.encoded()
		#expect(encoded == "id: 1\nid: 2\nevent: a\nevent: b\ndata: x\n\n")
		assertOnlyKnownFields(encoded)
	}

	@Test("unicode payloads round-trip through utf-8 unchanged")
	func unicodeRoundTrip() {
		let payload = "héllo 🌍 日本語"
		let encoded = SSEEvent(data: payload).encoded()
		#expect(encoded == "data: \(payload)\n\n")
		let decoded = String(decoding: Array(encoded.utf8), as: UTF8.self)
		#expect(decoded == encoded)
	}

	@Test("adversarial payloads can only ever emit known prefixed fields")
	func noInjectionPossibility() {
		let hostile = [
			"line\n event: forged\ndata: forged\n: comment",
			"id: 7\r\nevent: forged\n\ndata: forged",
			"a\rb\rc",
		]
		for payload in hostile {
			assertOnlyKnownFields(SSEEvent(data: payload).encoded())
			assertOnlyKnownFields(SSEEvent(event: payload, data: "x", id: payload).encoded())
		}
	}

	/// every non-empty line of an sse frame must be one of the four known
	/// fields — never a bare `:comment` line, a foreign field, or a line that
	/// would dispatch the event early.
	private func assertOnlyKnownFields(_ frame: String) {
		for line in frame.split(separator: "\n") {
			if line.isEmpty { continue }
			let prefix = line.prefix(while: { $0 != ":" })
			let name = String(prefix).trimmingCharacters(in: .whitespaces)
			#expect(["id", "event", "data", "retry"].contains(name), "unexpected sse line: \(line)")
		}
	}
}

// MARK: - SSE.response and HTTPStream shapes

@Suite("SSE.response", .serialized)
struct SSEBucketTests {
	@Test("response carries a text/event-stream stream body that replays the events")
	func responseShape() async {
		let expected = [SSEEvent(data: "one"), SSEEvent(event: "two", data: "b\nc")]
		let events = AsyncStream<SSEEvent> { continuation in
			for event in expected { continuation.yield(event) }
			continuation.finish()
		}
		let response = SSE.response(events)
		guard case .stream(let chunks, let contentType) = response.body else {
			Issue.record("expected a .stream body, got \(response.body)")
			return
		}
		#expect(contentType == "text/event-stream")
		var received: [[UInt8]] = []
		for await chunk in chunks { received.append(chunk) }
		#expect(received == expected.map { Array($0.encoded().utf8) })
	}

	@Test("HTTPStream carries its chunks and content type")
	func httpStreamSurface() {
		let stream = HTTPStream(chunks: AsyncStream { $0.finish() }, contentType: "application/x-ndjson")
		#expect(stream.contentType == "application/x-ndjson")
		guard case .stream(_, let content) = stream.body else {
			Issue.record("expected HTTPStream.body to bridge to .stream")
			return
		}
		#expect(content == "application/x-ndjson")
	}
}

// MARK: - wire behaviour

@Suite("streaming over the wire", .serialized)
struct StreamingWireTests {
	@Test("chunked framing is well-formed and one wire chunk per event")
	func chunkedFramingIsWellFormed() async throws {
		let events = [SSEEvent(data: "first"), SSEEvent(event: "diff", data: "second"), SSEEvent(data: "third", retryMs: 5000)]
		let expectedBytes = events.map { Array($0.encoded().utf8) }
		let source = AsyncStream<SSEEvent> { continuation in
			for event in events { continuation.yield(event) }
			continuation.finish()
		}
		let router = Router {
			// "/" answers the harness's readiness probe with 200.
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.get("/events") { _ in SSE.response(source) }
		}
		try await withRouterServer(router, portBase: 36000) { port in
			let (headers, body) = try await rawChunkedGET(
				"http://127.0.0.1:\(port)/events",
				extra: ["-H", "Connection: close"]
			)
			#expect(headerValue(headers, "transfer-encoding") == "chunked")
			#expect(headerValue(headers, "content-type") == "text/event-stream")
			#expect(headerValue(headers, "cache-control") == "no-store")
			// a streaming response must not pretend to know its length.
			#expect(headerValue(headers, "content-length") == nil)

			let chunks = try decodeChunked(body)
			// per-event flush: three events arrive as three distinct wire
			// chunks whose sizes match the encoded events byte for byte.
			#expect(chunks.count == 3)
			for (index, chunk) in chunks.enumerated() {
				#expect(Array(chunk) == expectedBytes[index])
			}
		}
	}

	@Test("a client disconnect cancels a producer that never finishes")
	func disconnectCancelsProducer() async throws {
		let (cancelSignal, cancelContinuation) = AsyncStream<Void>.makeStream()
		let events = AsyncStream<SSEEvent> { continuation in
			let produce = Task {
				continuation.yield(SSEEvent(data: "first"))
				// a producer that would never finish on its own.
				while true {
					try await Task.sleep(for: .seconds(1_000_000))
				}
			}
			continuation.onTermination = { termination in
				// reached only when the server stopped consuming, which its
				// cancellation propagates into this stream's storage.
				produce.cancel()
				cancelContinuation.yield(())
				cancelContinuation.finish()
			}
		}
		let router = Router {
			// "/" answers the harness's readiness probe with 200.
			Route.get("/") { _ in HTTPResponse(body: .text("ok")) }
			Route.get("/events") { _ in SSE.response(events) }
		}
		try await withRouterServer(router, portBase: 36100) { port in
			let received = try await curlThenDisconnect(url: "http://127.0.0.1:\(port)/events")
			// prove the disconnect happened after streaming began.
			#expect(received.contains("first"))
			let cancelled = await waitForSignal(cancelSignal, timeoutSeconds: 5)
			#expect(cancelled, "the producer was not cancelled after the client disconnected")
		}
	}

	// MARK: helpers

	/// raw chunked-wire GET through curl. `--raw` disables curl's transfer
	/// decoding, so the body comes back with the chunk-size framing intact —
	/// the instrument that does not lie about what arrived.
	private func rawChunkedGET(_ url: String, extra: [String]) async throws -> (String, Data) {
		guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else {
			Issue.record("curl is not available — the wire bytes cannot be observed")
			throw SeamTestError.notReady
		}
		let headerFile = FileManager.default.temporaryDirectory
			.appendingPathComponent("stream-headers-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: headerFile) }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
		process.arguments = ["-s", "--raw", "-N", "--max-time", "5", "-D", headerFile.path, "-o", "-"]
			+ extra + [url]
		let pipe = Pipe()
		process.standardOutput = pipe
		try process.run()
		let body = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		let headers = (try? String(contentsOf: headerFile, encoding: .utf8)) ?? ""
		return (headers, body)
	}

	/// connect, let the first events arrive, then kill curl: process death
	/// closes the tcp connection, which is the disconnect under test.
	private func curlThenDisconnect(url: String) async throws -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
		process.arguments = ["-sN", "--max-time", "10", url]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		try? await Task.sleep(for: .milliseconds(600))
		process.terminate()
		process.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(decoding: data, as: UTF8.self)
	}

	/// first header value for `name`, case-insensitive.
	private func headerValue(_ headers: String, _ name: String) -> String? {
		for line in headers.components(separatedBy: "\r\n") {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let field = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			if field == name.lowercased() {
				return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
			}
		}
		return nil
	}

	/// parse `size\r\n<payload>\r\n` framing and return the payload chunks.
	/// a malformed framing throws.
	private func decodeChunked(_ body: Data) throws -> [Data] {
		var cursor = body.startIndex
		var chunks: [Data] = []
		let crlf = Data([0x0D, 0x0A])
		while cursor < body.endIndex {
			guard let crlfRange = body.range(of: crlf, in: cursor..<body.endIndex) else {
				throw ChunkDecodeError.malformed
			}
			let sizeText = String(decoding: body[cursor..<crlfRange.lowerBound], as: UTF8.self)
			guard let size = Int(sizeText, radix: 16) else { throw ChunkDecodeError.malformed }
			cursor = crlfRange.upperBound
			if size == 0 { break }
			guard let chunkEnd = body.index(cursor, offsetBy: size, limitedBy: body.endIndex) else {
				throw ChunkDecodeError.malformed
			}
			chunks.append(Data(body[cursor..<chunkEnd]))
			cursor = chunkEnd
			guard cursor < body.endIndex, body[cursor] == 0x0D,
				body.index(after: cursor) < body.endIndex,
				body[body.index(after: cursor)] == 0x0A
			else {
				throw ChunkDecodeError.malformed
			}
			cursor = body.index(cursor, offsetBy: 2)
		}
		return chunks
	}

	private enum ChunkDecodeError: Error {
		case malformed
	}

	/// whether the first element `signal` yields (or its finish) arrives
	/// within `timeoutSeconds`.
	private func waitForSignal(_ signal: AsyncStream<Void>, timeoutSeconds: Double) async -> Bool {
		let signalled = await withTaskGroup(of: Bool.self) { group in
			group.addTask {
				for await _ in signal {}
				return true
			}
			group.addTask {
				try? await Task.sleep(for: .seconds(timeoutSeconds))
				return false
			}
			let first = await group.next() ?? false
			group.cancelAll()
			return first
		}
		return signalled
	}
}
