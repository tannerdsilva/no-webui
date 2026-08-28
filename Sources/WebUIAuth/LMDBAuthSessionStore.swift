import Foundation
import WebUI
import QuickLMDB
import SystemPackage

// MARK: - LMDBAuthSessionStore

/// an LMDB-backed `AuthSessionStore` per the design in
/// `Documentation/AUTH_SESSIONS.md` and `IMPLEMENTATION_PLAN.md` (M0-T8).
///
/// schema (one environment, three named databases):
/// - `tok`   — session id (16 bytes) → JSON(`AuthenticatedSession`), primary
/// - `tk`    — SHA-256 token hash (32 bytes) → session id
/// - `user`  — identity id (utf8) → concatenated 16-byte session-id records
/// - `audit` — reserved for the M2 audit trail (opened, unused)
///
/// the `user` reverse index is intentionally denormalized (a raw array of
/// fixed-size id records) rather than an LMDB dupsort database: dupsort
/// requires custom `MDB_comparable` key types (a QuickLMDB macro applied to
/// consumer-declared types), and per-session rewrite of a small id list is
/// cheaper and simpler at this scale.
///
/// quicklmdb reading discipline (verified against the pinned revision):
/// `MDB_db_get_entry_static` **throws** `.notFound` for a missing key — the
/// `loadEntry` optional return never delivers nil. every `loadEntry` below is
/// therefore guarded by a `containsEntry` check in the same transaction (the
/// contains path maps NOTFOUND to `false`).
///
/// concurrency: this is an actor; every operation opens, uses and closes
/// exactly one LMDB transaction inside a single synchronous body, so each
/// transaction is bound to one thread and never straddles a suspension (LMDB
/// permits one read transaction per thread and one writer per environment —
/// the actor serializes writers). reads are `readOnly` and terminate via the
/// transaction's deinit abort; writes always end in `commit()` and on `throw`
/// the `~Copyable` transaction aborts itself in deinit — a committed
/// transaction is consumed, so there is no abort-after-commit path.
public actor LMDBAuthSessionStore: AuthSessionStore {

	private nonisolated let env: Environment
	private nonisolated let dbTok: Database
	private nonisolated let dbTokHash: Database
	private nonisolated let dbUser: Database
	private nonisolated let dbAudit: Database

	private static let sessionIDLength = 16

	/// open (or create) the store at `path`.
	///
	/// - Parameters:
	///   - path: the LMDB environment directory (created on demand by LMDB).
	///   - mapSize: LMDB map size in bytes; nil uses the LMDB default.
	public init(path: String, mapSize: Int? = nil) throws {
		let env = try Environment(
			path: path,
			flags: [],
			mapSize: mapSize,
			maxReaders: 128,
			maxDBs: 8,
			mode: FilePermissions(rawValue: 0o700)
		)
		let txn = try Transaction(env: env, readOnly: false)
		let dbTok = try Database(env: env, name: "tok", flags: [.create], tx: txn)
		let dbTokHash = try Database(env: env, name: "tk", flags: [.create], tx: txn)
		let dbUser = try Database(env: env, name: "user", flags: [.create], tx: txn)
		let dbAudit = try Database(env: env, name: "audit", flags: [.create], tx: txn)
		try txn.commit()
		self.env = env
		self.dbTok = dbTok
		self.dbTokHash = dbTokHash
		self.dbUser = dbUser
		self.dbAudit = dbAudit
	}

	// MARK: AuthSessionStore

	public func create(_ session: AuthenticatedSession) throws {
		let json = try JSONEncoder().encode(session)
		let txn = try Transaction(env: env, readOnly: false)
		guard !(try dbTok.containsEntry(key: [UInt8](session.id), tx: txn)) else {
			throw AuthStoreError.duplicateSession
		}
		try dbTok.setEntry(key: [UInt8](session.id), value: [UInt8](json), flags: [], tx: txn)
		try dbTokHash.setEntry(key: [UInt8](session.tokenHash), value: [UInt8](session.id), flags: [], tx: txn)
		try appendSessionID([UInt8](session.id), to: [UInt8](session.identityID.utf8), tx: txn)
		try txn.commit()
	}

	public func find(tokenHash: Data) throws -> AuthenticatedSession? {
		let txn = try Transaction(env: env, readOnly: true)
		let tokenKey = [UInt8](tokenHash)
		guard try dbTokHash.containsEntry(key: tokenKey, tx: txn),
		      let idBytes = try dbTokHash.loadEntry(key: tokenKey, as: [UInt8].self, tx: txn) else {
			return nil
		}
		return try loadSession(id: idBytes, tx: txn)
	}

	public func touch(_ session: AuthenticatedSession) throws {
		let json = try JSONEncoder().encode(session)
		let txn = try Transaction(env: env, readOnly: false)
		guard try dbTok.containsEntry(key: [UInt8](session.id), tx: txn) else {
			throw AuthStoreError.notFound
		}
		// only the primary row carries lastSeenAt; the indexes are untouched.
		try dbTok.setEntry(key: [UInt8](session.id), value: [UInt8](json), flags: [], tx: txn)
		try txn.commit()
	}

	public func invalidate(id: Data) throws {
		let txn = try Transaction(env: env, readOnly: false)
		guard try removeSession(id: [UInt8](id), tx: txn) else {
			throw AuthStoreError.notFound
		}
		try txn.commit()
	}

	public func invalidateAll(for identityID: String) throws {
		let txn = try Transaction(env: env, readOnly: false)
		let identityKey = [UInt8](identityID.utf8)
		if try dbUser.containsEntry(key: identityKey, tx: txn) {
			if let records = try dbUser.loadEntry(key: identityKey, as: [UInt8].self, tx: txn) {
				for id in Self.decodeSessionIDs(records) {
					_ = try? removeSession(id: id, tx: txn)
				}
			}
			// final sweep: per-session removal already clears the key when the
			// last session goes, so absence here is normal — tolerate it.
			try? dbUser.deleteEntry(key: identityKey, tx: txn)
		}
		try txn.commit()
	}

	public func listSessions(for identityID: String) throws -> [AuthenticatedSession] {
		let txn = try Transaction(env: env, readOnly: true)
		let identityKey = [UInt8](identityID.utf8)
		var result: [AuthenticatedSession] = []
		if try dbUser.containsEntry(key: identityKey, tx: txn),
		   let records = try dbUser.loadEntry(key: identityKey, as: [UInt8].self, tx: txn) {
			for id in Self.decodeSessionIDs(records) {
				if let session = try loadSession(id: id, tx: txn) {
					result.append(session)
				}
			}
		}
		return result.sorted { $0.createdAt > $1.createdAt }
	}

	@discardableResult
	public func purgeExpired(before date: Date) throws -> Int {
		let txn = try Transaction(env: env, readOnly: false)
		var expired: [(id: [UInt8], identityID: String)] = []
		dbTok.cursor(tx: txn) { cursor in
			for (key, value) in cursor.makeIterator() {
				guard let session = try? JSONDecoder().decode(
					AuthenticatedSession.self,
					from: Data(Self.bytes(value))
				), session.isExpired(at: date) else {
					continue
				}
				expired.append((id: Self.bytes(key), identityID: session.identityID))
			}
		}
		for entry in expired {
			_ = try removeSession(id: entry.id, tx: txn)
		}
		try txn.commit()
		return expired.count
	}

	// MARK: private helpers

	// MDB_val is a Sequence of UInt8; these overloads normalize both the cursor
	// tuple element and its optional form to [UInt8].

	private static func bytes(_ val: MDB_val) -> [UInt8] {
		Array(val)
	}

	private static func bytes(_ val: MDB_val?) -> [UInt8] {
		val.map { Array($0) } ?? []
	}

	/// remove a session and every index row pointing at it.
	/// - Returns: false when the session was already gone.
	private func removeSession(id: [UInt8], tx: borrowing Transaction) throws -> Bool {
		guard try dbTok.containsEntry(key: id, tx: tx),
		      let json = try dbTok.loadEntry(key: id, as: [UInt8].self, tx: tx) else {
			return false
		}
		let session = try JSONDecoder().decode(AuthenticatedSession.self, from: Data(json))
		try dbTok.deleteEntry(key: id, tx: tx)
		try dbTokHash.deleteEntry(key: [UInt8](session.tokenHash), tx: tx)
		try removeSessionID(id, from: [UInt8](session.identityID.utf8), tx: tx)
		return true
	}

	private func loadSession(id: [UInt8], tx: borrowing Transaction) throws -> AuthenticatedSession? {
		guard try dbTok.containsEntry(key: id, tx: tx),
		      let json = try dbTok.loadEntry(key: id, as: [UInt8].self, tx: tx) else {
			return nil
		}
		return try? JSONDecoder().decode(AuthenticatedSession.self, from: Data(json))
	}

	// user-index helpers: the value is a raw concatenation of 16-byte session
	// id records (no JSON, fixed stride, cheap to append and stride).

	private func appendSessionID(_ id: [UInt8], to identityKey: [UInt8], tx: borrowing Transaction) throws {
		precondition(id.count == Self.sessionIDLength,
		             "LMDBAuthSessionStore requires 16-byte session ids (fix: use 16 random bytes for AuthenticatedSession.id)")
		var records: [UInt8] = []
		if try dbUser.containsEntry(key: identityKey, tx: tx),
		   let existing = try dbUser.loadEntry(key: identityKey, as: [UInt8].self, tx: tx) {
			records = existing
		}
		records.append(contentsOf: id)
		try dbUser.setEntry(key: identityKey, value: records, flags: [], tx: tx)
	}

	private func removeSessionID(_ id: [UInt8], from identityKey: [UInt8], tx: borrowing Transaction) throws {
		var records: [UInt8] = []
		if try dbUser.containsEntry(key: identityKey, tx: tx),
		   let existing = try dbUser.loadEntry(key: identityKey, as: [UInt8].self, tx: tx) {
			records = existing
		}
		let ids = Self.decodeSessionIDs(records).filter { $0 != id }
		if ids.isEmpty {
			try dbUser.deleteEntry(key: identityKey, tx: tx)
		} else {
			try dbUser.setEntry(key: identityKey, value: Self.encodeSessionIDs(ids), flags: [], tx: tx)
		}
	}

	static func encodeSessionIDs(_ ids: [[UInt8]]) -> [UInt8] {
		var result: [UInt8] = []
		result.reserveCapacity(ids.count * sessionIDLength)
		for id in ids {
			result.append(contentsOf: id)
		}
		return result
	}

	static func decodeSessionIDs(_ records: [UInt8]) -> [[UInt8]] {
		guard records.count % sessionIDLength == 0 else {
			return []
		}
		var result: [[UInt8]] = []
		result.reserveCapacity(records.count / sessionIDLength)
		var index = 0
		while index < records.count {
			result.append(Array(records[index..<(index + sessionIDLength)]))
			index += sessionIDLength
		}
		return result
	}
}
