import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PackagePlugin

// nonisolated(unsafe): signal handlers can't capture, and can't touch an
// actor-isolated global either. the var is written once before handlers are
// installed and only read by the c handlers that forward the signal.
nonisolated(unsafe) private var showcaseChildPID: Int32 = -1

// c-convention handlers (no captures allowed): forward the signal to the child
// server so a Ctrl+C / kill on the plugin invocation also stops the server.
private func forwardShowcaseTermination(_ sig: Int32) {
    if showcaseChildPID > 0 {
        kill(showcaseChildPID, sig)
    }
    exit(0)
}

// hosts the live swift-generated showcase server as a child. like `serve`,
// the command-plugin sandbox forbids listen() (bind fails with EPERM), so the
// sandbox must be disabled:
//
//   swift package --disable-sandbox plugin showcase-serve
//
// the plugin spawns the WebUIShowcaseServer tool, keeps the process alive for
// as long as the server runs, and forwards the child's stdout/stderr.

@main
struct WebUIShowcaseServePlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let port = extractor.extractOption(named: "port").first ?? "9092"
        let base = "http://127.0.0.1:\(port)"

        let server = try context.tool(named: "WebUIShowcaseServer")

        let process = Process()
        process.executableURL = server.url
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()

        showcaseChildPID = process.processIdentifier
        signal(SIGTERM, forwardShowcaseTermination)
        signal(SIGINT, forwardShowcaseTermination)

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
            Diagnostics.error("showcase server did not become ready on :\(port) — run with --disable-sandbox")
            process.terminate()
            return
        }

        print("showcase-serve: \(base) (ws://127.0.0.1:\(port)/ws)")
        print("  host: swift package --disable-sandbox plugin showcase-serve")
        print("  Ctrl+C to stop")

        while process.isRunning {
            try await Task.sleep(for: .milliseconds(250))
        }
        print("showcase server exited; showcase-serve plugin exiting")
    }

    private func httpOK(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (_, response) = try? await session.data(from: url) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
