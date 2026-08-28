import Foundation
import Testing

@testable import WebUIAuth

@Suite("Identity")
struct IdentityTests {

	@Test("codable round trip preserves id and roles")
	func codableRoundTrip() throws {
		let identity = Identity(id: "member-42", roles: [Role.member, "tee-time-booker"])
		let data = try JSONEncoder().encode(identity)
		let decoded = try JSONDecoder().decode(Identity.self, from: data)
		#expect(decoded == identity)
		#expect(decoded.id == "member-42")
		#expect(decoded.roles.contains(Role.admin) == false)
	}

	@Test("default roles are empty")
	func defaultRoles() {
		let identity = Identity(id: "x")
		#expect(identity.roles.isEmpty)
	}
}

@Suite("Credential")
struct CredentialTests {

	@Test("credential carries raw password bytes through to the authenticator")
	func credentialCarriesSecret() {
		let secret = Data("s3cret".utf8)
		let credential = Credential(username: "tanner", secret: secret)
		#expect(credential.username == "tanner")
		#expect(credential.secret == secret)
	}
}
