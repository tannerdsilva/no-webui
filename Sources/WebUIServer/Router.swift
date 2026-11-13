import NIOHTTP1
import WebUI

// MARK: - Responder
//
// the unit the router answers with: a request in, a response out. the
// transport (http, and the websocket's navigate re-render) is the caller's
// concern — a responder knows nothing about nio, nonces, or sessions.

/// answers one typed request with one typed response.
///
/// throwing: a responder may fail (a page render can throw), and the server
/// turns that throw into a 500 carrying the host's error page rather than a
/// dropped connection (`WebUIServerConfig.onRenderFailure`).
public protocol Responder: Sendable {
	func respond(to request: HTTPRequest) async throws -> HTTPResponse
}

// MARK: - PathPattern

/// "/users/:id" — a literal segment, a `:name` capture, or a trailing `*rest`.
///
/// matching splits the raw path on `/` BEFORE percent-decoding, so an
/// encoded `%2f` can never manufacture a segment boundary — that is the
/// pattern-injection guard (a `/..%2f` decodes inside one capture, never as
/// a traversal above the route). a trailing slash is insignificant.
public struct PathPattern: Sendable, ExpressibleByStringLiteral {
	/// the pattern as written, e.g. "/users/:id".
	public let pattern: String
	/// the specificity key the router orders matches by: literal segment
	/// count, then capture count. a wildcard contributes to neither, so
	/// literal beats capture beats wildcard. only ever compared for ORDER.
	public let specificity: Int

	internal enum Token: Sendable, Equatable {
		case literal(String)
		case capture(String)
		case wildcard(String)
	}

	internal let tokens: [Token]

	public init(stringLiteral value: String) {
		self.init(value)
	}

	/// parse a pattern string.
	public init(_ value: String) {
		var tokens: [Token] = []
		for piece in value.split(separator: "/", omittingEmptySubsequences: true) {
			if piece.hasPrefix(":") {
				tokens.append(.capture(String(piece.dropFirst())))
			} else if piece.hasPrefix("*") {
				tokens.append(.wildcard(String(piece.dropFirst())))
			} else {
				tokens.append(.literal(String(piece)))
			}
		}
		self.tokens = tokens
		var literalCount = 0
		var captureCount = 0
		for token in tokens {
			switch token {
			case .literal: literalCount += 1
			case .capture: captureCount += 1
			case .wildcard: break
			}
		}
		// the weights are wide enough that no realistic path overflows the
		// lower field before the higher one flips.
		self.specificity = literalCount * 1_000_000 + captureCount * 1_000
		self.pattern = value
	}

	/// match `path`, returning the captured parameters, or nil for no match.
	/// a literal-only pattern returns an empty dictionary.
	public func match(_ path: String) -> [String: String]? {
		var params: [String: String] = [:]
		guard matchSegments(Self.segments(of: path), into: &params) else { return nil }
		return params
	}

	/// split the raw path on '/' without decoding first — the injection
	/// guard — and drop empty pieces (a trailing slash, a doubled slash).
	internal static func segments(of path: String) -> [String] {
		path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
	}

	private func matchSegments(
		_ segments: [String],
		into params: inout [String: String]
	) -> Bool {
		var i = 0
		for token in tokens {
			switch token {
			case .literal(let literal):
				guard i < segments.count, Self.decode(segments[i]) == literal else { return false }
				i += 1
			case .capture(let name):
				guard i < segments.count else { return false }
				params[name] = Self.decode(segments[i])
				i += 1
			case .wildcard(let name):
				// the remainder — at least one segment — decoded per segment
				// and re-joined, so the capture is faithful to the path.
				guard i < segments.count else { return false }
				// a wildcard is only legal as the final token; a pattern that
				// puts one elsewhere never matches (it would swallow the
				// segments its trailing literals expect).
				guard case .wildcard? = tokens.last else { return false }
				params[name] = segments[i...].map(Self.decode).joined(separator: "/")
				return true
			}
		}
		return i == segments.count
	}

