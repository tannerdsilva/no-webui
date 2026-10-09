import WebUI
import WebUIDesignSystem
import WebUIServer

// the wave-4 event deck (W4.1): one control per deck event, each carrying its
// typed modifier and a handler that decodes the typed payload and renders it
// back into the family's log span. the page is what
// `designer/event-deck-probe.mjs` drives: the gate reads the stable control
// ids out of the served markup, drives each event in a real browser, asserts
// the outbound frame the engine sent (event name + typed payload), and asserts
// the update frame the server answered with (the decoded payload rendered
// back). a control declares exactly one event — the engine's narrow-by-default
// contract — so driving an un-declared event on a control must send nothing.

// MARK: - payload echo helpers
//
// every handler renders its decoded typed payload back into the family log, so
// the inbound update frame a gate asserts on is proof the server decoded the
// exact payload the wire carried.

func fmt(_ n: Double) -> String {
    n == n.rounded() ? String(Int(n)) : String(n)
}

func pointerMessage(_ name: String, _ p: PointerPayload?) -> String {
    guard let p else { return "\(name) no-pointer-payload" }
    return "\(name) x=\(fmt(p.x)) y=\(fmt(p.y)) button=\(p.button) buttons=\(p.buttons)"
}

func touchMessage(_ name: String, _ t: TouchPayload?) -> String {
    guard let t else { return "\(name) no-touch-payload" }
    return "\(name) x=\(fmt(t.x)) y=\(fmt(t.y)) id=\(t.identifier) touches=\(t.touches)"
}

func dragMessage(_ name: String, _ d: DragPayload) -> String {
    var parts = [name]
    for (key, value) in d.data.sorted(by: { $0.key < $1.key }) {
        parts.append("\(key)=\(value)")
    }
    for file in d.files {
        parts.append("file=\(file.name) size=\(file.size) type=\(file.type)")
    }
    return parts.joined(separator: " ")
}

func pasteMessage(_ name: String, _ p: PastePayload) -> String {
    "\(name) text=\(p.text ?? "<nil>") html=\(p.html ?? "<nil>")"
}

func mediaMessage(_ name: String, _ m: MediaPayload) -> String {
    let code = m.code.map { " code=\($0)" } ?? ""
    return "\(name) t=\(fmt(m.currentTime)) d=\(fmt(m.duration)) rs=\(m.readyState)\(code)"
}

func logMarkup(_ spanID: String, _ message: String) -> String {
    "<span id=\"\(spanID)\">\(htmlEscape(message))</span>"
}

func logUpdate(_ spanID: String, _ message: String) -> [FragmentUpdate] {
    [FragmentUpdate(id: spanID, html: logMarkup(spanID, message))]
}

func deckLog(_ spanID: String, _ leading: String) -> String {
    "<pre class=\"deck-log\">\(logMarkup(spanID, leading))</pre>"
}

// MARK: - the deck document

struct DeckDocument: View {
    /// the per-render token the server minted, echoed into the page's
    /// `RuntimeConfig` so the websocket frames bind back to this render's
    /// session (AGENTS.md security invariant 11).
    let renderToken: String

    init(renderToken: String = "") {
        self.renderToken = renderToken
    }

    func render(into buffer: inout HTMLBuffer) {
        let document = WebUIDocument(
            title: "Event deck · wave 4",
            body: deckBody(),
            runtimeConfig: renderToken.isEmpty ? nil : RuntimeConfig(renderToken: renderToken),
            // the deck is a probe fixture: `designer/event-deck-probe.mjs`
            // drives its media controls with data:-uri wavs, which the default
            // `default-src 'self'` policy blocks with MEDIA_ERR_SRC_NOT_SUPPORTED.
            // this one page relaxes media-src so the media pipeline is real;
            // framework defaults are untouched.
            contentSecurityPolicyExtras: "media-src 'self' data: blob:;",
            rawStyles: Self.deckStyles
        )
        buffer.append(document.renderThroughBuffer())
    }

