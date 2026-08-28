import Foundation
import Testing

@testable import WebUIAuth

@Suite("AuthContext")
struct AuthContextTests {

	func makeSession() -> AuthenticatedSession {
		AuthenticatedSession(
			id: Data([0x01]),
			tokenHash: Data(repeating: 0xAB, count: 32),
			identityID: "member-7",
			csrfSeed: Data([0x02]),
			createdAt: Date(),
			expiresAt: .distantFuture,
			lastSeenAt: Date()
		)
	}

	@Test("TaskLocal carries the context across an async boundary")
	func taskLocalPropagation() async {
		let context = AuthContext(
			session: makeSession(),
			identity: Identity(id: "member-7", roles: [Role.admin])
		)
		// a plain Task inherits task-local values; Task.detached deliberately
		// does not, so this must be an inheriting child task.
		let seen = await AuthContext.$current.withValue(context) {
			await Task { AuthContext.current }.value
		}
		#expect(seen == context)
		#expect(seen?.identity?.id == "member-7")
	}

	@Test("TaskLocal is nil without a wrapping withValue")
	func unsetIsNil() async {
		#expect(AuthContext.current == nil)
	}

	@Test("hasRole consults the identity's roles")
	func roleCheck() {
		let member = AuthContext(
			session: makeSession(),
			identity: Identity(id: "x", roles: [Role.member])
		)
		#expect(member.hasRole(Role.member))
		#expect(member.hasRole(Role.admin) == false)
		let anonymous = AuthContext(session: makeSession(), identity: nil)
		#expect(anonymous.hasRole(Role.member) == false)
	}
}
