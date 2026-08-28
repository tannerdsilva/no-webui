import Foundation

// MARK: - Errors

/// errors common to session-store operations.
public enum AuthStoreError: Error, Equatable, Sendable {
	/// a session with the same id already exists.
	case duplicateSession
	/// the session does not exist.
	case notFound
	/// a stored record failed to decode.
	case malformedRecord(String)
}

// MARK: - UserStore

/// the backend's source of identities. the framework never assumes how the
/// backend stores users — only that it can resolve a username to an identity
/// (or nil). password verification is the `Authenticator`'s job.
public protocol UserStore: Sendable {
	func identity(forUsername username: String) async throws -> Identity?
}

// MARK: - Authenticator

/// verifies presented credentials and returns the authenticated identity.
/// `nil` means the credentials are invalid (or the user does not exist) —
/// the framework treats both identically to avoid leaking existence.
public protocol Authenticator: Sendable {
	func authenticate(_ credential: Credential) async throws -> Identity?
}

// MARK: - AuthSessionStore

/// persistence contract for authentication sessions.
///
/// implementations are expected to be concurrency-safe (an actor or a
/// lock-guarded class). `find` looks up by the **hash** of the client-held
/// token — the raw token never reaches the store.
public protocol AuthSessionStore: Sendable {
	func create(_ session: AuthenticatedSession) async throws
	func find(tokenHash: Data) async throws -> AuthenticatedSession?
	func touch(_ session: AuthenticatedSession) async throws
	func invalidate(id: Data) async throws
	/// invalidate every session belonging to an identity (logout-everywhere).
	func invalidateAll(for identityID: String) async throws
	/// list a user's sessions, newest first.
	func listSessions(for identityID: String) async throws -> [AuthenticatedSession]
	/// remove every session whose `expiresAt` is at or before `date`.
	/// returns the number of purged sessions.
	@discardableResult
	func purgeExpired(before date: Date) async throws -> Int
}
