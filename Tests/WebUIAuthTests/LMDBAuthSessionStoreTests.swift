import Foundation
import Testing

@testable import WebUIAuth

@Suite("LMDBAuthSessionStore")
struct LMDBAuthSessionStoreTests {

	func makeSession(id: UInt8, identityID: String = "u1", createdAt: Double = 1_000, expiresAt: Double = 10_000) -> AuthenticatedSession {
		AuthenticatedSession(
			// the LMDB store's reverse index stores fixed 16-byte session-id
			// records — the fixture must honor that contract.
			id: Data([id] + [UInt8](repeating: 0x00, count: 15)),
			tokenHash: Data(repeating: id, count: 32),
			identityID: identityID,
			csrfSeed: Data([id, 0xEE]),
			createdAt: Date(timeIntervalSince1970: createdAt),
			expiresAt: Date(timeIntervalSince1970: expiresAt),
			lastSeenAt: Date(timeIntervalSince1970: createdAt)
		)
	}

	@Test("create then find by token hash")
	func createAndFind() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let session = makeSession(id: 1)
			try await store.create(session)
			let found = try await store.find(tokenHash: session.tokenHash)
			#expect(found == session)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("find returns nil for unknown token hashes")
	func findUnknown() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			#expect(try await store.find(tokenHash: Data(repeating: 0x77, count: 32)) == nil)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("duplicate create throws")
	func duplicate() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let session = makeSession(id: 1)
			try await store.create(session)
			do {
				try await store.create(session)
				Issue.record("expected duplicateSession error")
			} catch let error as AuthStoreError {
				#expect(error == AuthStoreError.duplicateSession)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("touch updates lastSeenAt")
	func touch() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			var session = makeSession(id: 1)
			try await store.create(session)
			session.lastSeenAt = Date(timeIntervalSince1970: 9_999)
			try await store.touch(session)
			let found = try await store.find(tokenHash: session.tokenHash)
			#expect(found?.lastSeenAt == session.lastSeenAt)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("touch on a missing session throws")
	func touchMissing() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			do {
				try await store.touch(makeSession(id: 9))
				Issue.record("expected notFound error")
			} catch let error as AuthStoreError {
				#expect(error == AuthStoreError.notFound)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("invalidate removes every index row")
	func invalidate() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let session = makeSession(id: 1)
			try await store.create(session)
			try await store.invalidate(id: session.id)
			#expect(try await store.find(tokenHash: session.tokenHash) == nil)
			#expect(try await store.listSessions(for: session.identityID).isEmpty)
			do {
				try await store.invalidate(id: session.id)
				Issue.record("expected notFound error")
			} catch let error as AuthStoreError {
				#expect(error == AuthStoreError.notFound)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("invalidateAll removes every session for one identity only")
	func invalidateAll() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let a1 = makeSession(id: 1, identityID: "u1")
			let a2 = makeSession(id: 2, identityID: "u1")
			let b1 = makeSession(id: 3, identityID: "u2")
			try await store.create(a1)
			try await store.create(a2)
			try await store.create(b1)
			try await store.invalidateAll(for: "u1")
			#expect(try await store.find(tokenHash: a1.tokenHash) == nil)
			#expect(try await store.find(tokenHash: a2.tokenHash) == nil)
			#expect(try await store.find(tokenHash: b1.tokenHash) == b1)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("listSessions returns newest first")
	func listNewestFirst() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let old = makeSession(id: 1, createdAt: 1_000)
			let new = makeSession(id: 2, createdAt: 2_000)
			try await store.create(old)
			try await store.create(new)
			let listed = try await store.listSessions(for: "u1")
			#expect(listed.map(\.id) == [new.id, old.id])
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("purgeExpired removes only expired sessions and reports the count")
	func purge() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			let live = makeSession(id: 1, expiresAt: 5_000)
			let dead = makeSession(id: 2, expiresAt: 3_000)
			try await store.create(live)
			try await store.create(dead)
			let count = try await store.purgeExpired(before: Date(timeIntervalSince1970: 4_000))
			#expect(count == 1)
			#expect(try await store.find(tokenHash: live.tokenHash) == live)
			#expect(try await store.find(tokenHash: dead.tokenHash) == nil)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("sessions survive an environment close and reopen")
	func persistenceAcrossReopen() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		let a1 = makeSession(id: 1, identityID: "u1")
		let a2 = makeSession(id: 2, identityID: "u1")
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			try await store.create(a1)
			try await store.create(a2)
		}
		do {
			let reopened = try LMDBAuthSessionStore(path: dir)
			let found = try await reopened.find(tokenHash: a1.tokenHash)
			#expect(found == a1)
			let listed = try await reopened.listSessions(for: "u1")
			#expect(listed.count == 2)
		}
		LMDBTestEnvironment.remove(dir)
	}

	@Test("concurrent writers serialize cleanly under the actor")
	func concurrentWriters() async throws {
		let dir = try LMDBTestEnvironment.makeTempDirectory()
		do {
			let store = try LMDBAuthSessionStore(path: dir)
			await withTaskGroup(of: Void.self) { group in
				for i in 0..<20 {
					group.addTask {
						let session = AuthenticatedSession(
							id: Data([UInt8(i)] + [UInt8](repeating: 0x00, count: 15)),
							tokenHash: Data(repeating: UInt8(i), count: 32),
							identityID: "load",
							csrfSeed: Data([0x00]),
							createdAt: .distantPast.addingTimeInterval(TimeInterval(i)),
							expiresAt: .distantFuture,
							lastSeenAt: Date()
						)
						try? await store.create(session)
					}
				}
			}
			let listed = try await store.listSessions(for: "load")
			#expect(listed.count == 20)
		}
		LMDBTestEnvironment.remove(dir)
	}
}
