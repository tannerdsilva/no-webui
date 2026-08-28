import Foundation
import Testing

@testable import WebUIAuth

@Suite("AuthenticatedSession")
struct SessionTests {

	func makeSession(expiresAt: Date = .distantFuture) -> AuthenticatedSession {
		AuthenticatedSession(
			id: Data([0x01, 0x02, 0x03, 0x04]),
			tokenHash: Data(repeating: 0xAB, count: 32),
			identityID: "u1",
			csrfSeed: Data([0x05, 0x06]),
			createdAt: Date(timeIntervalSince1970: 1_000),
			expiresAt: expiresAt,
			lastSeenAt: Date(timeIntervalSince1970: 1_000)
		)
	}

	@Test("codable round trip preserves every field")
	func codableRoundTrip() throws {
		let session = makeSession()
		let data = try JSONEncoder().encode(session)
		let decoded = try JSONDecoder().decode(AuthenticatedSession.self, from: data)
		#expect(decoded == session)
		#expect(decoded.tokenHash == session.tokenHash)
		#expect(decoded.identityID == "u1")
	}

	@Test("isExpired honors the wall clock")
	func expiry() {
		let past = makeSession(expiresAt: Date(timeIntervalSince1970: 500))
		#expect(past.isExpired(at: Date(timeIntervalSince1970: 501)))
		let future = makeSession(expiresAt: Date(timeIntervalSince1970: 1_000))
		#expect(future.isExpired(at: Date(timeIntervalSince1970: 999)) == false)
		#expect(future.isExpired(at: Date(timeIntervalSince1970: 1_000)))
	}
}
