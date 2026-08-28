import Foundation

// MARK: - InMemoryAuthSessionStore

/// an actor-backed in-memory `AuthSessionStore` — the test double and the
/// reference implementation for store semantics.
///
/// maps: primary `id → session`, `tokenHash → id`, and a reverse
/// `identityID → set of session ids` for logout-everywhere and session caps.
public actor InMemoryAuthSessionStore: AuthSessionStore {

	private var sessions: [Data: AuthenticatedSession] = [:]
	private var tokenIndex: [Data: Data] = [:]
	private var byIdentity: [String: Set<Data>] = [:]

	public init() {}

	public func create(_ session: AuthenticatedSession) throws {
		guard sessions[session.id] == nil else {
			throw AuthStoreError.duplicateSession
		}
		sessions[session.id] = session
		tokenIndex[session.tokenHash] = session.id
		byIdentity[session.identityID, default: []].insert(session.id)
	}

	public func find(tokenHash: Data) throws -> AuthenticatedSession? {
		guard let id = tokenIndex[tokenHash], let session = sessions[id] else {
			return nil
		}
		return session
	}

	public func touch(_ session: AuthenticatedSession) throws {
		guard var stored = sessions[session.id] else {
			throw AuthStoreError.notFound
		}
		stored.lastSeenAt = session.lastSeenAt
		sessions[session.id] = stored
	}

	public func invalidate(id: Data) throws {
		guard let session = sessions.removeValue(forKey: id) else {
			throw AuthStoreError.notFound
		}
		tokenIndex.removeValue(forKey: session.tokenHash)
		byIdentity[session.identityID]?.remove(session.id)
	}

	public func invalidateAll(for identityID: String) throws {
		let ids = byIdentity[identityID] ?? []
		for id in ids {
			if let session = sessions.removeValue(forKey: id) {
				tokenIndex.removeValue(forKey: session.tokenHash)
			}
		}
		byIdentity.removeValue(forKey: identityID)
	}

	public func listSessions(for identityID: String) throws -> [AuthenticatedSession] {
		(byIdentity[identityID] ?? [])
			.compactMap { sessions[$0] }
			.sorted { $0.createdAt > $1.createdAt }
	}

	@discardableResult
	public func purgeExpired(before date: Date) throws -> Int {
		let expired = sessions.values
			.filter { $0.expiresAt <= date }
			.map { $0.id }
		for id in expired {
			if let session = sessions.removeValue(forKey: id) {
				tokenIndex.removeValue(forKey: session.tokenHash)
				byIdentity[session.identityID]?.remove(id)
			}
		}
		return expired.count
	}
}
