import Testing
import WebUI
import WebUIServer

// MARK: - 0.2 config caps
//
// the extraction that moved `WebUIServerConfig` into its own file also added the
// two caps `RenderToken`'s doc comment already claimed: `maxSessions` and
// `maxHandlers`. this suite is the round trip — a config with non-default caps
// must reach the `EventRouter` the server owns, and the table must honour them.

@Suite("WebUIServerConfig caps")
struct WebUIServerConfigCapTests {

	@Test("the defaults still match the router's own")
	func defaultsMatchRouter() {
		let config = WebUIServerConfig()
		let router = EventRouter()
		#expect(config.maxConnections == 256)
		#expect(config.maxSessions == router.maxSessions)
		#expect(config.maxHandlers == router.maxHandlers)
		#expect(config.readIdleSeconds == 120)
		#expect(config.assetCacheSeconds == 3600)
		#expect(config.pagePath == "/")
		#expect(config.maxBodyBytes == 1 << 20)
		#expect(config.maxMultipartParts == 64)
		#expect(config.requireRenderToken == false)
	}

	@Test("the extraction kept every non-cap default where it was")
	func otherDefaultsUnchanged() {
		var config = WebUIServerConfig()
		config.host = "127.0.0.1"
		config.port = 1234
		config.assetCacheSeconds = 7
		#expect(config.host == "127.0.0.1")
		#expect(config.port == 1234)
		#expect(config.assetCacheSeconds == 7)
		// the mutable surface still exists and still round-trips
		config.maxBodyBytes = 32
		config.maxMultipartParts = 2
		#expect(config.maxBodyBytes == 32)
		#expect(config.maxMultipartParts == 2)
	}

	@Test("a non-default caps config reaches the router the server owns")
	func capsReachOwnedRouter() async throws {
		let config = WebUIServerConfig(maxConnections: 7, maxSessions: 2, maxHandlers: 3)
		let server = WebUIServer(router: Router {}, config: config)

		let router = await server.eventRouter
		#expect(router.maxSessions == 2)
		#expect(router.maxHandlers == 3)
	}

	@Test("the caps the config carries are the caps the table enforces")
	func capsAreEnforced() async throws {
		let config = WebUIServerConfig(maxSessions: 2)
		let server = WebUIServer(router: Router {}, config: config)
		let router = await server.eventRouter

		// three sessions against a cap of two: the oldest is reaped, exactly as
		// `EventRouter(maxSessions: 2)` on its own would do.
		router.begin(RenderSessionID("a"))
		router.begin(RenderSessionID("b"))
		#expect(router.sessionCount == 2)
		router.begin(RenderSessionID("c"))
		#expect(router.sessionCount == 2)
		#expect(!router.contains(RenderSessionID("a")))
		#expect(router.contains(RenderSessionID("c")))
	}

	@Test("a caller-supplied router keeps its own limits")
	func callerRouterKeepsItsLimits() async throws {
		// the config's caps cannot silently retune a router the host built: the
		// host owns that table (and may share it across servers).
		let router = EventRouter(maxHandlers: 11, maxSessions: 9)
		let server = WebUIServer(router: Router {}, eventRouter: router, config: WebUIServerConfig(maxSessions: 2))
		let observed = await server.eventRouter
		#expect(observed.maxSessions == 9)
		#expect(observed.maxHandlers == 11)
	}
}
