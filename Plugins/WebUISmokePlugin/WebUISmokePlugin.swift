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

        // identity nonce: the gate proves the responding server is its own
        // child — a stale/foreign process that grabbed the port (or a from
        // an earlier run) must fail the readiness probe, not pass it.
        let nonce = UUID().uuidString

        let server = try context.tool(named: "WebUISmokeTest")
        let process = Process()
        process.executableURL = server.url
        var env = ProcessInfo.processInfo.environment
        env["WEBUI_SMOKE_NONCE"] = nonce
        process.environment = env
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
            if let (body, headers) = await GETWithHeaders(session, "\(base)/"),
               !body.isEmpty,
               headerValue(headers, "X-WebUI-Smoke-Nonce") == nonce {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard ready else {
            Diagnostics.error("server did not become ready on :\(port) with the gate's own identity (stale server holds the port, or --disable-sandbox was forgotten) — kill any WebUISmokeTest and re-run")
            return
        }
        ok("server ready on :\(port) (identity verified)")

        let cssSource = context.package.directoryURL
            .appendingPathComponent("designer/assets/design-system.css")

        if let servedCss = await GET(session, "\(base)/__assets/css"),
           let sourceCss = try? Data(contentsOf: cssSource),
           let cssText = String(data: servedCss, encoding: .utf8),
           servedCss.count <= sourceCss.count, !cssText.isEmpty, !cssText.contains("/*") {
            ok("css served is the minified sheet (comment-free, \(servedCss.count) bytes ≤ source \(sourceCss.count))")
        } else {
            bad("css served is not the minified design sheet")
        }


        let engineSource = context.package.directoryURL
            .appendingPathComponent("designer/assets/webui-engine.js")
        if let servedEngine = await GET(session, "\(base)/ui/webui-engine.js"),
           let sourceEngine = try? Data(contentsOf: engineSource),
           servedEngine == sourceEngine,
           let engineText = String(data: servedEngine, encoding: .utf8),
           !engineText.contains("/*") {
            ok("engine served bytes == source, comment-free (\(sourceEngine.count) bytes)")
        } else {
            bad("engine served bytes DIFFER from source or carry comments")
        }

        // the embed plugin's dogfood, end to end: /ui/probe.css is served from the generated
        // `ProbeAsset` a build produced out of `Assets/webui-assets.json`, and the bytes a
        // client receives must equal that generated payload — payload in, generated type
        // out, wire bytes verified.
        let probeSource = context.package.directoryURL
            .appendingPathComponent("Sources/WebUISmokeTest/Assets/probe.css")
        if let (servedProbe, probeHeaders) = await GETWithHeaders(session, "\(base)/ui/probe.css"),
           let sourceProbe = try? Data(contentsOf: probeSource),
           let generatedPayload = generatedBodyPayload(packageDir: context.package.directoryURL) {
            let probeText = String(data: servedProbe, encoding: .utf8) ?? ""
            if servedProbe == generatedPayload,
               !probeText.contains("/*"), !probeText.contains("dogfood"),
               servedProbe.count < sourceProbe.count,
               headerValue(probeHeaders, "Cache-Control")?.contains("immutable") == true {
                ok("embedded asset served == generated payload (comment-free, \(servedProbe.count) bytes < source \(sourceProbe.count), immutable)")
            } else {
                bad("embedded asset served DIFFERS from the generated payload")
            }
        } else {
            bad("the embed plugin's asset did not serve at /ui/probe.css (or its generated file is missing — run swift build)")
        }

        guard let pageData = await GET(session, "\(base)/"),
              let html = String(data: pageData, encoding: .utf8) else {
            Diagnostics.error("page not reachable at \(base)/")
            return
        }

        let signatures: [(sig: String, label: String)] = [
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

        // the design-sheet rules ride the /__assets/css route now (the page
        // links instead of inlining), so the css-level signatures are checked
        // against the served stylesheet body.
        if let cssData = await GET(session, "\(base)/__assets/css") {
            let cssText = String(decoding: cssData, as: UTF8.self)
            let cssSignatures: [(sig: String, label: String)] = [
                ("color-mix(in srgb, var(--color-neutral-200) 45%, var(--color-bg))", "progress groove color"),
                ("box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.12)", "progress groove inset shadow"),
                ("flex-direction: row", "progress left-anchor (row)"),
                ("grid-area: 1 / 1", "zstack overlap"),
                ("align-self: stretch", "block-component stretch"),
                ("margin-top: 1.75rem", "progress label lane"),
            ]
            for entry in cssSignatures {
                if cssText.contains(entry.sig) {
                    ok("css fix present: \(entry.label)")
                } else {
                    bad("css fix MISSING: \(entry.label)")
                }
            }
        } else {
            bad("stylesheets route did not serve for the css-level signatures")
        }

        if html.range(of: #"<script[^>]+src="http|<link[^>]+href="http"#, options: .regularExpression) == nil {
            ok("no external http asset references")
        } else {
            bad("page references external http assets (not self-contained)")
        }

        let interactiveCount = html.components(separatedBy: "data-component-id=\"").count - 1
        // 3 counter + 2 progress + 1 echo + 12 table controls (3 sort + select-all
        // + 4 select + 4 expand) + 6 chart bars = 24 routed components.
        if interactiveCount == 25 {
            ok("served page exposes 25 interactive components, incl. per-control table routing (handler wiring intact)")
        } else {
            bad("expected 25 data-component-id attributes, found \(interactiveCount)")
        }

        if html.contains("http-equiv=\"Content-Security-Policy\"") {
            ok("CSP meta present")
        } else {
            bad("CSP meta missing")
        }

        print("")
        print("=== summary: \(pass) passed, \(fail) failed ===")
        if fail == 0 {
            print("SMOKE PASS")
        } else {
            Diagnostics.error("smoke gate failed")
        }
    }

    /// the `bodyBase64` payload of the generated embed file, decoded — the bytes the server
    /// is expected to serve, read back from the build product itself. found by walking the
    /// known plugin-output shape rather than guessing the package hash swiftpm owns.
    private func generatedBodyPayload(packageDir: URL) -> Data? {
        let outputs = packageDir.appendingPathComponent(".build/plugins/outputs")
        guard let packages = try? FileManager.default.contentsOfDirectory(
            at: outputs, includingPropertiesForKeys: nil
        ) else { return nil }
        for package in packages {
            let file = package
                .appendingPathComponent("WebUISmokeTest/destination/WebUIEmbedPlugin/EmbeddedAssets.swift")
            guard
                let source = try? String(contentsOf: file, encoding: .utf8),
                let start = source.range(of: "bodyBase64 = \""),
                let end = source.range(of: "\"", range: start.upperBound..<source.endIndex)
            else { continue }
            return Data(base64Encoded: String(source[start.upperBound..<end.lowerBound]))
        }
        return nil
    }

    private func GET(_ session: URLSession, _ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await session.data(from: url).0
    }

    /// case-insensitive header lookup (http header names are case-insensitive).
    private func headerValue(_ headers: [String: String], _ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
            return value
        }
        return nil
    }

    private func GETWithHeaders(_ session: URLSession, _ urlString: String) async -> (Data, [String: String])? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers["\(key)"] = "\(value)"
        }
        return (data, headers)
    }
}
