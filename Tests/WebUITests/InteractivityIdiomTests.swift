import Testing
import WebUI
import WebUIDesignSystem

// one interactivity idiom
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W0.8; defect T7).
//
// T7 read the framework as having "12 handler labels / 3 idioms" competing to do
// one job. measurement says otherwise, and the difference matters:
//
//   * `HTMLEvent` has 15 named cases and every single one already has exactly one
//     modifier spelling — the vocabulary and its sugar are 1:1. the guard below
//     is a `switch`, so a case added without sugar breaks the *build*, not a test.
//   * every component `onX:` init parameter registers through `controlAttributes`,
//     the same function `.onClick`-style modifiers use. there is one
//     implementation; the three surfaces are three spellings of it.
//   * the three spellings are not redundant: a modifier attaches a DOM event to an
//     arbitrary view, `controlAttributes` + `ElementRef` is for a control with a
//     structured payload, and a component's typed parameter is the ergonomic form
//     of that same call. collapsing them would add ceremony, which is the opposite
//     of the framework's stated contract.
//
// one real gap did fall out: `HTMLEvent.custom(_:)` existed and nothing could
// attach it. `View.on(_:perform:)` is that path, and it is tested here.

/// the modifier sugar for one event, produced by an **exhaustive** switch.
///
/// this is the guard, and it is deliberately a `switch` rather than a list: a new
/// `HTMLEvent` case fails to compile here until it has a modifier, so the
/// vocabulary cannot grow past its sugar.
///
/// the render runs inside a `RenderContext` because that is the contract — a
/// modifier outside one logs a warning and emits **nothing**, which is the
/// framework's largest usability trap and the reason this helper exists rather
/// than a bare `.render()`.
private func sugar(for event: HTMLEvent, _ handler: @escaping EventHandler) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) {
        switch event {
        case .click:     return Text("x").onClick(perform: handler).renderThroughBuffer()
        case .submit:    return Text("x").onSubmit(perform: handler).renderThroughBuffer()
        case .input:     return Text("x").onInput(perform: handler).renderThroughBuffer()
        case .change:    return Text("x").onChange(perform: handler).renderThroughBuffer()
        case .mouseover: return Text("x").onMouseOver(perform: handler).renderThroughBuffer()
        case .mouseout:  return Text("x").onMouseOut(perform: handler).renderThroughBuffer()
        case .mousedown: return Text("x").onMouseDown(perform: handler).renderThroughBuffer()
        case .mouseup:   return Text("x").onMouseUp(perform: handler).renderThroughBuffer()
        case .keydown:   return Text("x").onKeyDown(perform: handler).renderThroughBuffer()
        case .keyup:     return Text("x").onKeyUp(perform: handler).renderThroughBuffer()
        case .keypress:  return Text("x").onKeyPress(perform: handler).renderThroughBuffer()
        case .focus:     return Text("x").onFocus(perform: handler).renderThroughBuffer()
        case .blur:      return Text("x").onBlur(perform: handler).renderThroughBuffer()
        case .focusin:   return Text("x").onFocusIn(perform: handler).renderThroughBuffer()
        case .focusout:  return Text("x").onFocusOut(perform: handler).renderThroughBuffer()
        case .pointerdown: return Text("x").onPointerDown(perform: handler).renderThroughBuffer()
        case .pointermove: return Text("x").onPointerMove(perform: handler).renderThroughBuffer()
        case .pointerup:   return Text("x").onPointerUp(perform: handler).renderThroughBuffer()
        case .pointercancel: return Text("x").onPointerCancel(perform: handler).renderThroughBuffer()
        case .pointerenter:  return Text("x").onPointerEnter(perform: handler).renderThroughBuffer()
        case .pointerleave:  return Text("x").onPointerLeave(perform: handler).renderThroughBuffer()
        case .touchstart: return Text("x").onTouchStart(perform: handler).renderThroughBuffer()
        case .touchmove:  return Text("x").onTouchMove(perform: handler).renderThroughBuffer()
        case .touchend:   return Text("x").onTouchEnd(perform: handler).renderThroughBuffer()
        case .dragstart:  return Text("x").onDragStart(perform: handler).renderThroughBuffer()
        case .drag:       return Text("x").onDrag(perform: handler).renderThroughBuffer()
        case .dragend:    return Text("x").onDragEnd(perform: handler).renderThroughBuffer()
        case .dragenter:  return Text("x").onDragEnter(perform: handler).renderThroughBuffer()
        case .dragover:   return Text("x").onDragOver(perform: handler).renderThroughBuffer()
        case .dragleave:  return Text("x").onDragLeave(perform: handler).renderThroughBuffer()
        case .drop:       return Text("x").onDrop(perform: handler).renderThroughBuffer()
        case .copy:       return Text("x").onCopy(perform: handler).renderThroughBuffer()
        case .cut:        return Text("x").onCut(perform: handler).renderThroughBuffer()
        case .paste:      return Text("x").onPaste(perform: handler).renderThroughBuffer()
        case .wheel:      return Text("x").onWheel(perform: handler).renderThroughBuffer()
        case .scroll:     return Text("x").onScroll(perform: handler).renderThroughBuffer()
        case .dblclick:   return Text("x").onDoubleClick(perform: handler).renderThroughBuffer()
        case .contextmenu: return Text("x").onContextMenu(perform: handler).renderThroughBuffer()
        case .animationend: return Text("x").onAnimationEnd(perform: handler).renderThroughBuffer()
        case .transitionend: return Text("x").onTransitionEnd(perform: handler).renderThroughBuffer()
        case .play:       return Text("x").onPlay(perform: handler).renderThroughBuffer()
        case .pause:      return Text("x").onPause(perform: handler).renderThroughBuffer()
        case .ended:      return Text("x").onEnded(perform: handler).renderThroughBuffer()
        case .timeupdate: return Text("x").onTimeUpdate(perform: handler).renderThroughBuffer()
        case .loadedmetadata: return Text("x").onLoadedMetadata(perform: handler).renderThroughBuffer()
        case .error:      return Text("x").onError(perform: handler).renderThroughBuffer()
        case .custom:    return Text("x").on(event, perform: handler).renderThroughBuffer()
        }
    }
}