    static let deckStyles: [String] = [
        ".deck { max-width: 1100px; margin: 0 auto; padding: var(--space-8); display: flex; flex-direction: column; gap: var(--space-5); }",
        ".deck-intro p { color: var(--color-text-muted); margin: 0; }",
        ".deck-row { display: flex; flex-wrap: wrap; gap: var(--space-2); align-items: center; }",
        ".deck-ctrl { display: inline-block; padding: 6px 12px; border: 1px solid var(--color-border-subtle, #d1d5db); border-radius: 999px; background: var(--color-surface-muted, #f3f4f6); font-size: 13px; cursor: default; user-select: none; }",
        ".deck-log { margin: var(--space-3) 0 0; padding: var(--space-3); background: var(--color-surface-muted, #f3f4f6); border-radius: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; min-height: 2.2em; white-space: pre-wrap; word-break: break-all; }",
        ".deck-scroll-box { width: 360px; height: 90px; overflow: auto; border: 1px solid var(--color-border-subtle, #d1d5db); border-radius: 8px; padding: 8px; }",
        // the inner content is a Text span, not a div — the selector must match
        // what the renderer actually emits or the box never scrolls.
        ".deck-scroll-box span { height: 280px; display: block; white-space: nowrap; }",
        ".deck-anim { animation: deck-pulse 0.35s ease; }",
        "@keyframes deck-pulse { from { opacity: 0.35; } to { opacity: 1; } }",
        ".deck-tran { width: 160px; height: 44px; transition: width 0.3s ease; }",
        ".deck-audio { width: 320px; }",
    ]
}

// MARK: - the deck body

