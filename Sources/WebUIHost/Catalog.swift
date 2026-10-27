import WebUI
import WebUIServer
import WebUIAuth

// MARK: - PageRequest

/// one page render's inputs: which path was asked for, by whom, under which
/// render token.
///
/// value type, and it carries the principal rather than reaching for
/// `AuthContext.current`: a page body that could read an ambient identity could
/// also read the *wrong* one after an await, and the type system would not
/// object.
public struct PageRequest: Sendable {
	public let path: String
	public let query: [String: String]
	/// the principal this render is for. never nil — the catalog could not have
	/// chosen a page without one.
	public let principal: AuthContext
	/// the token this render mints into the page. the client echoes it back, and
	/// the router table is keyed by it.
	public let renderToken: RenderToken

	public init(
		path: String,
		query: [String: String] = [:],
		principal: AuthContext,
		renderToken: RenderToken
	) {
		self.path = path
		self.query = query
		self.principal = principal
		self.renderToken = renderToken
	}
}

// MARK: - RenderedPage

/// one finished render pass: the bytes, the router the pass registered into,
/// and the token the page must be bound under.
///
/// §5.3 also carries `regions: RenderDigest` here. design E's region accounting
/// exists in `HTMLBuffer` but `RenderDigest` is stage 2's (agent D), so this
/// value does not name it yet — a field added when the type exists beats a
/// placeholder that pretends.
public struct RenderedPage: Sendable {
	public let html: UnsafeMarkup
	/// the router this pass registered handlers on. bound by the catalog
	/// responder; never by the page.
	public let router: EventRouter
	public let renderToken: RenderToken

	public init(html: UnsafeMarkup, router: EventRouter, renderToken: RenderToken) {
		self.html = html
		self.router = router
		self.renderToken = renderToken
	}
}

// MARK: - PageRequest + render

extension PageRequest {
	/// the render session this request's handlers must register into — exactly
	/// the render token, which is the binding contract ``SessionRouterTable``
	/// relies on so that `drop(session:)` ends every handler the page made.
	public var renderSession: RenderSessionID {
		RenderSessionID(renderToken.value)
	}

	/// render one page body into a ``RenderedPage``.
	///
	/// this is the whole of a page's plumbing: start the pass (mint counters
	/// restart, so ids are stable), render under the render context that carries
	/// this pass's router and session, and hand back the router so the catalog
	/// can bind it. a page author writes the body and nothing else.
	public func render<D: BufferRendering>(
		on router: EventRouter = EventRouter(),
		_ body: () throws -> D
	) rethrows -> RenderedPage {
		router.begin(renderSession)
		let html = try RenderContext.$current.withValue(
			RenderContext(router: router, session: renderSession)
		) {
			try body().markup
		}
		return RenderedPage(html: html, router: router, renderToken: renderToken)
	}
}

// MARK: - Page

/// a route, an optional role guard, and the body that renders it.
///
/// the *declared* half of §5.3's split: sendable, no router, no token, no
/// identity — everything a render adds arrives in the ``PageRequest``. so a page
/// value is comparable across requests and safe to hold for the process's life.
public struct Page: Sendable {
	/// the path this page answers. pattern matching is `WebUIServer`'s
	/// (`PathPattern`), so `/users/:id` works and a `%2f` cannot forge a
	/// segment boundary.
	public let pattern: PathPattern
	/// the role a principal must hold. nil means "any principal" — never
	/// "anyone": a page in an authenticated catalog always needs a session.
	public let requiresRole: String?
	public let render: @Sendable (PageRequest) async throws -> RenderedPage

	public init(
		pattern: PathPattern,
		requiresRole: String? = nil,
		render: @escaping @Sendable (PageRequest) async throws -> RenderedPage
	) {
		self.pattern = pattern
		self.requiresRole = requiresRole
		self.render = render
	}

	/// whether `principal` may see this page.
	public func admits(_ principal: AuthContext) -> Bool {
		guard let requiresRole else { return true }
		return principal.hasRole(requiresRole)
	}
}

// MARK: - AuthenticatedCatalog

