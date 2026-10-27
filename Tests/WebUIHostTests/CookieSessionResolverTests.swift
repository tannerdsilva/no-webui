import Foundation
import Testing
import WebUI
import WebUIServer
import WebUIAuth
import WebUIHost

// MARK: - C1 gate: cookie → token hash → store → principal
//
// the gate, verbatim from the plan: "a real signed cookie resolves to a
// principal; absent / expired / malformed → nil; a revoked session → nil".
// each of those is its own test below, and every one of them runs against a
// real `InMemoryAuthSessionStore` and a real 32-byte `SessionToken` — the
// resolver's whole job is this join, so a fake store would test nothing.

@Suite("principal resolver")
struct CookieSessionResolverTests {

	@Test("a real signed cookie resolves to a principal")
	func signedCookieResolves() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store, identityID: "alice")
		let resolver = CookieSessionResolver(
			store: store,
			identities: Fixture.directory([("alice", [Role.member])])
		)

		let principal = try await resolver.principal(for: Fixture.request("/", cookie: login.cookie))

		let resolved = try #require(principal)
		#expect(resolved.session.identityID == "alice")
		#expect(resolved.session.tokenHash == login.session.tokenHash)
		// the token itself never appears in the resolved value — only its hash.
		#expect(resolved.session.tokenHash != login.token)
		#expect(resolved.identity?.roles == [Role.member])
	}

	@Test("the cookie header is read when the parsed map is empty")
	func cookieHeaderFallback() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)

		let principal = try await resolver.principal(
			for: Fixture.request("/", cookie: login.cookie, asHeader: true)
		)

		#expect(principal?.session.identityID == "alice")
	}

	@Test("an absent cookie resolves to nil")
	func absentCookieIsNil() async throws {
		let store = InMemoryAuthSessionStore()
		_ = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)

		#expect(try await resolver.principal(for: Fixture.request("/")) == nil)
	}

	@Test("a malformed cookie resolves to nil")
	func malformedCookieIsNil() async throws {
		let store = InMemoryAuthSessionStore()
		_ = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)

		// not base64url at all
		#expect(try await resolver.principal(for: Fixture.request("/", cookie: "not a token!")) == nil)
		// base64url but the wrong length: a 16-byte token cannot hash as a 32-byte one
		#expect(try await resolver.principal(for: Fixture.request("/", cookie: Base64.encodeURL([UInt8](repeating: 7, count: 16)))) == nil)
		// an empty value
		#expect(try await resolver.principal(for: Fixture.request("/", cookie: "")) == nil)
	}

	@Test("a well-formed token the store never issued resolves to nil")
	func unknownTokenIsNil() async throws {
		let store = InMemoryAuthSessionStore()
		_ = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)
		let stranger = try SessionToken.generate()

		#expect(try await resolver.principal(for: Fixture.request("/", cookie: Base64.encodeURL(stranger))) == nil)
	}

	@Test("an expired session resolves to nil and is removed from the store")
	func expiredSessionIsNil() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(
			store: store,
			expiresAt: Date().addingTimeInterval(-1)
		)
		let resolver = CookieSessionResolver(store: store)

		#expect(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)) == nil)
		// expiry is a cleanup, not a 404: the index entry is gone, so the same
		// cookie cannot resolve on a later request either.
		#expect(try await store.find(tokenHash: login.session.tokenHash) == nil)
	}

	@Test("a revoked session resolves to nil")
	func revokedSessionIsNil() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)

		let live = try #require(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)))
		#expect(live.session.identityID == "alice")

		// the store half of logout
		try await resolver.endSession(tokenHash: login.session.tokenHash)

		#expect(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)) == nil)
	}

	@Test("an identity the directory has forgotten still resolves, with no roles")
	func missingIdentityKeepsPrincipal() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store, identityID: "ghost")
		let resolver = CookieSessionResolver(
			store: store,
			identities: Fixture.directory([("alice", [Role.member])])
		)

		let principal = try #require(try await resolver.principal(for: Fixture.request("/", cookie: login.cookie)))
		// the session is authentic; what it may do is now nothing.
		#expect(principal.session.identityID == "ghost")
		#expect(principal.identity?.id == "ghost")
		#expect(principal.identity?.roles.isEmpty == true)
	}

	@Test("resolution touches lastSeenAt")
	func resolutionTouchesLastSeen() async throws {
		let store = InMemoryAuthSessionStore()
		let login = try await Fixture.logIn(store: store)
		let resolver = CookieSessionResolver(store: store)

		_ = try await resolver.principal(for: Fixture.request("/", cookie: login.cookie))

		let stored = try #require(try await store.find(tokenHash: login.session.tokenHash))
		#expect(stored.lastSeenAt >= login.session.lastSeenAt)
	}

	@Test("a store failure throws rather than pretending nobody is signed in")
	func storeFailureThrows() async throws {
		let resolver = CookieSessionResolver(store: FailingSessionStore())

		await #expect(throws: FailingSessionStore.Failure.self) {
			_ = try await resolver.principal(
				for: Fixture.request("/", cookie: Base64.encodeURL([UInt8](repeating: 3, count: 32)))
			)
		}
	}

	@Test("the session cookie carries no script-readable value")
	func sessionCookieAttributes() throws {
		let token = [UInt8](repeating: 9, count: 32)
		let cookie = CookieSessionResolver.sessionCookie(token: token, secure: true)
		let header = try cookie.setCookieHeaderValue()

		#expect(cookie.value == Base64.encodeURL(token))
		#expect(header.contains("HttpOnly"))
		#expect(header.contains("Secure"))
		#expect(header.contains("SameSite=Lax"))
		#expect(header.contains("Path=/"))
	}
}

// MARK: - FailingSessionStore

/// a store that cannot answer — the difference between "anonymous" (nil) and
/// "cannot tell" (throw), which the resolver must preserve.
private struct FailingSessionStore: AuthSessionStore {
	struct Failure: Error {}

	func create(_ session: AuthenticatedSession) async throws { throw Failure() }
	func find(tokenHash: [UInt8]) async throws -> AuthenticatedSession? { throw Failure() }
	func touch(_ session: AuthenticatedSession) async throws { throw Failure() }
	func invalidate(id: [UInt8]) async throws { throw Failure() }
	func invalidateAll(for identityID: String) async throws { throw Failure() }
	func listSessions(for identityID: String) async throws -> [AuthenticatedSession] { throw Failure() }
	func purgeExpired(before date: Date) async throws -> Int { throw Failure() }
}
