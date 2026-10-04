import Logging
import WebUI
import WebUIBlocks
import WebUIServer

// MARK: - Standalone blocks server
//
// one block per process: `--block <name>` (default `index`, which lists every
// block). the framework's server takes a single render closure with no request
// argument, so multi-route dispatch would mean changing a pinned public API;
// serving one block at "/" keeps every block genuinely standalone, which is the
// property the p6 exit gate asks for, and the index links them all.

/// `--flag <int>` with a default (the same parser shape as the showcase server).
func intFlag(named name: String, default fallback: Int) -> Int {
	if let i = CommandLine.arguments.firstIndex(of: name),
	   i + 1 < CommandLine.arguments.count,
	   let v = Int(CommandLine.arguments[i + 1]), v > 0 {
		return v
	}
	return fallback
}

/// `--flag <string>` with a default.
func stringFlag(named name: String, default fallback: String) -> String {
	if let i = CommandLine.arguments.firstIndex(of: name),
	   i + 1 < CommandLine.arguments.count {
		return CommandLine.arguments[i + 1]
	}
	return fallback
}

@main
struct WebUIBlocksServer {
	static func main() async throws {
		let logger = Logger(label: "webui.blocks")
		let port = intFlag(named: "--port", default: 9093)
		let name = stringFlag(named: "--block", default: "index")
		let dir = stringFlag(named: "--dir", default: "")
		let block = Block(rawValue: name)

		guard name == "index" || block != nil else {
			let known = (["index"] + Block.allCases.map { $0.rawValue }).joined(separator: ", ")
			logger.error("unknown block '\(name)'; known blocks: \(known)")
			return
		}

		// one router for the process: a block that grows handlers registers them
		// here and the server routes its events over the same socket.
		let router = EventRouter()
		let server = WebUIServer(
			render: {
				if let block {
					return WebUIBlocks.page(for: block, dir: dir.isEmpty ? nil : dir)
				}
				return WebUIBlocks.indexPage(dir: dir.isEmpty ? nil : dir)
			},
			router: router,
			config: WebUIServerConfig(
			host: "0.0.0.0",
			port: port,
			// the generated engine slice (continuum §1.5): the engine fetches
			// it at boot and swaps its conservative attr seed for it.
			assets: [
				WebUIAsset(ContinuumEngineManifest.self, path: "/ui/continuum-manifest.json").registration
			]
		)
		)
		logger.info("serving block '\(name)' on http://0.0.0.0:\(port)")
		try await server.start()
	}
}