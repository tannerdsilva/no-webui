import Synchronization
import Testing
import WebUI
import WebUIDesignSystem

// the wave-4 event deck (W4.1)
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W4.1).
//
// every deck event carries a typed payload and arrives through a typed
// modifier. per family, these tests assert both halves of the contract:
//   1. the rendered control's wire frame names the right event
//      (`data-event="pointermove"`, …) — the attribute the runtime dispatches
//      on, and therefore the event name the server's handler is keyed by.
//   2. an `EventData` carrying the engine's wire keys decodes to the typed
//      payload struct (`PointerPayload`, `TouchPayload`, `DragPayload`, …) —
//      the magic-string retirement the plan calls for.
//   3. the payload a handler receives is the struct the wire carried — the
//      round trip through `EventRouter`, the same path the deck fixture's
//      handlers (and the browser probe) exercise.

@Suite("wave-4 event deck (W4.1)")
struct EventDeckTests {

    /// render `v` inside a fresh routing context and return the emitted html,
    /// exactly the shape `InteractivityIdiomTests.sugar` produces: the
    /// modifier needs a `RenderContext` to register and emit, and a test that
    /// forgets the context sees an inert control and fails its own probe.
    private func rendered(_ v: ModifiedView<Text, EventHandlerModifier>) -> String {
        RenderContext.$current.withValue(RenderContext(router: EventRouter())) {
            v.markup.html
        }
    }

    /// an `EventData` whose `data` is the wire keys the engine emits
    /// (`extractEventData` in `designer/assets/webui-engine.js`).
    private func frame(_ name: String, _ data: [String: JSONValue]) -> EventData {
        EventData(component: ComponentID("c0"), event: name, data: data)
    }

    /// the wire-frame assertion for one control: the emitted attributes carry
    /// the right `data-event` value and a `data-component-id` for the router.
    private func assertWireName(_ html: String, _ name: String) {
        #expect(html.contains("data-event=\"\(name)\""), "\(name): \(html)")
        #expect(html.contains("data-component-id="), "\(name): \(html)")
    }

    // MARK: pointer

    @Test("pointer: wire frames name each event and the payload decodes")
    func pointerFamily() {
        assertWireName(rendered(Text("x").onPointerDown { _ in [] }), "pointerdown")
        assertWireName(rendered(Text("x").onPointerMove { _ in [] }), "pointermove")
        assertWireName(rendered(Text("x").onPointerUp { _ in [] }), "pointerup")
        assertWireName(rendered(Text("x").onPointerCancel { _ in [] }), "pointercancel")
        assertWireName(rendered(Text("x").onPointerEnter { _ in [] }), "pointerenter")
        assertWireName(rendered(Text("x").onPointerLeave { _ in [] }), "pointerleave")

        let e = frame("pointerdown", [
            "x": .number(10.5), "y": .number(20), "button": .number(2), "buttons": .number(1),
        ])
        #expect(e.pointer() == PointerPayload(x: 10.5, y: 20, button: 2, buttons: 1))
        // the accessor needs both coordinates; a half-populated frame is nil,
        // never a half-coerced guess.
        #expect(frame("pointerdown", ["x": .number(3)]).pointer() == nil)
        #expect(frame("pointerdown", [:] ).pointer() == nil)
    }

    // MARK: touch

    @Test("touch: wire frames name each event and the payload decodes")
    func touchFamily() {
        assertWireName(rendered(Text("x").onTouchStart { _ in [] }), "touchstart")
        assertWireName(rendered(Text("x").onTouchMove { _ in [] }), "touchmove")
        assertWireName(rendered(Text("x").onTouchEnd { _ in [] }), "touchend")

        let e = frame("touchstart", [
            "x": .number(10), "y": .number(20), "identifier": .number(7), "touches": .number(1),
        ])
        #expect(e.touch() == TouchPayload(x: 10, y: 20, identifier: 7, touches: 1))
        #expect(frame("touchstart", [:]).touch() == nil)
    }

    // MARK: drag & drop