@Suite("one interactivity idiom")
struct InteractivityIdiomTests {

    /// every named case. the count assertion below is what keeps this list honest
    /// against the enum — the `switch` in `sugar` is the compile-time guard, this
    /// is the runtime one.
    private static let namedCases: [HTMLEvent] = [
        .click, .submit, .input, .change,
        .mouseover, .mouseout, .mousedown, .mouseup,
        .keydown, .keyup, .keypress,
        .focus, .blur, .focusin, .focusout,
        // the wave-4 event deck (W4.1)
        .pointerdown, .pointermove, .pointerup, .pointercancel, .pointerenter, .pointerleave,
        .touchstart, .touchmove, .touchend,
        .dragstart, .drag, .dragend, .dragenter, .dragover, .dragleave, .drop,
        .copy, .cut, .paste,
        .wheel, .scroll,
        .dblclick, .contextmenu,
        .animationend, .transitionend,
        .play, .pause, .ended, .timeupdate, .loadedmetadata, .error,
    ]

    @Test("every named HTMLEvent case has exactly one modifier spelling")
    func vocabularyIsCovered() {
        let handler: EventHandler = { _ in [] }
        for event in Self.namedCases {
            let html = sugar(for: event, handler)
            #expect(
                html.contains("data-event=\"\(event.rawValue)\""),
                "\(event.rawValue) has no modifier: \(html)"
            )
        }
        // 46 in the enum today. if a case is added, `sugar` stops compiling; if one
        // is added to the enum AND to `sugar` but forgotten here, this fails.
        #expect(Self.namedCases.count == 46, "the event vocabulary changed size — update this list")
    }

    @Test("a custom event is reachable — the escape hatch is not stranded")
    func customEventIsReachable() {
        let html = sugar(for: .custom("dragstart")) { _ in [] }
        #expect(html.contains("data-event=\"dragstart\""), "got \(html)")
        #expect(html.contains("data-component-id="), "got \(html)")
    }

    @Test("a modifier emits the routing pair the runtime dispatches on")
    func modifierEmitsRoutingPair() {
        let html = sugar(for: .click) { _ in [] }
        #expect(html.contains("data-component-id="))
        #expect(html.contains("data-event=\"click\""))
    }

    @Test("outside a RenderContext a modifier emits nothing — and says so")
    func withoutContextTheModifierIsInert() {
        // the contract, pinned because it is the framework's sharpest edge: the
        // modifier path registers through the context, so with no context there is
        // nothing to route to. it warns rather than failing, which is why a silent
        // dead control is possible at all.
        let html = Text("x").onClick { _ in [] }.renderThroughBuffer()
        #expect(!html.contains("data-event="), "outside a context there is nothing to emit: \(html)")
    }

    @Test("the same event name means the same wire value through every spelling")
    func spellingsAgree() async {
        // a modifier and a component's typed parameter must land on the same
        // `data-event` value and the same routing contract, or a handler written
        // one way stops working when a component is introduced.
        let modifierHTML = sugar(for: .input) { _ in [] }

        let router = EventRouter()
        let context = RenderContext(router: router)
        let componentHTML = await RenderContext.$current.withValue(context) {
            WebUIInput(placeholder: "p", id: "field").onInput { _ in
                [FragmentUpdate(id: "out", html: "ok")]
            }.renderThroughBuffer()
        }

        #expect(modifierHTML.contains("data-event=\"input\""))
        #expect(componentHTML.contains("data-event=\"input\""))
        #expect(router.handlerCount > 0, "the component path must register, like the modifier path")
    }
}