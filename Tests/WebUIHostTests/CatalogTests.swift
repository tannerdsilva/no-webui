import Foundation
import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - C2 gate: the catalogs
//
// the gate, verbatim: "two identities GET / → DIFFERENT html; unauthenticated
// GET /dashboard → 303 to /login; unknown path → 404". those three are the last
// three tests here and they run through the composed host, because a catalog
// alone cannot answer any of them — the first needs a resolver, the second needs
// the anonymous door, the third needs the 404 the host owns. the tests before
// them pin the catalog's own contract.

@Suite("page catalog")
struct CatalogTests {

	@Test("the most specific pattern wins")
	func mostSpecificWins() async throws {
		let catalog = AuthenticatedCatalog(
			pages: [
				Page(pattern: "/users/:id") { _ in throw CancellationError() },
				Page(pattern: "/users/me") { _ in throw CancellationError() },
			],
			table: RouterTable()
		)

		// matching is a router rule, so assert it on the match, not on a render:
		// `page(for:)` is the pure decision the responder is built from.
		#expect(catalog.page(for: "/users/me")?.pattern.pattern == "/users/me")
		#expect(catalog.page(for: "/users/42")?.pattern.pattern == "/users/:id")
		#expect(catalog.page(for: "/nope") == nil)
	}

	@Test("a role guard refuses a principal that lacks the role")
	func roleGuardRefuses() async throws {
		let store = InMemoryAuthSessionStore()
		let member = try await Fixture.logIn(store: store, identityID: "member")
		let admin = try await Fixture.logIn(store: store, identityID: "admin")
		let resolver = CookieSessionResolver(
			store: store,
			identities: Fixture.directory([("member", [Role.member]), ("admin", [Role.admin])])
		)
		let catalog = AuthenticatedCatalog(
			pages: [
				Page(pattern: "/admin", requiresRole: Role.admin) { request in
					request.render { Text("admin") }
				}
			],
			table: RouterTable()
		)

		let memberPrincipal = try #require(try await resolver.principal(for: Fixture.request("/", cookie: member.cookie)))
		let adminPrincipal = try #require(try await resolver.principal(for: Fixture.request("/", cookie: admin.cookie)))

		#expect(try await catalog.responder(for: "/admin", principal: memberPrincipal) == nil)
		#expect(try await catalog.responder(for: "/admin", principal: adminPrincipal) != nil)
	}

	@Test("a render binds its router under the token the page carries")
	func renderBinds() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)
		let table = RouterTable()
		let catalog = AuthenticatedCatalog(
			pages: [Fixture.page("/")],
			table: table
		)
		let principal = try #require(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)))

		let responder = try #require(try await catalog.responder(for: "/", principal: principal))
		let response = try await responder.respond(to: Fixture.request("/"))
		let html = bodyText(response)

		let token = try #require(renderToken(in: html), "the page must carry the token it rendered under")
		#expect(table.renderTokens(for: login.sessionKey).map(\.value) == [token])
	}

	@Test("a static catalog serves its paths and its fallback, whatever the principal")
	func staticCatalogIgnoresPrincipal() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)
		let principal = try #require(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)))

		let publicPage = RecordingResponder("public")
		let catalog = StaticCatalog(
			pages: ["/login": publicPage],
			fallback: RecordingResponder("fallback")
		)

		#expect(try await catalog.responder(for: "/login", principal: principal) != nil)
		#expect(try await catalog.responder(for: "/login") != nil)
		#expect(try await catalog.responder(for: "/anything") != nil)
		#expect(try await catalog.responder(for: "/missing", principal: principal) != nil)

		let empty = StaticCatalog(pages: [:])
		#expect(try await empty.responder(for: "/login", principal: principal) == nil)
	}

	// MARK: the gate's three

	@Test("two identities get different html at the same path")
	func twoIdentitiesGetDifferentHTML() async throws {
		let fixture = TestHost(pages: [Fixture.page("/")])
		let alice = try await fixture.logIn(identityID: "alice")
		let bob = try await fixture.logIn(identityID: "bob")

		let aliceResponse = try await fixture.host.respond(to: Fixture.request("/", cookie: alice.cookie))
		let bobResponse = try await fixture.host.respond(to: Fixture.request("/", cookie: bob.cookie))

		let aliceHTML = bodyText(aliceResponse)
		let bobHTML = bodyText(bobResponse)

		#expect(aliceResponse.status == .ok)
		#expect(bobResponse.status == .ok)
		#expect(aliceHTML.contains("page for alice"))
		#expect(bobHTML.contains("page for bob"))
		#expect(aliceHTML != bobHTML)
		// and the tokens differ too: one render each, one namespace each.
		#expect(renderToken(in: aliceHTML) != renderToken(in: bobHTML))
	}

	@Test("an unauthenticated guarded path is a 303 to the login page")
	func unauthenticatedRedirectsToLogin() async throws {
		let fixture = TestHost(pages: [Fixture.page("/dashboard")])

		let response = try await fixture.host.respond(to: Fixture.request("/dashboard"))

		#expect(response.status.code == 303)
		#expect(location(of: response) == "/login")
		#expect(bodyText(response).isEmpty)
	}

	@Test("an unknown path is a 404, signed in or not")
	func unknownPathIs404() async throws {
		let fixture = TestHost(pages: [Fixture.page("/dashboard")])
		let login = try await fixture.logIn()

		let anonymous = try await fixture.host.respond(to: Fixture.request("/nope"))
		let authenticated = try await fixture.host.respond(to: Fixture.request("/nope", cookie: login.cookie))

		#expect(anonymous.status.code == 404)
		#expect(authenticated.status.code == 404)
		// not a redirect: an unknown path is not a sign-in problem, and
		// redirecting it would tell an anonymous visitor which paths exist.
		#expect(location(of: anonymous) == nil)
	}

	@Test("an unknown path with no cookie does not leak into the login redirect")
	func unknownPathAnonymousIsNotRedirect() async throws {
		let fixture = TestHost(pages: [Fixture.page("/dashboard")])

		let response = try await fixture.host.respond(to: Fixture.request("/secret-admin-panel"))

		#expect(response.status.code == 404)
	}
}