    @Test("drag & drop: wire frames name each event and the payload decodes")
    func dragFamily() {
        assertWireName(rendered(Text("x").onDragStart { _ in [] }), "dragstart")
        assertWireName(rendered(Text("x").onDrag { _ in [] }), "drag")
        assertWireName(rendered(Text("x").onDragEnd { _ in [] }), "dragend")
        assertWireName(rendered(Text("x").onDragEnter { _ in [] }), "dragenter")
        assertWireName(rendered(Text("x").onDragOver { _ in [] }), "dragover")
        assertWireName(rendered(Text("x").onDragLeave { _ in [] }), "dragleave")
        assertWireName(rendered(Text("x").onDrop { _ in [] }), "drop")

        let e = frame("drop", [
            "data": .object(["text/plain": .string("hi")]),
            "files": .array([
                .object(["name": .string("note.txt"), "size": .number(11), "type": .string("text/plain")]),
            ]),
        ])
        #expect(e.drag() == DragPayload(
            data: ["text/plain": "hi"],
            files: [DroppedFile(name: "note.txt", size: 11, type: "text/plain")]
        ))
        // a drop that carried nothing is still a drop — empty, never nil.
        #expect(frame("drop", [:] ).drag() == DragPayload(data: [:], files: []))
    }

    // MARK: clipboard

    @Test("clipboard: wire frames name each event and the payload decodes")
    func clipboardFamily() {
        assertWireName(rendered(Text("x").onCopy { _ in [] }), "copy")
        assertWireName(rendered(Text("x").onCut { _ in [] }), "cut")
        assertWireName(rendered(Text("x").onPaste { _ in [] }), "paste")

        let e = frame("paste", ["text": .string("hello"), "html": .string("<b>hi</b>")])
        #expect(e.paste() == PastePayload(text: "hello", html: "<b>hi</b>"))
        // either half may be absent on the wire (null, or missing entirely).
        #expect(frame("paste", ["text": .null, "html": .null]).paste() == PastePayload(text: nil, html: nil))
        #expect(frame("paste", [:]).paste() == PastePayload(text: nil, html: nil))
    }

    // MARK: wheel & scroll

    @Test("wheel/scroll: wire frames name each event and the payloads decode")
    func wheelScrollFamily() {
        assertWireName(rendered(Text("x").onWheel { _ in [] }), "wheel")
        assertWireName(rendered(Text("x").onScroll { _ in [] }), "scroll")

        #expect(frame("wheel", ["deltaX": .number(12), "deltaY": .number(34)]).wheel() == WheelPayload(deltaX: 12, deltaY: 34))
        #expect(frame("scroll", ["scrollTop": .number(40), "scrollLeft": .number(0)]).scroll() == ScrollPayload(scrollTop: 40, scrollLeft: 0))
        // both families degrade to zero-deltas, never a partial decode.
        #expect(frame("wheel", [:]).wheel() == WheelPayload(deltaX: 0, deltaY: 0))
        #expect(frame("scroll", [:]).scroll() == ScrollPayload(scrollTop: 0, scrollLeft: 0))
    }

    // MARK: misc

    @Test("misc: wire frames name each event and the payloads decode")
    func miscFamily() {
        assertWireName(rendered(Text("x").onDoubleClick { _ in [] }), "dblclick")
        assertWireName(rendered(Text("x").onContextMenu { _ in [] }), "contextmenu")
        assertWireName(rendered(Text("x").onAnimationEnd { _ in [] }), "animationend")
        assertWireName(rendered(Text("x").onTransitionEnd { _ in [] }), "transitionend")

        // dblclick/contextmenu report a pointer position (they share the
        // pointer accessor).
        #expect(frame("dblclick", ["x": .number(1), "y": .number(2)]).pointer() == PointerPayload(x: 1, y: 2, button: 0, buttons: 0))
        #expect(frame("animationend", ["animationName": .string("deck-pulse")]).animation() == AnimationPayload(animationName: "deck-pulse"))
        #expect(frame("transitionend", ["propertyName": .string("width"), "elapsedTime": .number(0.3)]).transition() == TransitionPayload(propertyName: "width", elapsedTime: 0.3))
        #expect(frame("animationend", [:]).animation() == AnimationPayload(animationName: ""))
    }

    // MARK: media

    @Test("media: wire frames name each event and the payload decodes")
    func mediaFamily() {
        assertWireName(rendered(Text("x").onPlay { _ in [] }), "play")
        assertWireName(rendered(Text("x").onPause { _ in [] }), "pause")
        assertWireName(rendered(Text("x").onEnded { _ in [] }), "ended")
        assertWireName(rendered(Text("x").onTimeUpdate { _ in [] }), "timeupdate")
        assertWireName(rendered(Text("x").onLoadedMetadata { _ in [] }), "loadedmetadata")
        assertWireName(rendered(Text("x").onError { _ in [] }), "error")

        let e = frame("timeupdate", [
            "currentTime": .number(0.25), "duration": .number(30), "readyState": .number(4), "code": .null,
        ])
        #expect(e.media() == MediaPayload(currentTime: 0.25, duration: 30, readyState: 4, code: nil))
        // an error carries the media element's error.code.
        #expect(frame("error", ["currentTime": .number(0), "duration": .number(0), "readyState": .number(0), "code": .number(4)]).media() == MediaPayload(currentTime: 0, duration: 0, readyState: 0, code: 4))
        #expect(frame("play", [:]).media() == MediaPayload(currentTime: 0, duration: 0, readyState: 0, code: nil))
    }

    // MARK: the deck round-trips typed payloads through the router

    @Test("the deck's handlers receive the structs the wire carried")
    func handlersReceiveTypedPayloads() async {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let seen = Mutex<[String]>([])

        let html = await RenderContext.$current.withValue(context) {
            VStack {
                Text("p").onPointerMove { e in
                    let p = e.pointer()!
                    seen.withLock { $0.append("pointer \(p.x),\(p.y),\(p.button),\(p.buttons)") }
                    return []
                }
                Text("d").onDrop { e in
                    let d = e.drag()
                    seen.withLock { $0.append("drag \(d.data["text/plain"] ?? "?") \(d.files.count)") }
                    return []
                }
                Text("p2").onPaste { e in
                    let p = e.paste()
                    seen.withLock { $0.append("paste \(p.text ?? "?") \(p.html ?? "?")") }
                    return []
                }
            }.markup.html
        }

        // every control must have registered, and each rendered marker names
        // the component the runtime will dispatch to.
        let ids = html.matches(of: /data-component-id="([^"]+)"/).map { String($0.1) }
        #expect(ids.count == 3, "expected three deck controls, got \(ids): \(html)")

        _ = await router.dispatch(
            EventData(component: ComponentID(ids[0]), event: "pointermove",
                      data: ["x": .number(1), "y": .number(2), "button": .number(0), "buttons": .number(1)])
        )
        _ = await router.dispatch(
            EventData(component: ComponentID(ids[1]), event: "drop",
                      data: ["data": .object(["text/plain": .string("payload")]), "files": .array([])])
        )
        _ = await router.dispatch(
            EventData(component: ComponentID(ids[2]), event: "paste",
                      data: ["text": .string("hello"), "html": .string("<b>hi</b>")])
        )

        #expect(seen.withLock { $0 } == [
            "pointer 1.0,2.0,0,1",
            "drag payload 0",
            "paste hello <b>hi</b>",
        ])
    }
}
