import Foundation

// MARK: - AuthContext

/// the ambient authentication state for a request or an event dispatch.
///
/// mirrors `RenderContext`: a `@TaskLocal` set by the server around
/// authenticated renders and around `EventRouter.handle` dispatches. views
/// branch on `identity?.roles`; handlers and audit code read identity from the
/// bound session's context, never from a closure parameter.
public struct AuthContext: Sendable, Equatable {
	public let session: AuthenticatedSession
	public let identity: Identity?

	public init(session: AuthenticatedSession, identity: Identity? = nil) {
		self.session = session
		self.identity = identity
	}

	public func hasRole(_ role: String) -> Bool {
		identity?.roles.contains(role) ?? false
	}

	@TaskLocal public static var current: AuthContext?
}
