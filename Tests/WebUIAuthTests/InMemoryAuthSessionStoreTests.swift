import Foundation
import Testing

@testable import WebUIAuth

@Suite("InMemoryAuthSessionStore")
struct InMemoryAuthSessionStoreTests {

	func makeSession(id: UInt8, identityID: String = "u1", createdAt: Double = 1_000, expiresAt: Double = 10_000) -> AuthenticatedSession {
		AuthenticatedSession(
			id: Data([id]),
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
		let store = InMemoryAuthSessionStore()
		let session = makeSession(id: 1)
		try await store.create(session)
		let found = try await store.find(tokenHash: session.tokenHash)
		#expect(found == session)
	}

	@Test("find returns nil for an unknown token hash")
	func findUnknown() async throws {
		let store = InMemoryAuthSessionStore()
		#expect(try await store.find(tokenHash: Data(repeating: 0x77, count: 32)) == nil)
	}

	@Test("duplicate create throws")
	func duplicate() async throws {
		let store = InMemoryAuthSessionStore()
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

	@Test("touch updates lastSeenAt")
	func touch() async throws {
		let store = InMemoryAuthSessionStore()
		var session = makeSession(id: 1)
		try await store.create(session)
		session.lastSeenAt = Date(timeIntervalSince1970: 9_999)
		try await store.touch(session)
		let found = try await store.find(tokenHash: session.tokenHash)
		#expect(found?.lastSeenAt == session.lastSeenAt)
	}

	@Test("invalidate removes the session; missing invalidate throws")
	func invalidate() async throws {
		let store = InMemoryAuthSessionStore()
		let session = makeSession(id: 1)
		try await store.create(session)
		try await store.invalidate(id: session.id)
		#expect(try await store.find(tokenHash: session.tokenHash) == nil)
		do {
			try await store.invalidate(id: session.id)
			Issue.record("expected notFound error")
		} catch let error as AuthStoreError {
			#expect(error == AuthStoreError.notFound)
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("invalidateAll removes every session for one identity only")
	func invalidateAll() async throws {
		let store = InMemoryAuthSessionStore()
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

	@Test("listSessions returns newest first")
	func listNewestFirst() async throws {
		let store = InMemoryAuthSessionStore()
		let old = makeSession(id: 1, createdAt: 1_000)
		let new = makeSession(id: 2, createdAt: 2_000)
		try await store.create(old)
		try await store.create(new)
		let listed = try await store.listSessions(for: "u1")
		#expect(listed.map(\.id) == [new.id, old.id])
	}

	@Test("purgeExpired removes only expired sessions and reports the count")
	func purge() async throws {
		let store = InMemoryAuthSessionStore()
		let live = makeSession(id: 1, expiresAt: 5_000)
		let dead = makeSession(id: 2, expiresAt: 3_000)
		try await store.create(live)
		try await store.create(dead)
		let count = try await store.purgeExpired(before: Date(timeIntervalSince1970: 4_000))
		#expect(count == 1)
		#expect(try await store.find(tokenHash: live.tokenHash) == live)
		#expect(try await store.find(tokenHash: dead.tokenHash) == nil)
	}

	@Test("concurrent create/invalidate stays consistent")
	func concurrentStress() async throws {
		let store = InMemoryAuthSessionStore()
		await withTaskGroup(of: Void.self) { group in
			for i in 0..<100 {
				group.addTask {
					let session = AuthenticatedSession(
						id: Data([UInt8(i % 250), UInt8(i >> 8)]),
						tokenHash: Data(repeating: UInt8(i), count: 32),
						identityID: "load",
						csrfSeed: Data([0x00]),
						createdAt: Date(),
						expiresAt: .distantFuture,
						lastSeenAt: Date()
					)
					try? await store.create(session)
				}
			}
		}
		let listed = try await store.listSessions(for: "load")
		#expect(listed.count == 100)
	}
}