	/// percent-decode one raw segment; an invalid escape passes through.
	private static func decode(_ text: String) -> String {
		guard text.contains("%") else { return text }
		let input = Array(text.utf8)
		var bytes: [UInt8] = []
		bytes.reserveCapacity(input.count)
		var i = 0
		while i < input.count {
			let byte = input[i]
			if byte == 0x25, i + 2 < input.count,
			   let hi = Self.hex(input[i + 1]), let lo = Self.hex(input[i + 2]) {
				bytes.append(hi << 4 | lo)
				i += 3
			} else {
				bytes.append(byte)
				i += 1
			}
		}
		return String(decoding: bytes, as: UTF8.self)
	}

	private static func hex(_ byte: UInt8) -> UInt8? {
		switch byte {
		case 0x30...0x39: return byte - 0x30                  // 0-9
		case 0x41...0x46: return byte - 0x41 + 10             // A-F
		case 0x61...0x66: return byte - 0x61 + 10             // a-f
		default: return nil
		}
	}
}

// MARK: - RenderIntent

/// why a page is being rendered.
///
/// one render pipeline serves three occasions, and a host's render is not
/// identical across them: a first load may arm a scroll-to-bottom, a client
/// navigation pushes history, and a refresh must re-render the page it is
/// already on without replaying either side effect. the intent is a value on
/// the request — not a bool, not an ambient flag — so the host switches
/// exhaustively and the compiler names the third case when it arrives.
public enum RenderIntent: Sendable, Hashable {
	/// the server is answering an http page request: the browser is loading
	/// this document.
	case load
	/// the engine reported a client-side navigation and the server is
	/// re-rendering the page in place (`answerNavigate`).
	case navigate
	/// a handler answered `HandlerOutcome.refresh` and the server is
	/// re-rendering the session's current page to diff it.
	case refresh
}

/// the request the intent door hands a host.
///
/// `{ method, path, query, intent }` plus the rest of the ``HTTPRequest`` the
/// route was matched with — headers, cookies, body, path parameters and the
/// render token — reachable through ``request``. the token matters: a page is
/// what publishes it, so a render door that could not reach it could not serve
/// a mixed page.
///
/// a value, not the live request: a host may keep it, and nothing about the
/// server's state is mutable through it.
public struct RenderRequest: Sendable {
	/// the http request the route matched, with `params` already filled.
	public let request: HTTPRequest
	/// why this render is happening.
	public let intent: RenderIntent

	public var method: HTTPMethod { request.method }
	/// the routed path, query stripped.
	public var path: String { request.path }
	/// the decoded query pairs.
	public var query: [String: String] { request.query }
	/// the path parameters the pattern captured.
	public var params: [String: String] { request.params }
	/// the session the server resolved for this render, when a host configured
	/// an authorizer. carried across a refresh so a per-identity page keeps its
	/// identity rather than falling back to an anonymous render.
	public var principal: SessionKey? { request.principal }
	/// the token minted for this render; a page echoes it into
	/// ``RuntimeConfig/renderToken`` so its frames are answered in its session.
	public var renderToken: RenderToken { request.renderToken }

	public init(request: HTTPRequest, intent: RenderIntent) {
		self.request = request
		self.intent = intent
	}
}

// MARK: - Route

/// one method + pattern pair and the responder that answers it.
public struct Route: Sendable {
	public let method: HTTPMethod
	public let pattern: PathPattern

	/// what answers the route: an ordinary responder, or a streaming upload.
	/// an upload route is never answered from a finished ``HTTPRequest`` — its
	/// body is the connection's own stream — so the arms are exclusive by
	/// construction.
	enum Action: Sendable {
		case respond(any Responder)
		case upload(UploadRoute)
	}

	let action: Action

	public init(method: HTTPMethod, pattern: PathPattern, responder: any Responder) {
		self.method = method
		self.pattern = pattern
		self.action = .respond(responder)
	}

	private init(method: HTTPMethod, pattern: PathPattern, action: Action) {
		self.method = method
		self.pattern = pattern
		self.action = action
	}

