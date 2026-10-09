import NIOHTTP1
import WebUISharedCore

// MARK: - HTTPMethod
//
// the wire methods the typed request model carries. `rawValue` is the
// lowercase wire spelling; the server translates between this and nio's own
// `HTTPMethod` at the edge.

/// the http verbs the router can answer.
public enum HTTPMethod: String, Sendable, CaseIterable {
	case get, head, post, put, patch, delete, options
}

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

// MARK: - HTTPRequest

/// the typed request the router answers: method, path and decoded query, the
/// case-insensitive header collection, cookies, body, and the per-render
/// token that binds the response back to the page that asked. `params` is a
/// write-slot the router fills from a ``PathPattern`` before delivering the
/// request.
public struct HTTPRequest: Sendable {
	public var method: HTTPMethod
	public var path: String
	/// the decoded `?a=1&b=2` pairs. a repeated key keeps its first value
	/// (same contract as `WebUIServerRequest.query`).
	public var query: [String: String]
	/// request headers. `NIOHTTP1.HTTPHeaders`: an order-preserving,
	/// case-insensitive collection, so lookups answer regardless of wire
	/// casing (rfc 7230).
	public var headers: HTTPHeaders
	public var cookies: [String: String]
	public var body: RequestBody
	/// the token minted for THIS render, echoed into `RuntimeConfig.renderToken`.
	public var renderToken: RenderToken
	/// whether the request arrived over a tls transport.
	public var isSecure: Bool
	/// path parameters, filled by the router (w3.2).
	public var params: [String: String]

	public init(
		method: HTTPMethod = .get,
		path: String = "/",
		query: [String: String] = [:],
		headers: HTTPHeaders = HTTPHeaders(),
		cookies: [String: String] = [:],
		body: RequestBody = .none,
		renderToken: RenderToken = RenderToken(""),
		isSecure: Bool = false,
		params: [String: String] = [:]
	) {
		self.method = method
		self.path = path
		self.query = query
		self.headers = headers
		self.cookies = cookies
		self.body = body
		self.renderToken = renderToken
		self.isSecure = isSecure
		self.params = params
	}
}

/// the request body shapes a typed request can carry. the wire parser in
/// `FormBody.swift` produces the typed values: a urlencoded body becomes
/// `.form`, a multipart body `.multipart`, anything else `.bytes`.
public enum RequestBody: Sendable {
	case none
	case bytes([UInt8])
	case form(FormValues)
	case multipart(MultipartForm)
}

// MARK: - HTTPResponse

/// the typed response a render closure returns: status, headers, cookies, and
/// one body shape. this is what lets a page finally set a status, a header,
/// or a cookie from inside its own render.
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
		// case stream(HTTPStream)  // w3.5
	}
}
