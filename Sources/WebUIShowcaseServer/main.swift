import Foundation
import Logging
import WebUI
import WebUIDesignSystem
import WebUIServer
import WebUIShowcaseContent

// MARK: - Live showcase generation (re-rendered per request, never a frozen file)

/// Build the full showcase document from Swift views right now. Unlike the
/// static `designer/previews/showcase.html` artifact, every request reflects
/// the current source: change a component or the css and this server serves
/// it immediately. The runtime is enabled (and served a working `/ws` below),
/// so the client boots cleanly with no failed-handshake error.
func renderShowcasePage(state: ShowcaseState, checkClasses: Bool = true) -> String {
    HTMLClassValidator.onUndefined = { className in
        // the one page-scoped structural wrapper (documented in the class pin
        // test) — everything else should be in the sheet.
        if className == "demo-section" { return }
        Logger(label: "webui.showcase-server").warning(
            "undefined design-system class on showcase: \(className)"
        )
    }
    let doc = WebUIDocument(
        title: "WebUI Showcase",
        body: ShowcasePage(state: state).render(),
        includeRuntime: true,
        checkClasses: checkClasses
    )
    return doc.render()
}

// MARK: - render profiling

/// instrumented render profile. the page render is the server's entire cost on
/// a small box, so this attributes it: the page itself (with and without class
/// validation), a synthetic N-node tree for the *generic* per-node overhead,
/// and the three micro-paths the render leans on (id minting, escaping, string
/// growth).
///
/// every render here is wrapped in a `RenderContext`, exactly as the server
/// does. without it each handler registration logs a warning, and those log
/// writes land inside the timed region — the first version of this bench did
/// that and inflated every number.
func renderBench(n: Int) {
    let state = ShowcaseState()
    let router = EventRouter()
    let ctx = RenderContext(router: router)

    func report(_ label: String, iterations: Int, _ body: () -> Void) {
        body()  // warm
        let t0 = Date().timeIntervalSince1970
        for _ in 0..<iterations { body() }
        let ms = (Date().timeIntervalSince1970 - t0) * 1000 / Double(iterations)
        print(label.padding(toLength: 38, withPad: " ", startingAt: 0) + String(format: "%9.3f ms", ms))
    }

    print("=== page render (server-shaped: RenderContext present) ===")
    for check in [true, false] {
        report("page, class-check \(check ? "on " : "off")", iterations: n) {
            _ = RenderContext.$current.withValue(ctx) {
                renderShowcasePage(state: state, checkClasses: check)
            }
        }
    }

    print("=== synthetic tree: generic per-node cost ===")
    let nodes = 2000
    let tree = VStack(spacing: 0) {
        ForEach(0..<nodes) { i in
            Div { Text("row \(i)") }
        }
    }
    report("synthetic \(nodes) div+text nodes", iterations: max(5, n / 4)) {
        _ = RenderContext.$current.withValue(ctx) { tree.render() }
    }

    print("=== micro paths the render leans on ===")
    report("nextComponentID (mutex + string alloc)", iterations: 200_000) {
        _ = router.nextComponentID()
    }
    // uppercase on purpose: the orphan ratchet scans every token in Sources/,
    // so a lowercase sample containing a real class name would mark that class
    // reachable and fail the baseline-tightness test.
    let clean = "PLAIN_PROSE 12345 MIXED_CASE_TOKENS"
    report("htmlEscape (nothing to escape)", iterations: 200_000) {
        _ = htmlEscape(clean)
    }
    let dirty = "<A HREF=\"X\">TOM & JERRY'S</A>"
    report("htmlEscape (escapables present)", iterations: 200_000) {
        _ = htmlEscape(dirty)
    }
    let pieces = (0..<2850).map { "chunk\($0)_abcdefghij" }
    report("string growth: 2850 plain appends", iterations: 200) {
        var s = ""
        for p in pieces { s += p }
        _ = s.utf8.count
    }
    report("string growth: same + reserveCapacity", iterations: 200) {
        var s = ""
        s.reserveCapacity(60_000)
        for p in pieces { s += p }
        _ = s.utf8.count
    }

    // A/B on identical input: the retired Swift-Regex scanner against the
    // shipped byte scanner, each doing the same work (tokenize the page, then
    // subtract the sheet's classes). the first bench reported the difference
    // between these two as ~42 ms, but that comparison was polluted by log
    // writes inside the timed region — this one is not.
    let html = RenderContext.$current.withValue(ctx) {
        renderShowcasePage(state: state, checkClasses: false)
    }
    let defined = HTMLClassValidator.definedClasses()
    let retired = /class\s*=\s*["']([^"']*)["']/
    report("validation, RETIRED regex form", iterations: max(3, n / 4)) {
        var tokens = Set<String>()
        for match in html.matches(of: retired) {
            for token in match.output.1.split(whereSeparator: \.isWhitespace) {
                tokens.insert(String(token))
            }
        }
        _ = defined.subtracting(tokens).count
    }
    report("validation, SHIPPED byte form", iterations: max(3, n / 4)) {
        _ = HTMLClassValidator.undefinedClasses(in: html).count
    }
    print("   (page under test: \(html.utf8.count) bytes, sheet: \(defined.count) classes)")
}

func intFlag(named name: String, default fallback: Int) -> Int {
    if let i = CommandLine.arguments.firstIndex(of: name),
       i + 1 < CommandLine.arguments.count,
       let v = Int(CommandLine.arguments[i + 1]), v > 0 {
        return v
    }
    return fallback
}

// MARK: - Server (WebUIServer: page + assets + /ws, content-addressed css)

@main
struct WebUIShowcaseServer {
    static func main() async throws {
        let port = intFlag(named: "--port", default: 9092)
        if let i = CommandLine.arguments.firstIndex(of: "--render-bench"),
           i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]) {
            renderBench(n: n)
            return
        }
        // the showcase is a dev page: class validation is on by default so a
        // typo'd class is loud, and can be switched off to measure/serve the
        // page without the validator in the request path.
        let checkClasses = !CommandLine.arguments.contains("--no-class-check")
        // one state box + one router for the whole process: the server injects
        // its router as the render context (so the page's handlers register
        // here) and every request re-renders from the same live state.
        let state = ShowcaseState()
        let router = EventRouter()
        let server = WebUIServer(
            render: { renderShowcasePage(state: state, checkClasses: checkClasses) },
            router: router,
            config: WebUIServerConfig(host: "0.0.0.0", port: port)
        )
        try await server.start()
    }
}