	/// a GET route answered by a closure.
	public static func get(
		_ pattern: PathPattern,
		_ r: @escaping @Sendable (HTTPRequest) async -> HTTPResponse
	) -> Route {
		Route(method: .get, pattern: pattern, responder: ClosureResponder(r))
	}

	/// a POST route answered by a closure.
	public static func post(
		_ pattern: PathPattern,
		_ r: @escaping @Sendable (HTTPRequest) async -> HTTPResponse
	) -> Route {
		Route(method: .post, pattern: pattern, responder: ClosureResponder(r))
	}

	/// a GET route whose responder sees **why** the page is being rendered.
	///
	/// the additive door beside ``get(_:_:)``: that one hands the host an
	/// `HTTPRequest` and nothing more, and a host that ignores intent keeps
	/// compiling byte for byte. this one hands a ``RenderRequest``, whose
	/// `intent` is `.load` on an http page request, `.navigate` when the engine
	/// reported a client navigation, and `.refresh` when a handler answered
	/// `HandlerOutcome.refresh` — which is how a host stops replaying
	/// load-only side effects (arm-scroll-to-bottom, push-history) on a refresh.
	///
	/// named `render`, not an overload of `get`: a trailing closure binds to
	/// the last parameter whatever its label, so `Route.get("/") { _ in … }`
	/// would be ambiguous between the two closure shapes at every existing call
	/// site (`_ in HTTPResponse(…)` satisfies both) — an additive door that
	/// breaks the door beside it is not additive.
	///
	/// the closure is non-throwing, exactly like ``get(_:_:)``: a render that
	/// fails answers the request by returning an error response, and a throw
	/// would have no head to turn into one on the websocket paths.
	public static func render(
		_ pattern: PathPattern,
		_ r: @escaping @Sendable (RenderRequest) async -> HTTPResponse
	) -> Route {
		Route(method: .get, pattern: pattern, responder: IntentResponder(r))
	}

	/// a POST route whose body is handed to the handler as it arrives.
	///
	/// the third constructor beside ``get``/``post``: those receive a finished
	/// ``HTTPRequest``, whose body the server buffered under
	/// `WebUIServerConfig.maxBodyBytes`. this one receives the connection's
	/// body directly — an ``UploadBody`` yields at most one read's worth of
	/// bytes per step — so the route's window is one chunk, not the request.
	/// the server matches upload routes before it reads a body, which is why
	/// this route never sees a ``RequestBody`` and never pays the buffer.
	///
	/// - parameters:
	///   - pattern: the path to answer.
	///   - limit: the byte budget for this upload, kept with the route so the
	///     counted enforcement reads one number. a head that declares more than
	///     this is refused before a body byte is read, and a body that crosses it
	///     is cut at the limit — counted from the bytes the handler was handed,
	///     never from `Content-Length`.
	///   - handler: consumes the head and the body, and answers the request.
	public static func upload(
		_ pattern: PathPattern,
		limit: Int,
		handler: @escaping @Sendable (UploadHead, consuming UploadBody) async throws -> HTTPResponse
	) -> Route {
		Route(
			method: .post,
			pattern: pattern,
			action: .upload(UploadRoute(limit: limit, handler: handler))
		)
	}

	/// a page route: the builder's value renders as a whole document, inside
	/// the render context the server establishes (component ids, handler
	/// registration, csp nonce).
	///
	/// typed on ``BufferRendering``, not ``View``: a `WebUIDocument` and an
	/// `HTMLDocument` are whole pages and are *not* views, so a route typed on
	/// `View` could not serve the framework's own document type — the gap that
	/// pushed every document host onto the deprecated `requestRender:` init.
	public static func page<D: BufferRendering>(
		_ pattern: PathPattern,
		content: @escaping @Sendable (HTTPRequest) throws -> D
	) -> Route {
		Route(method: .get, pattern: pattern, responder: PageResponder(content: content))
	}

