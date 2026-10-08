import WebUI

// MARK: - RenderToken

/// the identity of one page render, minted by the server and echoed by the
/// client on every `event`/`ping` frame.
///
/// the token is the key the router routes against: a message is answered in the
/// session that minted its token, so a page rendered before a reload — or before
/// a different user logged in — cannot drive another page's handlers. this is
/// what makes AGENTS.md security invariant 11 true of `WebUIServer` itself,
/// rather than only of a host that hand-rolls its own NIO server.
///
/// the guarantee, stated exactly: a frame is answered only by handlers that a
/// render this process actually served registered, and a frame naming a token
/// this process never minted — a forgery, or one from before a restart — is
/// refused and its socket closed. sessions are LRU-bounded
/// (`WebUIServerConfig` → `EventRouter.maxSessions`), so an old render's session
/// eventually falls off the table.
///
/// what it does not do: distinguish two clients. `WebUIServer` serves one shared
/// page from one router, so per-identity routing stays a host concern — a host
/// that renders per-user content mints its own token and keeps its own router per
/// identity, as `WebUIAuthExample` demonstrates.
public struct RenderToken: Sendable, Hashable, CustomStringConvertible {
	/// the wire form: 16 random bytes, base64url, no padding.
	public let value: String

	public init(_ value: String) {
		self.value = value
	}

	/// the router namespace this token owns.
	public var session: RenderSessionID { RenderSessionID(value) }

	/// mint a fresh 128-bit token.
	///
	/// `nil` only when the platform entropy source fails. the caller must treat
	/// that as a degraded render — never as a reason to substitute a guessable
	/// token, which would be worse than none — see `WebUIServer.handleHTTP`.
	public static func mint() -> RenderToken? {
		guard let bytes = SecureRandom.bytes(16) else { return nil }
		return RenderToken(Base64.encodeURL(bytes))
	}

	public var description: String { value }
}