import WebUI
import WebUIDesignSystem

// MARK: - Configuration

/// tuning for `WebUIServer`. defaults match the reference servers: bind any
/// interface, 256-connection admission cap, 120 s read idle, one-hour asset
/// cache, 1 024 render sessions and 10 000 handlers per session — the caps
/// `EventRouter` enforces.
///
/// the three capacity numbers live here so one config value reaches the table
/// that enforces it: `maxConnections` bounds accepted sockets at admission
/// (`ConnectionGate`), and `maxSessions`/`maxHandlers` are handed to the router
/// the server owns. a server handed an `EventRouter` by its host keeps that
/// router's own limits — the host built it, so the host tunes it.
public struct WebUIServerConfig: Sendable {
	public var host: String
	public var port: Int
	public var maxConnections: Int
	/// the most render sessions the server's own router holds before reaping
	/// the least-recently-used. mirrors ``EventRouter/maxSessions``.
	public var maxSessions: Int
	/// the most handlers one render session may register. mirrors
	/// ``EventRouter/maxHandlers``; exceeding it is a
	/// ``WebUIFailure/handlerCapReached(session:limit:)``.
	public var maxHandlers: Int
	public var readIdleSeconds: Int64
	public var assetCacheSeconds: Int
	public var pagePath: String
	/// the host's rendered theme catalog (see ``ThemeSheet``), served at its
	/// content-addressed `url` with a year-long immutable cache. the same value's `url` is
	/// what a ``WebUIDocument`` links, so the page and the server agree by construction.
	public var themeSheet: ThemeSheet?
	/// extra assets this host serves (see ``WebUIServerAsset``). the framework
	/// routes and the page route are matched first, so an entry here can
	/// neither shadow nor disable them. duplicate paths: the last entry wins.
	public var assets: [WebUIServerAsset]

	/// when true, a websocket `event`/`ping` whose render token is absent or
	/// unknown is answered with a `token` error frame and the socket is closed
	/// (AGENTS.md security invariant 11).
	///
	/// defaults to false so a 1.x host that never threaded a token keeps working
	/// unchanged; it flips to true at the 2.0 cut. a host that threads the token
	/// today — pass `WebUIServerRequest.renderToken.value` into the document's
	/// `renderToken:` — can turn it on now.
	public var requireRenderToken: Bool

	/// what the server does when a handler throws.
	///
	/// defaults to ``HandlerFailurePolicy/notifyClient``: the page is told and,
	/// when the component registered a fallback, given something to render in the
	/// broken control's place. a silent failure is what made C3 invisible.
	public var handlerFailurePolicy: HandlerFailurePolicy
	/// what a failed page render answers over http: the host's error page for
	/// the thrown error. `nil` answers a plain-text 500 naming the failure.
	///
	/// a render throw used to surface as a dead page — the error propagated up
	/// and the connection was dropped. with this set, the request is answered
	/// with a 500 carrying `onRenderFailure(error)`, so the failure is visible
	/// and the connection survives. a swift trap is not an error and never
	/// reaches this closure (see `STABILITY.md`).
	public var onRenderFailure: (@Sendable (any Error) -> String)?

	/// the hard cap on one request body, in bytes. a declared `Content-Length`
	/// over the cap is refused before a single body byte is buffered, and a
	/// body that grows past it mid-stream is cut off — an upload endpoint
	/// without a cap is a DoS (plan w3.3). default 1 MiB.
	public var maxBodyBytes: Int
	/// the hard cap on one multipart body's parts. exceeding it is a 422 that
	/// names the limit. default 64.
	public var maxMultipartParts: Int

	public init(
		host: String = "0.0.0.0",
		port: Int = 9090,
		maxConnections: Int = 256,
		maxSessions: Int = 1_024,
		maxHandlers: Int = 10_000,
		readIdleSeconds: Int64 = 120,
		assetCacheSeconds: Int = 3600,
		pagePath: String = "/",
		themeSheet: ThemeSheet? = nil,
		assets: [WebUIServerAsset] = [],
		requireRenderToken: Bool = false,
		handlerFailurePolicy: HandlerFailurePolicy = .notifyClient,
		onRenderFailure: (@Sendable (any Error) -> String)? = nil,
		maxBodyBytes: Int = 1 << 20,
		maxMultipartParts: Int = 64
	) {
		self.host = host
		self.port = port
		self.maxConnections = maxConnections
		self.maxSessions = maxSessions
		self.maxHandlers = maxHandlers
		self.readIdleSeconds = readIdleSeconds
		self.assetCacheSeconds = assetCacheSeconds
		self.pagePath = pagePath
		self.themeSheet = themeSheet
		self.assets = assets
		self.requireRenderToken = requireRenderToken
		self.handlerFailurePolicy = handlerFailurePolicy
		self.onRenderFailure = onRenderFailure
		self.maxBodyBytes = maxBodyBytes
		self.maxMultipartParts = maxMultipartParts
	}
}
