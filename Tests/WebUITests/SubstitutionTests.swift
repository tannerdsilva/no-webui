import Testing
import Synchronization
import WebUI
import WebUICore
@testable import WebUIServer

// MARK: - Substitution — the i0-owned suite
//
// the i0 landing's own gate (LIVE_DX §4.3, appendix A.1). it is owned by the
// landing, not by lane R, because it pins the *seam* both W1 lanes build on:
//
//   · DX-12 — `RenderContext.withCurrent` establishes the dispatch-scoped render
//     context, so a control first rendered INSIDE a handler self-registers.
//   · DX-14 — `EventOutcome` and its six default conformances adapt to the one
//     wire substrate; `control(_:handler:)` is the erased adapter.
//
// the honest control is `handlerIntroducedControlIsDeadWithoutTheSeam`: the same
// handler body run through `router.handle` (no seam) leaves the nested control
// unregistered. that is what proves the seam is load-bearing rather than
// decorative — the in-process half of d-m (the probe's half is frames-only).

// MARK: - helpers

/// a `View` the framework has never seen — the substitution law's shape.
private struct ProbeView: View {
	let body: String
	func render() -> String { "<span>\(body)</span>" }
}

/// an `EventOutcome` the framework has never seen (the i0 twin).
private struct CustomOutcome: EventOutcome {
	let html: String
	func resolve(_ context: OutcomeContext) async -> [FragmentUpdate] {
		[FragmentUpdate(id: "custom-\(context.component.value)", html: html)]
	}
}

/// records the ids an `invalidate` provider is handed, thread-safely.
private final class InvalidateRecorder: Sendable {
	private let state = Mutex<[String]>([])

	func record(_ ids: [String]) {
		state.withLock { $0.append(contentsOf: ids) }
	}

	var ids: [String] { state.withLock { $0 } }
}

/// records the component id each handler invocation saw in the outcome context.
private final class SeenRecorder: Sendable {
	private let state = Mutex<[String]>([])

	func record(_ value: String) {
		state.withLock { $0.append(value) }
	}

	var values: [String] { state.withLock { $0 } }
}

// MARK: - DX-12 — the seam

@Suite("Substitution — the render-context seam (DX-12)")
struct RenderContextSeamTests {

	@Test("withCurrent establishes the context for the body and restores it after (both overloads)")
	func withCurrentEstablishesAndRestores() async {
		let router = EventRouter()
		#expect(RenderContext.current == nil, "no context outside a seam")

		// the async overload: the context must survive a suspension point inside the
		// body — exactly what the dispatch path relies on.
		let asyncSawRouter = await RenderContext.withCurrent(router: router) {
			await Task.yield()
			return RenderContext.current?.router === router
		}
		// the sync overload in its natural shape (a non-async closure).
		let syncSawRouter = RenderContext.withCurrent(router: router) {
			RenderContext.current?.router === router
		}

		#expect(asyncSawRouter, "the async overload establishes the context")
		#expect(syncSawRouter, "the sync overload establishes the context")
		#expect(RenderContext.current == nil, "the context is restored on exit")
	}

	@Test("the seam hands the body THE router, and its counters advance")
	func withCurrentSkipsAnID() async {
		let router = EventRouter()
		let first = await RenderContext.withCurrent(router: router) {
			await Task.yield()
			var context = RenderContext.current
			return context?.nextComponentID().value
		}
		let second = await RenderContext.withCurrent(router: router) {
			await Task.yield()
			var context = RenderContext.current
			return context?.nextComponentID().value
		}
		#expect(first != nil)
		#expect(second != nil)
		#expect(first != second, "the router's counter is shared state across seam entries")
	}

	@Test("a control first rendered INSIDE a handler self-registers (the seam is load-bearing)")
	func handlerIntroducedControlRegistersUnderTheSeam() async {
		let router = EventRouter()
		let child = [FragmentUpdate(id: "fresh", html: "<p>fresh</p>")]

		router.register({ _ in
			// the handler body renders a NEW control. under the seam the render
			// context is present, so `control` registers it there and then.
			let attributes = control("fresh", event: .click) { (_: EventData) async -> [FragmentUpdate] in
				child
			}
			return [FragmentUpdate(id: "swap", html: "<button\(attributes)>swap</button>")]
		}, for: "swap")

		#expect(router.handlerCount == 1)

		let first = await dispatchOutcome(EventData(component: "swap", event: "click"), router: router)
		#expect(first.count == 1)
		#expect(first[0].id == "swap")
		#expect(first[0].html.contains("data-component-id=\"fresh\""))
		#expect(router.handlerCount == 2, "the handler-introduced control registered itself")

		let second = await dispatchOutcome(EventData(component: "fresh", event: "click"), router: router)
		#expect(second == child, "a later event reaches the handler-introduced control")
	}

	@Test("control run — without the seam the same handler body leaves the control dead")
	func handlerIntroducedControlIsDeadWithoutTheSeam() async {
		let router = EventRouter()

		router.register({ _ in
			let attributes = control("cold-child", event: .click) { (_: EventData) async -> [FragmentUpdate] in
				[]
			}
			return [FragmentUpdate(id: "cold", html: "<button\(attributes)>cold</button>")]
		}, for: "cold")

		// bypass the seam: no render context is established for the handler body.
		let updates = await router.handle(EventData(component: "cold", event: "click"))
		#expect(updates.count == 1)
		#expect(updates[0].html.contains("data-component-id=\"cold-child\""))
		#expect(router.handlerCount == 1, "the nested control never registered — this is the pre-i0 state")
	}

