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

// MARK: - AuthSessionStore

/// persistence contract for authentication sessions.
///
/// implementations are expected to be concurrency-safe (an actor or a
/// lock-guarded class). `find` looks up by the **hash** of the client-held
/// token — the raw token never reaches the store.
public protocol AuthSessionStore: Sendable {
	func create(_ session: AuthenticatedSession) async throws
	func find(tokenHash: [UInt8]) async throws -> AuthenticatedSession?
	func touch(_ session: AuthenticatedSession) async throws
	func invalidate(id: [UInt8]) async throws
	/// invalidate every session belonging to an identity (logout-everywhere).
	func invalidateAll(for identityID: String) async throws
	/// list a user's sessions, newest first.
	func listSessions(for identityID: String) async throws -> [AuthenticatedSession]
	/// remove every session whose `expiresAt` is at or before `date`.
	/// returns the number of purged sessions.
	@discardableResult
	func purgeExpired(before date: Date) async throws -> Int
}
