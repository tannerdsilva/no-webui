import Foundation
import Logging
import ServiceLifecycle
import WebUI
import WebUIServer
import WebUISmokeShared

// MARK: - the smoke host
//
// `WebUIServer` owns everything the 1000-line NIO bootstrap here used to hand
// roll: the page render, the framework assets (css, engine, shell), the `/ws`
// upgrade, `EventRouter` dispatch, ping/pong, read-idle reaping and the
// admission cap. what is left is the route table (`SmokeHost.swift`), the
// host's own assets, and the launch.

/// parse a positive-integer flag (`--name N`) with a fallback.
func intFlag(named name: String, default fallback: Int) -> Int {
	if let i = CommandLine.arguments.firstIndex(of: name),
	   i + 1 < CommandLine.arguments.count,
	   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
		return v
	}
	return fallback
}

@main
struct WebUISmokeHost {
	static func main() async throws {
		// hydration byte-identity mode: print the shared hydration view's SSR
		// bytes and stop (the wasm client's --verify-render must match them).
		if CommandLine.arguments.contains("--print-hydration-ssr") {
			print(HydrationView().markup.html)
			return
		}

		let logger = Logger(label: "webui.smoketest")
		let port = intFlag(named: "--port", default: 9123)
		let state = SmokeState()
		let router = EventRouter()

		// `requireRenderToken` stays OFF: see `SmokePageResponder` — the gates'
		// wire clients speak the 1.x tokenless envelope, so enforcement would
		// refuse the first ping and close the socket.
		let server = WebUIServer(
			router: smokeRoutes(state: state, router: router),
			eventRouter: router,
			config: WebUIServerConfig(
				host: "127.0.0.1",
				port: port,
				maxConnections: intFlag(named: "--max-connections", default: 256),
				assets: smokeAssets(),
				requireRenderToken: false
			),
			logger: logger
		)
		logger.info("full-stack smoke server on http://127.0.0.1:\(port) (ws://127.0.0.1:\(port)/ws)")

		// a long-lived process is launched by the group, not awaited in main.
		let group = ServiceGroup(
			services: [WebUIServerService(server: server)],
			gracefulShutdownSignals: [.sigterm, .sigint],
			logger: logger
		)
		do {
			try await group.run()
		} catch is CancellationError {
			// the signal asked for exactly this: the listener is already down.
		}
	}
}