/// the multi-tenant page table: every page requires a principal, and every
/// match binds the render it serves back into the session that asked.
///
/// makes unrepresentable: "a page is served to whoever arrives" — there is no
/// entry point that takes a path without a principal, and the anonymous door
/// answers a redirect rather than a page.
public struct AuthenticatedCatalog: PageCatalog {
	public let pages: [Page]
	/// where an anonymous visitor is sent when the path exists. a plain path,
	/// never a `?next=` — a login page that echoes a request parameter into a
	/// redirect is an open-redirect waiting to happen, and the host does not
	/// need the parameter to serve the flow.
	public let loginPath: String
	/// the table every rendered page is bound into. binding lives here because
	/// "resolve this page for this principal" and "this render is now live" are
	/// one step: a resolved page that was never bound would serve a page whose
	/// controls are all dead.
	public let table: any SessionRouterTable

	public init(
		pages: [Page],
		loginPath: String = "/login",
		table: any SessionRouterTable
	) {
		self.pages = pages
		self.loginPath = loginPath
		self.table = table
	}

	// MARK: matching

	/// the most specific page matching `path`.
	///
	/// specificity is the router's own rule — literal segments, then captures,
	/// then wildcards, declaration order breaking ties — so a catalog and a
	/// `Router` never disagree about which of two matching routes wins.
	public func page(for path: String) -> Page? {
		let matches = pages.enumerated().filter { $0.element.pattern.match(path) != nil }
		guard !matches.isEmpty else { return nil }
		return matches.sorted { lhs, rhs in
			if lhs.element.pattern.specificity != rhs.element.pattern.specificity {
				return lhs.element.pattern.specificity > rhs.element.pattern.specificity
			}
			return lhs.offset < rhs.offset
		}.first?.element
	}

	// MARK: PageCatalog

	public func responder(for path: String, principal: AuthContext) async throws -> Responder? {
		guard let page = page(for: path), page.admits(principal) else { return nil }
		return CatalogPageResponder(page: page, principal: principal, table: table)
	}

	public func responder(for path: String) async throws -> Responder? {
		guard page(for: path) != nil else { return nil }
		return LoginRedirect(loginPath: loginPath)
	}
}

// MARK: - CatalogPageResponder

/// renders one page for one principal and binds the result.
///
/// the ordering is the security property: the token is minted *here*, the page
/// is rendered against it, and only then is the router bound. a render that
/// throws leaves nothing bound, so a failed render cannot leave a live entry
/// pointing at a half-registered router.
struct CatalogPageResponder: Responder {
	let page: Page
	let principal: AuthContext
	let table: any SessionRouterTable

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		// §7.2 rule 4: entropy failure fails the render. a tokenless page would
		// ship every control inert — worse than an error, because it looks fine.
		guard let token = RenderToken.mint() else {
			throw WebUIFailure.entropyUnavailable
		}
		let rendered = try await page.render(
			PageRequest(
				path: request.path,
				query: request.query,
				principal: principal,
				renderToken: token
			)
		)
		await table.bind(
			rendered.router,
			session: SessionKey(hash: principal.session.tokenHash),
			renderToken: RenderKey(value: rendered.renderToken.value)
		)
		return HTTPResponse(rendered.html)
	}
}

// MARK: - LoginRedirect

/// 303 to the login path — the anonymous answer for a guarded page that exists.
struct LoginRedirect: Responder {
	let loginPath: String

	func respond(to request: HTTPRequest) async throws -> HTTPResponse {
		HTTPResponse(status: .redirect, body: .redirect(to: loginPath))
	}
}

// MARK: - StaticCatalog

/// a path → responder table that ignores the principal.
///
/// the single-page server path: a deployment with no identities at all (a
/// status page, an asset host, a demo) still wants the framework's routing and
/// still benefits from answering through the same ``PageCatalog`` port, so the
/// host does not grow an `if multiTenant` branch. a public login page and its
/// assets belong here too, with the authenticated pages in an
/// ``AuthenticatedCatalog`` beside it.
public struct StaticCatalog: PageCatalog {
	/// exact-path entries. no patterns: a static catalog exists to say "this
	/// path, always this responder", and a pattern table is what
	/// ``AuthenticatedCatalog`` is for.
	public let pages: [String: any Responder]
	/// the answer for a path with no entry. nil answers 404 through the host.
	public let fallback: (any Responder)?

	public init(pages: [String: any Responder], fallback: (any Responder)? = nil) {
		self.pages = pages
		self.fallback = fallback
	}

	public func responder(for path: String, principal: AuthContext) async throws -> Responder? {
		pages[path] ?? fallback
	}

	public func responder(for path: String) async throws -> Responder? {
		pages[path] ?? fallback
	}
}
