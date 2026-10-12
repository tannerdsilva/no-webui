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

// MARK: - Route

/// one method + pattern pair and the responder that answers it.
public struct Route: Sendable {
	public let method: HTTPMethod
	public let pattern: PathPattern
	let responder: any Responder

	public init(method: HTTPMethod, pattern: PathPattern, responder: any Responder) {
		self.method = method
		self.pattern = pattern
		self.responder = responder
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

/// the closure-backed responder `Route.get`/`.post` stand on.
private struct ClosureResponder: Responder {
	let body: @Sendable (HTTPRequest) async -> HTTPResponse
	init(_ body: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
		self.body = body
	}
	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		await body(request)
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
		let matching = routes.filter { $0.pattern.match(request.path) != nil }
		guard !matching.isEmpty else {
			return HTTPResponse(status: .notFound, body: .text("not found"))
		}
		// most specific first; the enumerated offset keeps the sort stable
		// regardless of the library's own stability guarantees.
		let ranked = matching.enumerated().sorted { lhs, rhs in
			if lhs.element.pattern.specificity != rhs.element.pattern.specificity {
				return lhs.element.pattern.specificity > rhs.element.pattern.specificity
			}
			return lhs.offset < rhs.offset
		}.map(\.element)

		if let route = ranked.first(where: { $0.method == request.method }) {
			var routed = request
			routed.params = route.pattern.match(request.path) ?? [:]
			return try await route.responder.respond(to: routed)
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

	/// the 405 body. kept identical to the pre-router page message so a form
	/// POST lands on the same explanation it always had.
	static let methodNotAllowedBody =
		"405 — WebUIServer accepts GET only; a POST here means a <form> has no JS "
		+ "interception. See Documentation/API.md#forms (POST support: W3)."
}
