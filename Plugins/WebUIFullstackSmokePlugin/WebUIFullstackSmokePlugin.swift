import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PackagePlugin

// self-contained full-stack gate: one command spawns the WebUISmokeTest
// server (bind() requires the sandbox to be disabled), drives live WebSocket
// round-trips through designer/fullstack-smoke.mjs (node), then tears the
// server down. see WebUISmokePlugin for why gates host their own server.
//
//   swift package --disable-sandbox plugin --allow-network-connections local:9123 fullstack-smoke [--port 9123]

@main
struct WebUIFullstackSmokePlugin: CommandPlugin {
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
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        print("=== WebUI full-stack smoke check ===")
        print("  base: \(base)")

        var ready = false
        for _ in 0..<40 {
            if let body = await GETBody(session, "\(base)/"), !body.isEmpty {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard ready else {
            Diagnostics.error("server did not become ready on :\(port) — run with --disable-sandbox")
            return
        }
        print("  PASS server ready on :\(port)")

        let script = context.package.directoryURL
            .appendingPathComponent("designer/fullstack-smoke.mjs")
        let driver = Process()
        driver.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        driver.arguments = ["node", script.path, "--port", port]
        driver.standardOutput = FileHandle.standardOutput
        driver.standardError = FileHandle.standardError
        try driver.run()
        driver.waitUntilExit()

        if driver.terminationStatus != 0 {
            Diagnostics.error("full-stack smoke gate failed (exit \(driver.terminationStatus))")
        }
    }

    private func GETBody(_ session: URLSession, _ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await session.data(from: url).0
    }
}
