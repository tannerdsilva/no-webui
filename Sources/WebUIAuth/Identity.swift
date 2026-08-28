import Foundation

// MARK: - Identity

/// an authenticated principal in the backend's domain.
///
/// `id` is the backend's stable identifier (member number, email, …). `roles`
/// is the role set the framework guards on (`"member"`, `"admin"`, and any
/// backend-defined role); the backend owns the mapping from stored credentials
/// to identities via its `UserStore`.
public struct Identity: Sendable, Codable, Hashable {
	public let id: String
	public let roles: Set<String>

	public init(id: String, roles: Set<String> = []) {
		self.id = id
		self.roles = roles
	}
}

/// well-known role strings. backends are free to define their own roles; these
/// are the conventional ones the example and guards reference.
public enum Role {
	public static let member = "member"
	public static let admin = "admin"
}

// MARK: - Credential

/// credentials presented at login. `secret` is the raw password bytes and is
/// intended for single-use — never retain it past the authentication call
/// that consumes it.
public struct Credential: Sendable, Equatable {
	public let username: String
	public let secret: Data

	public init(username: String, secret: Data) {
		self.username = username
		self.secret = secret
	}
}
