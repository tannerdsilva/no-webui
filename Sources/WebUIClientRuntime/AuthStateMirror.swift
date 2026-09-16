import WebUICore
import Synchronization

/// a read-only mirror of the server's session presence (d4: advisory ui
/// gating only — credentials, throttling, and session authority never move to
/// the client; every sensitive operation re-checks server-side).
public struct AuthStateMirror: Sendable, Equatable {
	public let sessionPresent: Bool
	public let roles: Set<String>

	public static let anonymous = AuthStateMirror(sessionPresent: false, roles: [])

	public func hasRole(_ role: String) -> Bool {
		sessionPresent && roles.contains(role)
	}
}

/// boot-envelope auth state parsing (the non-secret presentation handle the
/// server ships at boot: session-present + roles — never credentials).
extension AuthStateMirror {
	public init?(envelope: String) {
		guard let root = try? JSONValue.parse(envelope),
		      case .object(let dict) = root else { return nil }
		let present: Bool
		if case .bool(let value)? = dict["sessionPresent"] {
			present = value
		} else {
			present = false
		}
		var roles: Set<String> = []
		if case .array(let list)? = dict["roles"] {
			for item in list {
				if case .string(let role) = item { roles.insert(role) }
			}
		}
		self.init(sessionPresent: present, roles: roles)
	}
}
