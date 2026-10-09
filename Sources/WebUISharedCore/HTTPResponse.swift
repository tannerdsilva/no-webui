// MARK: - HTTPStatus

/// a small, literal-friendly status value — `HTTPResponse` defaults to
/// `.ok`, and a handler writes `status: .notFound` or `status: 418` with the
/// same effect.
public struct HTTPStatus: Sendable, Hashable, ExpressibleByIntegerLiteral {
	public let code: Int

	public init(integerLiteral value: Int) {
		self.code = value
	}

	/// numeric status for the cases without a named constant.
	public init(_ code: Int) {
		self.code = code
	}

	public static let ok: HTTPStatus = 200
	public static let created: HTTPStatus = 201
	public static let noContent: HTTPStatus = 204
	public static let redirect: HTTPStatus = 303
	public static let notFound: HTTPStatus = 404
	public static let unprocessable: HTTPStatus = 422
}

// MARK: - HTTPResponse

/// the typed response a render closure returns: status, headers, cookies, and
/// one body shape. this is what lets a page finally set a status, a header,
/// or a cookie from inside its own render.
///
/// it lives on the shared leaf — like ``HTTPCookie`` — so the event layer
/// (`HandlerOutcome.response`) can carry one without the server, keeping the
/// leaf foundation-free.
public struct HTTPResponse: Sendable {
	public var status: HTTPStatus
	public var headers: [String: String]
	public var cookies: [HTTPCookie]
	public var body: Body

	public init(
		status: HTTPStatus = .ok,
		headers: [String: String] = [:],
		cookies: [HTTPCookie] = [],
		body: Body = .empty
	) {
		self.status = status
		self.headers = headers
		self.cookies = cookies
		self.body = body
	}

	public enum Body: Sendable {
		/// an html document or fragment; the server adds `text/html` (and the
		/// csp machinery) when it encodes the response.
		case html(String)
		case text(String)
		case bytes([UInt8], contentType: String)
		case empty
		/// `Location` + status; defaults to 303 see-other.
		case redirect(to: String, status: HTTPStatus = .redirect)
		/// a chunked body: the server writes `Transfer-Encoding: chunked`, flushes
		/// per chunk, and cancels the producing stream when the connection closes.
		/// `contentType` mirrors the `Content-Type` header so the wire type rides
		/// with the body (the header is still applied on top).
		///
		/// the chunk carrier is `WebUIServer.HTTPStream`; the shared leaf cannot
		/// name that type, so it carries the stream's two parts directly.
		case stream(AsyncStream<[UInt8]>, contentType: String)
	}
}
