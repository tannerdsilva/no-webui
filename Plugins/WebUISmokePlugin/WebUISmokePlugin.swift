import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PackagePlugin

// self-contained smoke gate: one command spawns the WebUISmokeTest server
// (bind() requires the sandbox to be disabled), checks it over loopback,
// then tears the server down. a long-running `serve` invocation holds the
// package .build lock for its whole run, so a gate can never be a separate
// invocation pointed at another plugin's server — it must host its own.
//
//   swift package --disable-sandbox plugin --allow-network-connections local:9123 smoke [--port 9123]

@main
struct WebUISmokePlugin: CommandPlugin {
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

        var pass = 0
        var fail = 0
        func ok(_ message: String) { pass += 1; print("  PASS \(message)") }
        func bad(_ message: String) { fail += 1; print("  FAIL \(message)") }

        print("=== WebUI smoke check ===")
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
        ok("server ready on :\(port)")

        let cssSource = context.package.directoryURL
            .appendingPathComponent("designer/assets/design-system.css")
        let jsSource = context.package.directoryURL
            .appendingPathComponent("designer/assets/webui-runtime.js")

        if let servedCss = await GET(session, "\(base)/__assets/css"),
           let sourceCss = try? Data(contentsOf: cssSource),
           let cssText = String(data: servedCss, encoding: .utf8),
           servedCss.count <= sourceCss.count, !cssText.isEmpty, !cssText.contains("/*") {
            ok("css served is the minified sheet (comment-free, \(servedCss.count) bytes ≤ source \(sourceCss.count))")
        } else {
            bad("css served is not the minified design sheet")
        }

        if let servedJs = await GET(session, "\(base)/__assets/js"),
           let sourceJs = try? Data(contentsOf: jsSource),
           servedJs == sourceJs {
            ok("js served bytes == source (\(sourceJs.count) bytes)")
        } else {
            bad("js served bytes DIFFER from source")
        }

        guard let pageData = await GET(session, "\(base)/"),
              let html = String(data: pageData, encoding: .utf8) else {
            Diagnostics.error("page not reachable at \(base)/")
            return
        }

        let signatures: [(sig: String, label: String)] = [
            ("color-mix(in srgb, var(--color-neutral-200) 45%, var(--color-bg))", "progress groove color"),
            ("box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.12)", "progress groove inset shadow"),
            ("flex-direction: row", "progress left-anchor (row)"),
            ("grid-area: 1 / 1", "zstack overlap"),
            ("align-self: stretch", "block-component stretch"),
            ("margin-top: 1.75rem", "progress label lane"),
            ("role=\"progressbar\"", "progressbars rendered"),
            ("counter-value", "interactive counter rendered"),
            ("echo-out__text", "live input echo rendered"),
            ("button button--primary", "primary button rendered"),
            ("smoke-chart-anchor", "interactive chart card rendered"),
            ("chart__svg", "chart svg rendered"),
        ]
        for entry in signatures {
            if html.contains(entry.sig) {
                ok("fix present: \(entry.label)")
            } else {
                bad("fix MISSING: \(entry.label)")
            }
        }

        if html.range(of: #"<script[^>]+src="http|<link[^>]+href="http"#, options: .regularExpression) == nil {
            ok("no external http asset references")
        } else {
            bad("page references external http assets (not self-contained)")
        }

        let interactiveCount = html.components(separatedBy: "data-component-id=\"").count - 1
        // 3 counter + 2 progress + 1 echo + 12 table controls (3 sort + select-all
        // + 4 select + 4 expand) + 6 chart bars = 24 routed components.
        if interactiveCount == 24 {
            ok("served page exposes 24 interactive components, incl. per-control table routing (handler wiring intact)")
        } else {
            bad("expected 24 data-component-id attributes, found \(interactiveCount)")
        }

        if html.contains("http-equiv=\"Content-Security-Policy\"") {
            ok("CSP meta present")
        } else {
            bad("CSP meta missing")
        }

        // client-mode probe (p1): the wasm artifact, the chamber, and the
        // client-demo page must all be served with the client-mode markers.
        // the artifact is built by a separate wasm-sdk invocation before this
        // gate; absence surfaces as FAIL here (gates build it first).
        if let wasm = await GET(session, base + "/__assets/app.wasm"),
           wasm.count > 8,
           Array(wasm.prefix(4)) == [0x00, 0x61, 0x73, 0x6D],
           wasm[4] == 0x01 {
            ok("client wasm served with valid magic/version (\(wasm.count) bytes)")
        } else {
            bad("client wasm missing or malformed (run the wasm release build first)")
        }

        if let clientJs = await GET(session, base + "/__assets/webui-client.js"),
           let clientText = String(data: clientJs, encoding: .utf8),
           clientText.contains("WebUIClient"), !clientText.contains("/*") {
            ok("chamber served, comment-free")
        } else {
            bad("chamber not served or carries comments")
        }

        if let demo = await GET(session, base + "/__assets/client-demo"),
           let demoText = String(data: demo, encoding: .utf8),
           demoText.contains("'wasm-unsafe-eval'"),
           demoText.contains("id=\"app\""),
           demoText.contains("webui-client.js"),
           !demoText.contains("WebUIRuntime.init") {
            ok("client-demo page carries client csp + external scripts")
        } else {
            bad("client-demo page missing client-mode markers")
        }

        print("")
        print("=== summary: \(pass) passed, \(fail) failed ===")
        if fail == 0 {
            print("SMOKE PASS")
        } else {
            Diagnostics.error("smoke gate failed")
        }
    }

    private func GETBody(_ session: URLSession, _ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await session.data(from: url).0
    }

    private func GET(_ session: URLSession, _ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await session.data(from: url).0
    }
}