	/// a page route whose content is loaded asynchronously before it renders — the
	/// shape an agent host needs (await state, then render the document).
	///
	/// the same `content:` label as the sync overload, deliberately: the compiler
	/// disambiguates on the closure's own async-ness, and a trailing closure keeps
	/// working for an async route. the rejected fallback was a distinct
	/// `asyncContent:` label — a trailing closure always binds to the trailing
	/// `content:` parameter, so that spelling would forbid trailing-closure syntax
	/// on every async route: a real ergonomic downgrade for no disambiguation gain.
	public static func page<D: BufferRendering>(
		_ pattern: PathPattern,
		content: @escaping @Sendable (HTTPRequest) async throws -> D
	) -> Route {
		Route(method: .get, pattern: pattern, responder: AsyncPageResponder(content: content))
	}
}

/// the responder `Route.get`/`.post` stand on.
private struct ClosureResponder: Responder {
	let body: @Sendable (HTTPRequest) async -> HTTPResponse
	init(_ body: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
		self.body = body
	}
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		await body(request)
	}
}

/// the responder `Route.render` stands on: lift the request's intent into a
/// ``RenderRequest`` and hand it to the host's closure.
///
/// the intent rides on the request the server built, so this adapter adds no
/// state of its own — two renders of one page can never be handed each other's
/// intent.
private struct IntentResponder: Responder {
	let body: @Sendable (RenderRequest) async -> HTTPResponse
	init(_ body: @escaping @Sendable (RenderRequest) async -> HTTPResponse) {
		self.body = body
	}
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		await body(RenderRequest(request: request, intent: request.renderIntent))
	}
}

/// the responder `Route.page` stands on: render the value through the buffer
/// (the one `BufferRendering` requirement) and hand the bytes out as html.
/// the render can throw — the server answers the throw, it does not drop it.
private struct PageResponder<D: BufferRendering>: Responder {
	let content: @Sendable (HTTPRequest) throws -> D
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		HTTPResponse(try content(request).markup)
	}
}

/// the responder `Route.page`'s async overload stands on: await the content,
/// then render it through the buffer and hand the bytes out as html.
private struct AsyncPageResponder<D: BufferRendering>: Responder {
	let content: @Sendable (HTTPRequest) async throws -> D
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		HTTPResponse(try await content(request).markup)
	}
}

// MARK: - Upload

/// the head of a streamed upload: what a route knows before it reads a byte.
///
/// the body is deliberately absent — it arrives as an ``UploadBody`` and is
/// consumed as it comes off the wire, so a multi-gigabyte request costs the
/// route one chunk of memory rather than one buffer of the whole file.
public struct UploadHead: Sendable {
	/// the request path, query already stripped.
	public let path: String
	/// the request headers, as they arrived.
	public let headers: HTTPHeaders
	/// the declared `Content-Length`, or nil for a chunked body.
	public let contentLength: Int?
}

/// a request body pulled as it arrives.
///
/// one cursor, bounded window: each `next()` answers at most the bytes of one
/// socket read, and nothing is retained between calls — the caller's loop
/// variable is the whole of what the route holds. the source is the
/// connection's inbound stream, so iterating this body reads the wire; a
/// handler that stops early stops reading, and the request loop skips the
/// rest.
///
/// on ownership: the stdlib's `AsyncSequence` inherits `Copyable`, so a
/// `~Copyable` conformance is not expressible — `_Concurrency` declares
/// `public protocol AsyncSequence<Element, Failure>` with the default
/// `Copyable` constraint. the single cursor is therefore the source object
/// below: every copy shares it, and each chunk is handed out once, never
/// replayed or duplicated.
public struct UploadBody: AsyncSequence {
	public typealias Element = [UInt8]

	/// where the chunks come from: the connection's one inbound cursor.
	let source: any UploadChunkSource

	init(source: any UploadChunkSource) {
		self.source = source
	}

	public func makeAsyncIterator() -> Iterator {
		Iterator(source: source)
	}

	public struct Iterator: AsyncIteratorProtocol {
		let source: any UploadChunkSource

		public mutating func next() async throws -> [UInt8]? {
			try await source.nextChunk()
		}
	}
}