	@Test("registration is overwrite-wins (last-render-wins) for a stable id (d-n)")
	func registrationIsOverwriteWins() async {
		let router = EventRouter()
		router.register({ _ in [FragmentUpdate(id: "x", html: "first")] }, for: "x")
		router.register({ _ in [FragmentUpdate(id: "x", html: "second")] }, for: "x")

		#expect(router.handlerCount == 1, "one id, one registration — the newest")

		let updates = await dispatchOutcome(EventData(component: "x", event: "click"), router: router)
		#expect(updates == [FragmentUpdate(id: "x", html: "second")])
	}
}

// MARK: - DX-14 — the outcome protocol

@Suite("Substitution — the outcome protocol (DX-14)")
struct EventOutcomeTests {

	@Test("the six default conformances adapt to the one wire substrate")
	func conformanceMatrix() async {
		let recorder = InvalidateRecorder()
		let context = OutcomeContext(component: "ctrl", invalidate: recorder.record)

		let single = FragmentUpdate(id: "a", html: "<p>a</p>")
		#expect(await single.resolve(context) == [single], "FragmentUpdate → itself")
		#expect(await [single].resolve(context) == [single], "[FragmentUpdate] → itself")
		#expect(await NoOutcome().resolve(context).isEmpty, "NoOutcome → nothing")

		let view = await ViewOutcome(ProbeView(body: "hi")).resolve(context)
		#expect(view == [FragmentUpdate(id: "ctrl", html: "<span>hi</span>")], "ViewOutcome replaces the firing component id")

		#expect(await RegionInvalidations(["r1", "r2"]).resolve(context).isEmpty, "invalidations carry no fragments")
		#expect(recorder.ids == ["r1", "r2"], "the provider recorded the ids, in order")

		let combined = await CombinedOutcome(single, RegionInvalidations(["r3"])).resolve(context)
		#expect(combined == [single], "CombinedOutcome concatenates")
		#expect(recorder.ids == ["r1", "r2", "r3"])
	}

	@Test("a custom EventOutcome drives the same dispatch path (the i0 twin)")
	func customOutcomeThroughTheErasedAdapter() async {
		let router = EventRouter()

		let attributes = RenderContext.withCurrent(router: router) {
			// `control` is the erased adapter: its closure type fixes `O`, here a
			// type the framework has never seen.
			control("custom-ctl", event: .click) { (_: EventData) async -> CustomOutcome in
				CustomOutcome(html: "<em>custom</em>")
			}
		}
		#expect(attributes == " data-component-id=\"custom-ctl\" data-event=\"click\"")

		let updates = await dispatchOutcome(EventData(component: "custom-ctl", event: "click"), router: router)
		#expect(updates == [FragmentUpdate(id: "custom-custom-ctl", html: "<em>custom</em>")])
	}

	@Test("a ViewOutcome through the adapter replaces the control's own id (d-x2)")
	func viewOutcomeThroughTheAdapter() async {
		let router = EventRouter()
		_ = RenderContext.withCurrent(router: router) {
			control("panel", event: .click) { (_: EventData) async -> ViewOutcome<ProbeView> in
				ViewOutcome(ProbeView(body: "rebuilt"))
			}
		}

		let updates = await dispatchOutcome(EventData(component: "panel", event: "click"), router: router)
		#expect(updates == [FragmentUpdate(id: "panel", html: "<span>rebuilt</span>")])
	}

	@Test("OutcomeContext.current is dispatch-scoped")
	func outcomeContextIsDispatchScoped() async {
		#expect(OutcomeContext.current == nil, "nil outside a dispatch")

		let router = EventRouter()
		let seen = SeenRecorder()
		router.register({ _ in
			seen.record(OutcomeContext.current?.component.value ?? "nil")
			return []
		}, for: "probe")

		_ = await dispatchOutcome(EventData(component: "probe", event: "click"), router: router)
		#expect(seen.values == ["probe"], "the handler reads the firing component")
		#expect(OutcomeContext.current == nil, "the context does not leak past the dispatch")
	}

	@Test("the invalidate provider reaches the erased adapter at dispatch time")
	func invalidateProviderIsThreadedByTheSeam() async {
		let router = EventRouter()
		let recorder = InvalidateRecorder()

		_ = RenderContext.withCurrent(router: router) {
			control("bump", event: .click) { (_: EventData) async -> RegionInvalidations in
				RegionInvalidations(["panel-a", "panel-b"])
			}
		}

		let updates = await dispatchOutcome(
			EventData(component: "bump", event: "click"),
			router: router,
			invalidate: recorder.record
		)

		#expect(updates.isEmpty, "the invalidation half carries no fragments")
		#expect(recorder.ids == ["panel-a", "panel-b"], "the provider handed to the seam is the one the adapter used")
	}
}

// MARK: - I5 — the pre-existing surface is byte-unchanged

@Suite("Substitution — the stable-id surface is unchanged (I5)")
struct ControlAttributesCompatibilityTests {

	@Test("controlAttributes emits identical bytes with a handler, and none without")
	func controlAttributesBytesUnchanged() {
		let wired = controlAttributes(id: "keep", event: .click) { (_: EventData) async -> [FragmentUpdate] in
			[]
		}
		#expect(wired == " data-component-id=\"keep\" data-event=\"click\"")

		let submitted = controlAttributes(id: "form-1", event: .submit) { (_: EventData) async -> [FragmentUpdate] in
			[]
		}
		#expect(submitted == " data-component-id=\"form-1\" data-event=\"submit\"")

		#expect(controlAttributes(id: "static", event: .click, handler: nil) == "", "nil handler renders statically")
	}

	@Test("ids are html-escaped on both the attribute and the event")
	func controlAttributesEscapes() {
		let escaped = controlAttributes(id: "a\"b", event: .click) { (_: EventData) async -> [FragmentUpdate] in
			[]
		}
		#expect(escaped == " data-component-id=\"a&quot;b\" data-event=\"click\"")
	}
}