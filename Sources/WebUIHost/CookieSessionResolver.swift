import Foundation
import WebUI
import WebUIServer
import WebUIAuth

// MARK: - CookieSessionResolver

/// the cookie → token hash → store → principal join.
///
/// the cookie carries the raw 32-byte session token, base64url encoded. the
/// token is the only thing a client holds; the store is keyed by its SHA-256
/// and never sees the token, so a store dump is not a session-theft kit. this
/// type is the one place those two facts meet.
///
/// every "no" is `nil` and none of them is an error, deliberately:
///
/// - no cookie, an empty value, a value that is not base64url, or one that
///   decodes to the wrong length → `nil` (malformed)
/// - a well-formed token the store does not know → `nil` (absent, or revoked:
///   `invalidate` removes the token index, so a revoked session is
///   indistinguishable from one that never existed — which is the point)
/// - a session the store knows whose `expiresAt` has passed → `nil`, and the
///   store entry is invalidated on the way out (expired is a cleanup, not a
///   404)
///
/// a store that *fails* throws instead: the caller must be able to answer 500
/// rather than pretending the user is anonymous.
public struct CookieSessionResolver: PrincipalResolver, SessionRevocation {
	/// the cookie name the resolver reads. deliberately not `__Host-` by
	/// default: a `__Host-` cookie requires `Secure` and therefore tls, and a
	/// deployment that terminates tls in front of the host may still be
	/// http-only on the loopback hop. a deployment that owns its tls should
	/// pass `__Host-auth`.
	public static let defaultCookieName = "auth"

	public let cookieName: String
	/// the session store. the resolver reads it; ``endSession(tokenHash:)``
	/// writes to it.
	public let store: any AuthSessionStore
	/// resolves a session's `identityID` to a role-carrying `Identity`. nil
	/// means "identity is the id with no roles", which is what a deployment
	/// without a directory wants.
	public let identities: (any IdentityDirectory)?
	/// the clock. injected because expiry is a behaviour worth testing without
	/// sleeping, and because a host may want one clock for the whole process.
	public let now: @Sendable () -> Date

	public init(
		cookieName: String = CookieSessionResolver.defaultCookieName,
		store: any AuthSessionStore,
		identities: (any IdentityDirectory)? = nil,
		now: @escaping @Sendable () -> Date = { Date() }
	) {
		self.cookieName = cookieName
		self.store = store
		self.identities = identities
		self.now = now
	}

	// MARK: reading

	public func principal(for request: HTTPRequest) async throws -> AuthContext? {
		guard let token = self.token(in: request) else { return nil }
		guard let hash = try? SessionToken.hash(token) else { return nil }
		guard let stored = try await store.find(tokenHash: hash) else { return nil }

		// absolute expiry, checked against the injected clock rather than the
		// session's own default `Date()` so a test and a host agree.
		guard !stored.isExpired(at: now()) else {
			// the session is over; drop the index entry so a stale cookie is
			// not resurrected by a sliding touch later.
			try? await store.invalidate(id: stored.id)
			return nil
		}

		var seen = stored
		seen.lastSeenAt = now()
		do {
			try await store.touch(seen)
		} catch {
			// the session was invalidated between `find` and `touch`: it is
			// gone, so this request has no principal. not an error — a
			// concurrent logout is the ordinary cause.
			return nil
		}

		return AuthContext(session: seen, identity: try await identity(for: seen.identityID))
	}

	/// the decoded token a request presents, or nil when it presents nothing
	/// usable.
	///
	/// reads the parsed cookie map first (what the server fills), then the raw
	/// `cookie` header — so a host that builds a request by hand, or drives the
	/// resolver over an embedded channel, does not have to remember to parse.
	private func token(in request: HTTPRequest) -> [UInt8]? {
		var value = request.cookies[cookieName]
		if value == nil, let header = request.headers.first(name: "cookie") {
			value = CookieParser.requestCookies(header)[cookieName]
		}
		guard let value, !value.isEmpty else { return nil }
		guard let bytes = Base64.decodeURL(value), bytes.count == SessionToken.byteCount else {
			return nil
		}
		return bytes
	}

	/// the identity a session's `identityID` names.
	///
	/// a directory that has forgotten the identity still yields the id with no
	/// roles — the session is authentic, and what it may do is nothing. it never
	/// yields `nil`: a resolved principal always names who it is, and "unknown
	/// identity" would otherwise be indistinguishable from "no identity, but
	/// authenticated", which is not a state that should exist.
	private func identity(for identityID: String) async throws -> Identity {
		guard let identities else { return Identity(id: identityID) }
		if let known = try await identities.identity(for: identityID) { return known }
		return Identity(id: identityID)
	}

	// MARK: writing

	public func endSession(tokenHash: [UInt8]) async throws {
		guard let session = try await store.find(tokenHash: tokenHash) else { return }
		try await store.invalidate(id: session.id)
	}
}

// MARK: - Session cookie

extension CookieSessionResolver {
	/// the `Set-Cookie` value that plants `token`.
	///
	/// the attributes are the safe default for a session cookie: `HttpOnly` (no
	/// script reads it), `SameSite=Lax` (a cross-site form post does not carry
	/// it), path `/`. `Secure` is the caller's decision because it is a
	/// property of the deployment's transport, not of the token.
	public static func sessionCookie(
		name: String = CookieSessionResolver.defaultCookieName,
		token: [UInt8],
		secure: Bool,
		maxAge: Int? = nil
	) -> SessionCookie {
		SessionCookie(
			name: name,
			value: Base64.encodeURL(token),
			attributes: SessionCookie.Attributes(
				maxAge: maxAge,
				path: "/",
				secure: secure,
				httpOnly: true,
				sameSite: .lax
			)
		)
	}

	/// the `Set-Cookie` value that clears `name`.
	public static func clearingCookie(
		name: String = CookieSessionResolver.defaultCookieName,
		secure: Bool
	) -> SessionCookie {
		SessionCookie(
			name: name,
			value: "",
			attributes: SessionCookie.Attributes(
				maxAge: 0,
				path: "/",
				secure: secure,
				httpOnly: true,
				sameSite: .lax
			)
		)
	}
}
