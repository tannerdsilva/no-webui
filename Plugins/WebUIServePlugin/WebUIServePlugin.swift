import Foundation
import PackagePlugin

// nonisolated(unsafe): signal handlers can't capture, and can't touch an
// actor-isolated global either. the var is written once before handlers are
// installed and only read by the c handlers that forward the signal.
nonisolated(unsafe) private var serveChildPID: Int32 = -1

// c-convention handlers (no captures allowed): forward the signal to the child
// server so a Ctrl+C / kill on the plugin invocation also stops the server.
private func forwardTermination(_ sig: Int32) {
    if serveChildPID > 0 {
        kill(serveChildPID, sig)
    }
    exit(0)
}

// binds a port and listens by hosting the WebUISmokeTest server as a child.
// the command-plugin sandbox forbids listen() — bind fails with EPERM even
// with the local network permission (that permission is outbound-only). the
// sandbox must therefore be disabled for this verb:
//
//   swift package --disable-sandbox plugin --allow-network-connections local:9123 serve
//
// the plugin then spawns the server (which it resolves via tool(named:)),
// keeps the process alive for as long as the server runs, and forwards the
// child's stdout/stderr. Ctrl+C on the invocation stops both.

@main
struct WebUIServePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let port = extractor.extractOption(named: "port").first ?? "9123"
        let base = "http://127.0.0.1:\(port)"

        let server = try context.tool(named: "WebUISmokeTest")

        let process = Process()
        process.executableURL = server.url
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()

        serveChildPID = process.processIdentifier
        signal(SIGTERM, forwardTermination)
        signal(SIGINT, forwardTermination)

        var ready = false
        for _ in 0..<40 {
            if await httpOK("\(base)/") {
                ready = true
                break
            }
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(250))
        }

        guard ready else {
            Diagnostics.error("server did not become ready on :\(port)")
            process.terminate()
            return
        }

        print("serve: \(base) (ws://127.0.0.1:\(port)/ws)")
        print("  host: swift package --disable-sandbox plugin serve")
        print("  Ctrl+C to stop")

        while process.isRunning {
            try await Task.sleep(for: .milliseconds(250))
        }
        print("server exited; serve plugin exiting")
    }

    private func httpOK(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(from: url) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
