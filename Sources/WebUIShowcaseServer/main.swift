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
func renderShowcasePage(state: ShowcaseState) -> String {
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
        checkClasses: true
    )
    return doc.render()
}

func intFlag(named name: String, default fallback: Int) -> Int {
    if let i = CommandLine.arguments.firstIndex(of: name),
       i + 1 < CommandLine.arguments.count,
       let v = Int(CommandLine.arguments[i + 1]), v > 0 {
        return v
    }
    return fallback
}

// MARK: - Server (WebUIServer: page + assets + /ws, gzip + content-addressed css)

@main
struct WebUIShowcaseServer {
    static func main() async throws {
        let port = intFlag(named: "--port", default: 9092)
        // one state box + one router for the whole process: the server injects
        // its router as the render context (so the page's handlers register
        // here) and every request re-renders from the same live state.
        let state = ShowcaseState()
        let router = EventRouter()
        let server = WebUIServer(
            render: { renderShowcasePage(state: state) },
            router: router,
            config: WebUIServerConfig(host: "0.0.0.0", port: port)
        )
        try await server.start()
    }
}