func deckBody() -> String {
    Div(class: "deck") {
        Div(class: "deck-intro") {
            Heading("Event deck", level: .h1)
            Paragraph("one control per wave-4 event, each declaring exactly the one event its typed modifier names — the engine's narrow-by-default contract. drive a control and the outbound frame round-trips; the server decodes the typed payload and renders it into the family log.")
        }

        // ── pointer ──
        WebUICard(elevation: .outlined) {
            Heading("pointer", level: .h2)
            Div(class: "deck-row") {
                Text("down").classes("deck-ctrl").id("deck-pd").onPointerDown { e in
                    logUpdate("pointer-log", pointerMessage("pointerdown", e.pointer()))
                }
                Text("move").classes("deck-ctrl").id("deck-pm").onPointerMove { e in
                    logUpdate("pointer-log", pointerMessage("pointermove", e.pointer()))
                }
                Text("up").classes("deck-ctrl").id("deck-pu").onPointerUp { e in
                    logUpdate("pointer-log", pointerMessage("pointerup", e.pointer()))
                }
                Text("cancel").classes("deck-ctrl").id("deck-pc").onPointerCancel { e in
                    logUpdate("pointer-log", pointerMessage("pointercancel", e.pointer()))
                }
                Text("enter").classes("deck-ctrl").id("deck-pe").onPointerEnter { e in
                    logUpdate("pointer-log", pointerMessage("pointerenter", e.pointer()))
                }
                Text("leave").classes("deck-ctrl").id("deck-pl").onPointerLeave { e in
                    logUpdate("pointer-log", pointerMessage("pointerleave", e.pointer()))
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("pointer-log", "pointer log")))
        }

        // ── touch ──
        WebUICard(elevation: .outlined) {
            Heading("touch", level: .h2)
            Div(class: "deck-row") {
                Text("start").classes("deck-ctrl").id("deck-ts").onTouchStart { e in
                    logUpdate("touch-log", touchMessage("touchstart", e.touch()))
                }
                Text("move").classes("deck-ctrl").id("deck-tm").onTouchMove { e in
                    logUpdate("touch-log", touchMessage("touchmove", e.touch()))
                }
                Text("end").classes("deck-ctrl").id("deck-te").onTouchEnd { e in
                    logUpdate("touch-log", touchMessage("touchend", e.touch()))
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("touch-log", "touch log")))
        }

        // ── drag & drop ──
        WebUICard(elevation: .outlined) {
            Heading("drag & drop", level: .h2)
            Div(class: "deck-row") {
                Text("start").classes("deck-ctrl").id("deck-ds").onDragStart { e in
                    logUpdate("drag-log", dragMessage("dragstart", e.drag()))
                }
                Text("drag").classes("deck-ctrl").id("deck-dr").onDrag { e in
                    logUpdate("drag-log", dragMessage("drag", e.drag()))
                }
                Text("end").classes("deck-ctrl").id("deck-de").onDragEnd { e in
                    logUpdate("drag-log", dragMessage("dragend", e.drag()))
                }
                Text("enter").classes("deck-ctrl").id("deck-denter").onDragEnter { e in
                    logUpdate("drag-log", dragMessage("dragenter", e.drag()))
                }
                Text("over").classes("deck-ctrl").id("deck-dover").onDragOver { e in
                    logUpdate("drag-log", dragMessage("dragover", e.drag()))
                }
                Text("leave").classes("deck-ctrl").id("deck-dleave").onDragLeave { e in
                    logUpdate("drag-log", dragMessage("dragleave", e.drag()))
                }
                Text("drop").classes("deck-ctrl").id("deck-drop").onDrop { e in
                    logUpdate("drag-log", dragMessage("drop", e.drag()))
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("drag-log", "drag log")))
        }

        // ── clipboard ──
        WebUICard(elevation: .outlined) {
            Heading("clipboard", level: .h2)
            Div(class: "deck-row") {
                Text("copy").classes("deck-ctrl").id("deck-copy").onCopy { e in
                    logUpdate("clipboard-log", pasteMessage("copy", e.paste()))
                }
                Text("cut").classes("deck-ctrl").id("deck-cut").onCut { e in
                    logUpdate("clipboard-log", pasteMessage("cut", e.paste()))
                }
                Text("paste").classes("deck-ctrl").id("deck-paste").onPaste { e in
                    logUpdate("clipboard-log", pasteMessage("paste", e.paste()))
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("clipboard-log", "clipboard log")))
        }

        // ── wheel & scroll ──
        WebUICard(elevation: .outlined) {
            Heading("wheel & scroll", level: .h2)
            Div(class: "deck-row") {
                Text("wheel").classes("deck-ctrl").id("deck-wheel").onWheel { e in
                    logUpdate("scroll-log", "wheel dx=\(fmt(e.wheel().deltaX)) dy=\(fmt(e.wheel().deltaY))")
                }
                Div(class: "deck-scroll-box") {
                    Text("scroll me — the box reports its scrollTop/scrollLeft.").id("deck-scroll-inner")
                }.id("deck-scroll").onScroll { e in
                    logUpdate("scroll-log", "scroll top=\(fmt(e.scroll().scrollTop)) left=\(fmt(e.scroll().scrollLeft))")
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("scroll-log", "scroll log")))
        }

        // ── misc ──
        WebUICard(elevation: .outlined) {
            Heading("misc", level: .h2)
            Div(class: "deck-row") {
                Text("dblclick").classes("deck-ctrl").id("deck-dbl").onDoubleClick { e in
                    logUpdate("misc-log", pointerMessage("dblclick", e.pointer()))
                }
                Text("context menu").classes("deck-ctrl").id("deck-ctx").onContextMenu { e in
                    logUpdate("misc-log", pointerMessage("contextmenu", e.pointer()))
                }
                Text("animation").classes("deck-ctrl deck-anim").id("deck-anim").onAnimationEnd { e in
                    logUpdate("misc-log", "animationend name=\(e.animation().animationName)")
                }
                Text("transition").classes("deck-ctrl deck-tran").id("deck-tran").onTransitionEnd { e in
                    logUpdate("misc-log", "transitionend prop=\(e.transition().propertyName) t=\(fmt(e.transition().elapsedTime))")
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("misc-log", "misc log")))
        }

        // ── media ──
        WebUICard(elevation: .outlined) {
            Heading("media", level: .h2)
            Div(class: "deck-row") {
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-play\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onPlay { e in
                    logUpdate("media-log", mediaMessage("play", e.media()))
                }
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-pause\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onPause { e in
                    logUpdate("media-log", mediaMessage("pause", e.media()))
                }
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-ended\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onEnded { e in
                    logUpdate("media-log", mediaMessage("ended", e.media()))
                }
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-time\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onTimeUpdate { e in
                    logUpdate("media-log", mediaMessage("timeupdate", e.media()))
                }
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-meta\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onLoadedMetadata { e in
                    logUpdate("media-log", mediaMessage("loadedmetadata", e.media()))
                }
                Raw(UnsafeMarkup.trusted("<audio id=\"deck-m-err\" class=\"deck-audio\" preload=\"metadata\" muted playsinline></audio>")).onError { e in
                    logUpdate("media-log", mediaMessage("error", e.media()))
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("media-log", "media log")))
        }

        // ── narrow by default: a click-only control ──
        WebUICard(elevation: .outlined) {
            Heading("narrow by default", level: .h2)
            Paragraph("this control declares click only — hover/press noise must never reach it.")
            Div(class: "deck-row") {
                Text("click only").classes("deck-ctrl").id("deck-click").onClick { e in
                    logUpdate("click-log", "click target=\(e.targetID ?? "<none>")")
                }
            }
            Raw(UnsafeMarkup.trusted(deckLog("click-log", "click log")))
        }
    }.renderThroughBuffer()
}

// MARK: - server entry

@main
struct WebUIEventDeck {
    static func main() async throws {
        let router = Router {
            Route.page("/") { request in
                DeckDocument(renderToken: request.renderToken.value)
            }
        }
        let server = WebUIServer(
            router: router,
            config: WebUIServerConfig(port: intFlag(named: "--port", default: 39000))
        )
        try await server.start()
    }

    /// parse a positive-integer flag (`--name N`) with a fallback.
    static func intFlag(named name: String, default fallback: Int) -> Int {
        if let i = CommandLine.arguments.firstIndex(of: name),
           i + 1 < CommandLine.arguments.count,
           let v = Int(CommandLine.arguments[i + 1]), v > 0 {
            return v
        }
        return fallback
    }
}
