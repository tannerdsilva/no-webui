import Synchronization
import Testing
import WebUI
import WebUIDesignSystem

// typed event payloads
// (`.hermes/plans/2026-10-08_151549_GENERAL_WEB_CAPABILITY.md`, W0.8; defect T8).
//
// `EventData.data` is `[String: JSONValue]`, but the only way to read it was
// `event.string("targetId")` / `event.string("value")` — a magic string whose
// typo compiles and silently returns `nil`, so a handler that never fires looks
// like a handler that does nothing.
//
// every framework-shipped handler now reads the named accessors below, so the
// pattern a reader copies out of the source is the typed one. `string(_:)` stays
// — it is frozen surface — for a field the framework does not name.

@Suite("typed event payloads")
struct EventPayloadTests {

    private func event(_ data: [String: JSONValue]) -> EventData {
        EventData(component: ComponentID("c0"), event: "click", data: data)
    }

    @Test("the named accessors read the wire keys")
    func namedAccessorsReadWireKeys() {
        let e = event([
            "targetId": .string("row-3"),
            "targetClass": .string("row__cell"),
            "value": .string("typed"),
            "key": .string("Enter"),
            "checked": .bool(true),
        ])
        #expect(e.targetID == "row-3")
        #expect(e.targetClass == "row__cell")
        #expect(e.value == "typed")
        #expect(e.key == "Enter")
        #expect(e.checked == true)
    }

    @Test("a missing field is nil through every accessor")
    func missingFieldsAreNil() {
        let e = event([:])
        #expect(e.targetID == nil)
        #expect(e.targetClass == nil)
        #expect(e.value == nil)
        #expect(e.key == nil)
        #expect(e.checked == nil)
    }

    @Test("a wrongly-typed field is nil, never a coercion")
    func wrongTypeIsNil() {
        // a number where a string is expected must not stringify, and vice versa:
        // a silent coercion is how a payload bug survives to production.
        let e = event(["value": .number(7), "checked": .string("true"), "targetId": .null])
        #expect(e.value == nil)
        #expect(e.checked == nil, "the string \"true\" is not a bool")
        #expect(e.targetID == nil)
    }

    @Test("the stringly accessors are preserved — they are frozen surface")
    func stringlyAccessorsStillWork() {
        let e = event(["message": .string("hello"), "count": .number(3), "flag": .bool(true)])
        #expect(e.string("message") == "hello")
        #expect(e.number("count") == 3)
        #expect(e.bool("flag") == true)
        // an unnamed field is exactly what the generic accessors are for.
        #expect(e.value == nil)
    }

    @Test("a component handler receives the same payload the wire carried")
    func handlerSeesTheTypedValue() async {
        let router = EventRouter()
        let context = RenderContext(router: router)
        let seen = Mutex<[String?]>([])

        let html = await RenderContext.$current.withValue(context) {
            WebUIInput(placeholder: "p", id: "field").onInput { event in
                seen.withLock { $0.append(event.value) }
                return []
            }.renderThroughBuffer()
        }

        // the rendered attribute names the component the runtime will dispatch to.
        guard let marker = html.range(of: "data-component-id=\"") else {
            Issue.record("no routing attribute in \(html)")
            return
        }
        let rest = html[marker.upperBound...]
        let componentID = String(rest[..<rest.firstIndex(of: "\"")!])

        _ = await router.dispatch(
            EventData(component: ComponentID(componentID), event: "input", data: ["value": .string("hi")])
        )

        #expect(seen.withLock { $0 } == ["hi"])
    }
}