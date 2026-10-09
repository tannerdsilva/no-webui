import WebUISharedCore

// MARK: - HTTPStream

/// a byte stream a response can carry. `WebUIServer` writes it with
/// `Transfer-Encoding: chunked`, flushes each chunk the moment it arrives,
/// and cancels the producing stream when the connection goes away — so a
/// long-lived one-way response (a token stream, a log tail) never leaks a
/// producer into a dead connection.
///
/// for server-sent events, `SSE.response` builds one of these for you; a
/// host that streams raw bytes composes one directly:
///
/// ```swift
/// let stream = HTTPStream(chunks: tokens, contentType: "application/x-ndjson")
/// return HTTPResponse(body: .stream(stream.chunks, contentType: stream.contentType))
/// ```
public struct HTTPStream: Sendable {
	/// the chunks, in order. the server writes one wire chunk per element —
	/// flush per element — so a producer that yields per token keeps the
	/// client current instead of buffering a burst.
	public let chunks: AsyncStream<[UInt8]>
	/// the `Content-Type` of the streamed body.
	public let contentType: String

	public init(chunks: AsyncStream<[UInt8]>, contentType: String) {
		self.chunks = chunks
		self.contentType = contentType
	}

	/// the response body this stream carries, ready for an `HTTPResponse`.
	internal var body: HTTPResponse.Body {
		.stream(chunks, contentType: contentType)
	}
}
