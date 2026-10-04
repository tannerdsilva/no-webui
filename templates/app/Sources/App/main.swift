import CryptoKit
import Foundation
import Synchronization
import WebUI
import WebUIDesignSystem
import WebUIServer

// MARK: - the acceptance page (CONTINUUM_DX appendix A)
//
// the minimal consumer page of the dx-accept template app:
//   - one PRE-EMITTED WebUIIsland("feed") region (the engine mounts regions
//     already in the DOM; a lone @HotView renders nothing by itself), with the
//     CLICK subscription the engine's frozen t2.2 contract requires for island
//     event delivery (see feedRegionHTML) — the region itself is the D-owned
//     view's markup, never hand-retyped;
//   - the DX-11 dogfood surface: a WebUITable with a typed onSort handler that
//     responds to a click with OPERATIONS (attr/text fragments), never a
//     whole-region replace of the table root;
//   - NO capability allowlist (a narrowing webui-config.capabilities list
//     would leave regions unmapped — the engine gates on it).

/// the pre-emitted feed region: `WebUIIsland("feed")` plus the click
/// subscription. the view emits `id/data-webui-island/data-webui-args`
/// (pinned serialization contract, D-owned); the acceptance needs clicks, so
/// the page rides the click descriptor beside the view's markup — same region,
/// subscription attached.
func feedRegionHTML() -> String {
    var html = WebUIIsland("feed").render()
    let marker = " data-webui-args="
    if let range = html.range(of: marker) {
        html.replaceSubrange(range, with: " data-webui-island-events='[\"click\"]'" + marker)
    }
    return html
}

func renderPage(router: EventRouter) -> String {
    let ctx = RenderContext(router: router)
    let body = RenderContext.$current.withValue(ctx) {
        Main(class: "app") {
            Heading("dx-accept — the zero-manual-steps app", level: .h1)
            Paragraph("the island region below is pre-emitted (WebUIIsland(\"feed\")); a @HotView struct + a plain `swift build` + `swift run` make it live.")
            Div(class: "island-card") {
                Raw(feedRegionHTML())
            }
            Heading("dogfood: WebUITable with a typed onSort handler (ops-only response)", level: .h2)
            Div(class: "dog") {
                WebUITable(
                    headers: ["name", "count"],
                    rows: [[Text("apple"), Text("3")], [Text("banana"), Text("1")], [Text("cherry"), Text("2")]],
                    wrapped: true,
                    id: "dog-table",
                    sortableColumns: [0, 1]
                )
                .onSort { _, column in
                    // the whole DX-11 claim: the click answers with ops, not
                    // a whole-region replace of the table root.
                    [
                        FragmentUpdate.attr(id: "dog-table-sort-\(column)", name: "aria-sort", value: "ascending"),
                        FragmentUpdate.text(id: "dog-status", value: "sorted column \(column)"),
                    ]
                }
                Div(id: "dog-status", class: "dog__status") {
                    Text("not sorted")
                }
            }
        }.render()
    }
    return WebUIDocument(title: "dx-accept", body: body, rawStyles: [
        ".app { max-width: 720px; margin: 0 auto; padding: var(--space-8); font-family: ui-monospace, monospace; }",
        ".island-card, .dog { margin: var(--space-4) 0; padding: var(--space-4); border: 1px solid var(--color-border, #ddd); border-radius: 6px; }",
        ".dog__status { margin-top: var(--space-2); color: var(--color-text-muted); }",
    ]).render()
}

// MARK: - the accepting server

@main
struct App {
    static func main() async throws {
        let port = intFlag(named: "--port", default: 9190)
        let router = EventRouter()

        // the island artifact the WebUIAutobuildPlugin cross-built during the
        // plain `swift build` lives in the sandbox-writable plugin work dir
        // (never on a home-dir project's .build/out — measured, DX-5).
        guard let feedBytes = locateFeedArtifact() else {
            FileHandle.standardError.write(Data("dx-accept: [error] feed.wasm not found under .build/plugins/outputs — the WebUIAutobuildPlugin did not cross-build the feed island\n".utf8))
            Foundation.exit(1)
        }
        let stamp = sha256Hex(feedBytes).prefix(12)
        let contentAddressed = "/__assets/webui-feed-\(stamp).wasm"
        // the v2 engine manifest: attributeAllowlist + islands[] (DX-6e) — the
        // engine consumes the content-addressed URL for "feed" and keeps the
        // convention URL as fallback (both URLs are served below).
        let manifest = "{\"version\":2,\"attributeAllowlist\":[\"class\",\"aria-*\",\"data-*\"],\"islands\":[{\"name\":\"feed\",\"url\":\"\(contentAddressed)\"}]}"

        let server = WebUIServer(
            render: { renderPage(router: router) },
            router: router,
            config: WebUIServerConfig(
                port: port,
                assets: [
                    WebUIServerAsset.text("/ui/continuum-manifest.json", manifest, contentType: "application/json", cacheSeconds: 3600),
                    WebUIServerAsset.bytes("/__assets/webui-feed.wasm", feedBytes, contentType: "application/wasm", cacheSeconds: 3600),
                    WebUIServerAsset.bytes(contentAddressed, feedBytes, contentType: "application/wasm", cacheSeconds: 31536000, immutable: true),
                ]
            )
        )
        print("dx-accept listening on http://127.0.0.1:\(port)")
        try await server.start()
    }

    // MARK: artifact location

    /// find the cross-built island artifact: `.build/plugins/outputs/<pkg>/<target>/destination/WebUIAutobuildPlugin/feed.wasm`
    /// scanned relative to the current working directory (the package root when `swift build`/`swift run`).
    static func locateFeedArtifact() -> [UInt8]? {
        let root = FileManager.default.currentDirectoryPath
        let outputs = root + "/.build/plugins/outputs/"
        guard let top = try? FileManager.default.contentsOfDirectory(atPath: outputs) else { return nil }
        for packageDir in top {
            let targetsURL = URL(fileURLWithPath: outputs + packageDir)
            guard let targets = try? FileManager.default.contentsOfDirectory(atPath: targetsURL.path) else { continue }
            for target in targets {
                let p = targetsURL.appendingPathComponent(target).appendingPathComponent("destination/WebUIAutobuildPlugin/feed.wasm").path
                if let bytes = try? Data(contentsOf: URL(fileURLWithPath: p)) { return Array(bytes) }
            }
        }
        return nil
    }

    static func sha256Hex(_ bytes: [UInt8]) -> String {
        let digest = SHA256.hash(data: bytes)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func intFlag(named name: String, default fallback: Int) -> Int {
        if let i = CommandLine.arguments.firstIndex(of: name),
           i + 1 < CommandLine.arguments.count,
           let v = Int(CommandLine.arguments[i + 1]), v > 0 {
            return v
        }
        return fallback
    }
}
