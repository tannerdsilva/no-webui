import Logging
import ServiceLifecycle

// MARK: - WebUIServerService

/// hosts a ``WebUIServer`` as a `Service`, so a long-lived page server starts
/// and stops inside a `ServiceGroup` rather than owning its own process
/// lifecycle.
///
/// `WebUIServer.start()` serves until `stop()`, and the lifecycle framework
/// implements shutdown by cancelling the task running `run()`. the cancellation
/// handler is non-async by signature, so it hops back onto the actor with a
/// `Task` — the only structured alternative would be restructuring `start()`
/// to return its accept loop to the caller, and that loop is the server's
/// whole contract.
///
/// ```swift
/// let server = WebUIServer(render: page, router: router, config: config)
/// let group = ServiceGroup(
///     services: [WebUIServerService(server: server)],
///     logger: logger
/// )
/// try await group.run()
/// ```
public struct WebUIServerService: Service {
	/// the server this service drives, exposed so a host can reach past the
	/// service (readiness probes, tests that stop directly).
	public let server: WebUIServer

	private let logger: Logger

	public init(server: WebUIServer, logger: Logger = Logger(label: "webui.service")) {
		self.server = server
		self.logger = logger
	}

	/// serve until the group shuts down.
	///
	/// a bind failure propagates out of `run()`: a service that cannot listen
	/// fails startup instead of reporting itself ready.
	///
	/// two shutdown doors, one action. the group's graceful path (what a signal
	/// does under the default `gracefulShutdownSignals`) runs
	/// ``withGracefulShutdownHandler``'s callback; task cancellation runs the
	/// `onCancel` handler. both close the listener, `start()` unwinds, and
	/// `run()` returns.
	///
	/// the graceful handler is not optional: `GracefulShutdownManager` only runs
	/// handlers registered through it, so a service with none leaves the group
	/// waiting for a completion that never arrives — `ServiceGroup(services:
	/// [service])`, the plainest construction there is, would hang on Ctrl-C.
	public func run() async throws {
		logger.info("webui service: starting")
		try await withGracefulShutdownHandler {
			try await withTaskCancellationHandler {
				try await server.start()
			} onCancel: {
				Task { await server.stop() }
			}
		} onGracefulShutdown: {
			Task { await server.stop() }
		}
		logger.info("webui service: stopped")
	}
}