/// the pull side of an ``UploadBody``: one chunk per call, never accumulated.
/// the server's connection implements it over nio's inbound stream.
protocol UploadChunkSource: AnyObject {
	func nextChunk() async throws -> [UInt8]?
}

/// why a streamed body stopped before its consumer was done.
///
/// the two failures a body can raise, kept apart because they want different
/// answers: an overrun is refused with a status the client can act on, while
/// a disconnect has nobody left to answer. both reach the handler as a throw
/// out of its iteration, so a host can delete whatever it had written.
enum UploadStreamError: Error, CustomStringConvertible {
	/// the route's `limit` was crossed. `received` is what the route had
	/// handed out when it refused — the declared length for a head refused
	/// before the read, the limit itself for a body cut mid-stream.
	case overLimit(limit: Int, received: Int)
	/// the connection ended before the body did. the reason is the transport's
	/// own account, for the log.
	case cancelled(reason: String)

	var description: String {
		switch self {
		case .overLimit(let limit, let received):
			return "upload over limit: \(limit) bytes allowed, \(received) received"
		case .cancelled(let reason):
			return "upload cancelled: the client disconnected before the body ended (\(reason))"
		}
	}
}

/// the route's byte budget, applied to a body as it is pulled.
///
/// the count is what the handler was handed, never what the head declared: a
/// `Content-Length` is the client's claim, and a body that carries more than
/// the claim says — chunked, or simply longer than it promised — is cut by
/// this counter. the chunk that crosses the limit is handed out up to the
/// last byte the budget allows, and the pull after it refuses, so the handler
/// sees exactly `limit` bytes and then a failure it can act on.
final class LimitedUploadSource: UploadChunkSource {
	private let upstream: any UploadChunkSource
	private let limit: Int
	/// body bytes handed to the handler so far.
	private var consumed = 0
	/// the refusal this body owes once the budget is spent and the wire had
	/// more. kept so the route can still refuse a handler that swallowed the
	/// cut instead of turning a truncated body into a success.
	private(set) var refusal: UploadStreamError?

	init(upstream: any UploadChunkSource, limit: Int) {
		self.upstream = upstream
		// a negative budget is not a limit; zero is the strictest one that is.
		self.limit = max(0, limit)
	}

	func nextChunk() async throws -> [UInt8]? {
		if let refusal { throw refusal }
		guard let chunk = try await upstream.nextChunk() else { return nil }
		let room = limit - consumed
		guard chunk.count > room else {
			consumed += chunk.count
			return chunk
		}
		consumed = limit
		let overrun = UploadStreamError.overLimit(limit: limit, received: consumed)
		refusal = overrun
		guard room > 0 else { throw overrun }
		return Array(chunk.prefix(room))
	}

	/// throw the refusal this body already owes, if any.
	func throwIfOverrun() throws {
		if let refusal { throw refusal }
	}
}

/// the streaming arm of a ``Route``: the handler and the byte budget the route
/// is held to.
struct UploadRoute: Sendable {
	/// the route's own limit, in bytes. kept with the route so the counted
	/// enforcement reads one number rather than one per handler.
	let limit: Int
	let handler: @Sendable (UploadHead, consuming UploadBody) async throws -> HTTPResponse

	func respond(_ head: UploadHead, body: consuming UploadBody) async throws -> HTTPResponse {
		// a head that declares more than the route allows is refused before
		// the body is touched: nothing is pulled off the wire and the handler
		// never runs, so the refusal costs the head it already read.
		if let declared = head.contentLength, declared > limit {
			throw UploadStreamError.overLimit(limit: limit, received: declared)
		}
		// the counted cap, applied where the bytes are handed out.
		let bounded = LimitedUploadSource(upstream: body.source, limit: limit)
		let response = try await handler(head, UploadBody(source: bounded))
		// the budget is the route's, not the handler's: a handler that caught
		// the cut and answered anyway must not turn a truncated body into a
		// 200 — a host that writes a file would then seal it.
		try bounded.throwIfOverrun()
		return response
	}
}

