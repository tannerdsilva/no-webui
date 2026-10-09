import WebUISharedCore

// MARK: - SSEEvent

/// one server-sent event: the sse fields an event can carry, plus framing
/// that survives a hostile payload (see `encoded()`).
public struct SSEEvent: Sendable {
	/// the event type (the `event:` line). `nil` omits the line, which the
	/// client reads as its default `message` event.
	public var event: String?
	/// the payload (the `data:` lines). a multi-line value becomes one
	/// `data:` line per line — the sse way to carry newlines.
	public var data: String
	/// the event id (the `id:` line), which the client echoes back in
	/// `Last-Event-ID` on reconnect.
	public var id: String?
	/// the reconnect hint in milliseconds (the `retry:` line).
	public var retryMs: Int?

	public init(event: String? = nil, data: String, id: String? = nil, retryMs: Int? = nil) {
		self.event = event
		self.data = data
		self.id = id
		self.retryMs = retryMs
	}

	// MARK: encoding

	/// the wire form: every field line `name: value\n`, then the blank line
	/// that dispatches the event to the client.
	///
	/// the one framing trap in sse is a value that contains a line ending: a
	/// raw newline would manufacture a field boundary, letting a payload
	/// smuggle an `event:`/`id:` line or a `:`-comment into the stream.
	/// every field value is therefore split on line boundaries and re-emitted
	/// with the field name re-asserted per line, so a crafted payload stays
	/// data and never becomes framing. for `data` that split is exactly how
	/// sse carries multi-line payloads.
	public func encoded() -> String {
		var out = ""
		if let id { out += Self.field("id", id) }
		if let event { out += Self.field("event", event) }
		out += Self.field("data", data)
		if let retryMs { out += "retry: \(retryMs)\n" }
		out += "\n"
		return out
	}

	/// one field, safe against embedded line endings: each line of `value`
	/// gets its own `name:` prefix, so no line in the value can ever read as
	/// a different field.
	private static func field(_ name: String, _ value: String) -> String {
		var out = ""
		for line in splitLines(value) {
			out += "\(name): \(line)\n"
		}
		return out
	}

	/// split `value` on every sse line ending — `\n`, `\r\n`, and a lone `\r`
	/// — keeping empty lines: an empty line in the value must become an empty
	/// `data:` line, not a premature end-of-event.
	private static func splitLines(_ value: String) -> [String] {
		var lines: [String] = []
		var current = ""
		// swift's grapheme segmentation (unicode gb3) yields a `\r\n` pair
		// as ONE character, so the pair must be matched before its halves —
		// a `\r` or `\n`-only branch would let a crlf through unchanged.
		for c in value {
			if c == "\r\n" || c == "\r" || c == "\n" {
				lines.append(current)
				current = ""
			} else {
				current.append(c)
			}
		}
		lines.append(current)
		return lines
	}
}

// MARK: - SSE

/// the server-sent-events responder: turn an event stream into a chunked
/// http response. the server writes it with `Transfer-Encoding: chunked`,
/// flushes per event, and cancels the producing stream when the connection
/// goes away.
public enum SSE {
	/// a `text/event-stream` response that streams `events`, one wire event
	/// per chunk.
	///
	/// the bytes are produced by a forwarding task that is cancelled through
	/// the chunk stream's termination hook: when the server stops consuming
	/// (the client disconnected), the chunk stream is cancelled, the
	/// forwarding task is cancelled, and that cancellation propagates into
	/// `events` — so a producer that never finishes is still wound down on
	/// disconnect instead of leaking a task.
	public static func response(_ events: AsyncStream<SSEEvent>) -> HTTPResponse {
		let chunks = AsyncStream<[UInt8]> { continuation in
			let forward = Task {
				for await event in events {
					if Task.isCancelled { break }
					continuation.yield(Array(event.encoded().utf8))
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in forward.cancel() }
		}
		let stream = HTTPStream(chunks: chunks, contentType: "text/event-stream")
		return HTTPResponse(body: stream.body)
	}
}
