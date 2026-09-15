import Foundation
import Testing
@testable import WebUI
@testable import WebUICore
@testable import WebUIDesignSystem

// MARK: - Dismissible wiring

@Suite("Dismissible components")
struct DismissibleTests {

    // MARK: wired routing

    @Test("onDismiss wires the toast close button as a routed component")
    func toastOnDismissWiresButton() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            WebUIToast(message: "Saved")
                .onDismiss { _, _ in [] }
                .render()
        }

        // the close button becomes a routed component
        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("data-event=\"click\""), "emitted: \(html)")
        // the static marker is retained so the button still announces dismissal
        #expect(html.contains("data-dismiss"), "emitted: \(html)")
        // no caller id → the framework minted e0 for the root
        #expect(html.contains("id=\"e0\""), "emitted: \(html)")

        // the click routes to the registered handler
        let updates = await router.handle(EventData(component: "c0", event: "click", data: [:]))
        #expect(updates.isEmpty)
    }

    @Test("onDismiss receives a self ref whose remove() targets the toast root")
    func toastOnDismissMeRemove() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            WebUIToast(message: "Saved", id: "toast-1")
                .onDismiss { me, _ in
                    // me must reference the toast root: both remove and replace
                    // target the same stable id, no string matching anywhere.
                    [me.remove(), me.replace(with: "<div>gone</div>")]
                }
                .render()
        }

        // stable caller id is used as the element id
        #expect(html.contains("id=\"toast-1\""), "emitted: \(html)")

        let updates = await router.handle(EventData(component: "c0", event: "click", data: [:]))

        // the handler ran and every fragment targeted the toast root
        #expect(updates.count == 2)
        #expect(updates[0] == FragmentUpdate(id: "toast-1", html: ""),
                "remove() must produce an empty fragment for the toast root, got \(updates[0])")
        #expect(updates[1] == FragmentUpdate(id: "toast-1", html: "<div>gone</div>"))
    }

    @Test("each wired dismissible routes to exactly its own handler")
    func multipleDismissiblesRouteIndependently() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            Div {
                WebUIToast(message: "One", id: "toast-1")
                    .onDismiss { me, _ in [me.remove()] }
                WebUIToast(message: "Two", id: "toast-2")
                    .onDismiss { me, _ in [me.remove()] }
            }
            .render()
        }

        // each close button is its own routed component
        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"c1\""), "emitted: \(html)")

        // dispatch to component c1 → only toast-2's handler runs
        let updates = await router.handle(EventData(component: "c1", event: "click", data: [:]))
        #expect(updates == [FragmentUpdate(id: "toast-2", html: "")],
                "c1 must route to the second toast only, got \(updates)")

        let updates2 = await router.handle(EventData(component: "c0", event: "click", data: [:]))
        #expect(updates2 == [FragmentUpdate(id: "toast-1", html: "")])
    }

    @Test("onDismiss without a RenderContext falls back to the static marker")
    func onDismissWithoutContextStaticFallback() {
        let html = WebUIToast(message: "Saved")
            .onDismiss { _, _ in [] }
            .render()

        // no component id, no minted element id — byte-identical to un-wired output
        #expect(!html.contains("data-component-id"), "emitted: \(html)")
        #expect(html == "<div class=\"toast toast--info\" role=\"alert\"><span class=\"toast__icon\"></span><span class=\"toast__message\">Saved</span><button class=\"toast__close\" data-dismiss aria-label=\"Dismiss\">&times;</button></div>")
    }

    // MARK: static byte-compatibility (the legacy container-handler pattern)

    @Test("unwired dismissible toast keeps the legacy static marker")
    func toastStaticMarkerUnchanged() {
        let html = WebUIToast(message: "Saved", dismissible: true).render()
        #expect(html == "<div class=\"toast toast--info\" role=\"alert\"><span class=\"toast__icon\"></span><span class=\"toast__message\">Saved</span><button class=\"toast__close\" data-dismiss aria-label=\"Dismiss\">&times;</button></div>")
        #expect(!html.contains("data-component-id"))
    }

    @Test("unwired modal close button keeps the legacy static marker")
    func modalStaticMarkerUnchanged() {
        let html = WebUIModal(title: "Confirm") { Text("body") }.render()
        #expect(html.contains("<button class=\"modal__close\" data-dismiss aria-label=\"Close\">&times;</button>"))
        #expect(!html.contains("data-component-id"))
    }

    @Test("unwired removable chip keeps the legacy static marker")
    func chipStaticMarkerUnchanged() {
        let html = WebUIChip("Tag", removable: true).render()
        #expect(html.contains("<button class=\"chip__remove\" data-remove aria-label=\"Remove\">&times;</button>"))
        #expect(!html.contains("data-component-id"))
    }

    @Test("unwired alert close button keeps the legacy static marker")
    func alertStaticMarkerUnchanged() {
        let html = WebUIAlert(message: "notice", dismissible: true).render()
        #expect(html.contains("<button class=\"alert__close\" data-dismiss aria-label=\"Dismiss\">&times;</button>"))
        #expect(!html.contains("data-component-id"))
    }

    @Test("non-dismissible components render no close button even with static marker support")
    func nonDismissibleRendersNoButton() {
        let html = WebUIToast(message: "Saved", dismissible: false).render()
        #expect(!html.contains("toast__close"))
    }

    // MARK: chip uses the remove marker when wired

    @Test("wired chip remove button carries data-remove plus component routing")
    func chipOnDismissWiresRemoveButton() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            WebUIChip("Tag", id: "chip-1")
                .onDismiss { me, _ in [me.remove()] }
                .render()
        }

        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("data-remove"), "emitted: \(html)")
        #expect(html.contains("id=\"chip-1\""), "emitted: \(html)")

        let updates = await router.handle(EventData(component: "c0", event: "click", data: [:]))
        #expect(updates == [FragmentUpdate(id: "chip-1", html: "")])
    }

    @Test("wired modal close button returns fragments for a stable modal id")
    func modalOnDismissRoutes() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            WebUIModal(title: "Confirm", id: "modal-1") { Text("body") }
                .onDismiss { me, _ in [me.remove()] }
                .render()
        }

        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("id=\"modal-1\""), "emitted: \(html)")

        let updates = await router.handle(EventData(component: "c0", event: "click", data: [:]))
        #expect(updates == [FragmentUpdate(id: "modal-1", html: "")])
    }

    @Test("wired alert close button returns fragments for a minted alert id")
    func alertOnDismissRoutes() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            WebUIAlert(message: "notice")
                .onDismiss { me, _ in [me.remove()] }
                .render()
        }

        // alert has no caller id → framework mints e0
        #expect(html.contains("id=\"e0\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("data-dismissible"), "emitted: \(html)")

        let updates = await router.handle(EventData(component: "c0", event: "click", data: [:]))
        #expect(updates == [FragmentUpdate(id: "e0", html: "")])
    }

    // MARK: element id minting is independent of component ids

    @Test("element ids and component ids come from separate counters")
    func elementAndComponentIdsAreDistinct() async {
        let router = EventRouter()
        let context = RenderContext(router: router)

        let html = RenderContext.$current.withValue(context) {
            Div {
                WebUIToast(message: "A").onDismiss { me, _ in [me.remove()] }
                WebUIToast(message: "B").onDismiss { me, _ in [me.remove()] }
            }
            .render()
        }

        // component ids: c0, c1 — element ids: e0, e1 (never colliding)
        #expect(html.contains("data-component-id=\"c0\""), "emitted: \(html)")
        #expect(html.contains("data-component-id=\"c1\""), "emitted: \(html)")
        #expect(html.contains("id=\"e0\""), "emitted: \(html)")
        #expect(html.contains("id=\"e1\""), "emitted: \(html)")
        // a component id must never appear as a standalone id attribute
        // (data-component-id=... contains "id=\"c" as a substring, so match the
        // space-prefixed attribute form to distinguish them)
        #expect(!html.contains(" id=\"c"), "a component id must never be used as an element id: \(html)")
    }

    // MARK: ElementRef

    @Test("ElementRef.remove produces an empty-html fragment for its id")
    func elementRefRemove() {
        let ref = ElementRef(id: "target")
        #expect(ref.remove() == FragmentUpdate(id: "target", html: ""))
    }

    @Test("ElementRef.replace produces a fragment with the given html")
    func elementRefReplace() {
        let ref = ElementRef(id: "target")
        #expect(ref.replace(with: "<div>hi</div>") == FragmentUpdate(id: "target", html: "<div>hi</div>"))
    }

    @Test("ElementRef.update renders a view into a fragment")
    func elementRefUpdate() {
        let ref = ElementRef(id: "target")
        let update = ref.update(Text("hello"))
        #expect(update.id == "target")
        #expect(update.html.contains("hello"))
    }
}