// MARK: - RouteBuilder

@resultBuilder public enum RouteBuilder {
	/// a single route statement.
	public static func buildExpression(_ route: Route) -> [Route] { [route] }
	/// a statement that already yields routes (an array literal, a loop).
	public static func buildExpression(_ routes: [Route]) -> [Route] { routes }
	public static func buildBlock(_ components: [Route]...) -> [Route] { components.flatMap { $0 } }
	public static func buildOptional(_ routes: [Route]?) -> [Route] { routes ?? [] }
	public static func buildEither(first component: [Route]) -> [Route] { component }
	public static func buildEither(second component: [Route]) -> [Route] { component }
	public static func buildArray(_ components: [[Route]]) -> [Route] { components.flatMap { $0 } }
}

// MARK: - Router

/// a typed route table. matching is MOST SPECIFIC FIRST — literal segment
/// count, then capture count — never declaration order; registration order
/// breaks ties only between two patterns with identical counts. a router
/// whose behaviour depended on declaration order would be a bug generator,
/// so the sort is explicit and stable.
public struct Router: Sendable, Responder {
	public let routes: [Route]

	public init(@RouteBuilder _ build: () -> [Route]) {
		self.routes = build()
	}

	public func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		let ranked = ranking(for: request.path)
		guard !ranked.isEmpty else {
			return HTTPResponse(status: .notFound, body: .text("not found"))
		}

		if let route = ranked.first(where: { $0.method == request.method }) {
			// an upload route answers on the wire, where its body is a stream.
			// reaching one here means the caller handed in a finished request
			// instead of the connection, so there is no body to stream: say so
			// rather than routing it an empty one.
			guard case .respond(let responder) = route.action else {
				return HTTPResponse(status: 500, body: .text(Self.uploadNeedsTheWire))
			}
			var routed = request
			routed.params = route.pattern.match(request.path) ?? [:]
			return try await responder.respond(to: routed)
		}

		// a matched pattern with an unmatched method: 405, and the Allow
		// header names the methods those patterns actually accept.
		let allowed = HTTPMethod.allCases
			.filter { method in ranked.contains { $0.method == method } }
			.map { $0.rawValue.uppercased() }
			.joined(separator: ", ")
		return HTTPResponse(
			status: HTTPStatus(405),
			headers: ["Allow": allowed],
			body: .text(Self.methodNotAllowedBody)
		)
	}

	/// the upload route that answers a `method`-`path` pair, most specific
	/// first. nil when the winning route for that method is an ordinary one —
	/// the server then takes the buffered path, exactly as it always has.
	func uploadRoute(method: HTTPMethod, path: String) -> UploadRoute? {
		for route in ranking(for: path) where route.method == method {
			guard case .upload(let upload) = route.action else { return nil }
			return upload
		}
		return nil
	}

	/// every route whose pattern matches `path`, most specific first; ties keep
	/// declaration order. one ranking for both dispatch paths, so an upload
	/// route and an ordinary route can never disagree about which pattern wins.
	private func ranking(for path: String) -> [Route] {
		routes
			.filter { $0.pattern.match(path) != nil }
			.enumerated()
			.sorted { lhs, rhs in
				if lhs.element.pattern.specificity != rhs.element.pattern.specificity {
					return lhs.element.pattern.specificity > rhs.element.pattern.specificity
				}
				return lhs.offset < rhs.offset
			}
			.map(\.element)
	}

	/// the 405 body. kept identical to the pre-router page message so a form
	/// POST lands on the same explanation it always had.
	static let methodNotAllowedBody =
		"405 — WebUIServer accepts GET only; a POST here means a <form> has no JS "
		+ "interception. See Documentation/API.md#forms (POST support: W3)."

	/// the 500 body for an upload route reached with a finished request: the
	/// server hands a streaming route the connection, and only the connection
	/// can answer it.
	static let uploadNeedsTheWire =
		"500 — this route streams its request body; it is answered on the wire "
		+ "(Route.upload receives an UploadBody), not from a finished HTTPRequest"
}
