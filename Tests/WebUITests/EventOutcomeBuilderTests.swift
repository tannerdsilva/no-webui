import Testing
import Synchronization
import WebUI
import WebUICore
@testable import WebUIServer

// MARK: - EventOutcomeBuilder — the per-shape helpers (lane S, s-sugar)
//
// the fixture + twin gate for Sources/WebUICore/EventOutcomeBuilder.swift.
// for every helper the SAME dispatch is expressed twice — through the helper
// and through the hand-written `control("id") { ... }` spelling — and the twin
// holds when both yield identical attributes, identical frames, and identical
// invalidations. the hand-written spelling lives on, compiled, in the same
// suite (the substitution law's "the hand path keeps compiling").
//
// every wiring runs inside `RenderContext.withCurrent`, exactly as the page
// render and the dispatch path do — a control wired outside the seam is dead
// by design (the DX-12 rule the i0 suite pins).

// MARK: - helpers

/// a `View` the framework has never seen — as in the i0 twin suite.
private struct ProbeView: View {
	let body: String
	func render() -> String { "<span>\(body)</span>" }
}

/// records the ids an `invalidate` provider is handed, thread-safely.
private final class InvalidateRecorder: Sendable {
	private let state = Mutex<[String]>([])

	func record(_ ids: [String]) {
		state.withLock { $0.append(contentsOf: ids) }
	}

	var ids: [String] { state.withLock { $0 } }
}

/// drives one dispatch through the real seam, returning the wire frames.
private func drive(
	_ router: EventRouter,
	_ id: String,
	invalidate: @escaping @Sendable ([String]) -> Void
) async -> [FragmentUpdate] {
	await dispatchOutcome(EventData(component: ComponentID(id), event: "click"), router: router, invalidate: invalidate)
}

@Suite("EventOutcomeBuilder — the per-shape helpers (s-sugar)")
struct EventOutcomeBuilderTests {

	@Test("noOutcome is the hand-written NoOutcome handler, spelled as a void body (the twin)")
	func noOutcomeTwin() async {
		let router = EventRouter()
		let counter = Mutex<Int>(0)

		// the helper path.
		let helper = RenderContext.withCurrent(router: router) {
			noOutcome("no-helper") { _ in
				counter.withLock { $0 += 1 }
			}
		}
		// the hand-written path, byte-for-byte today's spelling.
		let hand = RenderContext.withCurrent(router: router) {
			control("no-hand", event: .click) { (_: EventData) -> NoOutcome in
				counter.withLock { $0 += 1 }
				return NoOutcome()
			}
		}

		#expect(helper == " data-component-id=\"no-helper\" data-event=\"click\"")
		#expect(hand == " data-component-id=\"no-hand\" data-event=\"click\"")

		_ = await drive(router, "no-helper", invalidate: { _ in })
		_ = await drive(router, "no-hand", invalidate: { _ in })
		#expect(counter.withLock { $0 } == 2, "both paths ran their effects")
	}

	@Test("fragments emits several updates, verbatim (the twin)")
	func fragmentsTwin() async {
		let router = EventRouter()
		let recorder = InvalidateRecorder()

		let helper = RenderContext.withCurrent(router: router) {
			fragments("fr-helper") { _ in
				[FragmentUpdate(id: "a", html: "<p>a</p>"), FragmentUpdate(id: "b", html: "<p>b</p>")]
			}
		}
		let hand = RenderContext.withCurrent(router: router) {
			control("fr-hand", event: .click) { (_: EventData) async -> [FragmentUpdate] in
				[FragmentUpdate(id: "a", html: "<p>a</p>"), FragmentUpdate(id: "b", html: "<p>b</p>")]
			}
		}

		#expect(helper == " data-component-id=\"fr-helper\" data-event=\"click\"")
		#expect(hand == " data-component-id=\"fr-hand\" data-event=\"click\"")

		let helperFrames = _idFrames(await drive(router, "fr-helper", invalidate: recorder.record))
		let handFrames = _idFrames(await drive(router, "fr-hand", invalidate: recorder.record))
		#expect(helperFrames == handFrames, "the helper and the hand path push the same frames")
		#expect(helperFrames == ["a", "b"])
	}

	@Test("replaceFragment is the single-update shape (the twin)")
	func replaceFragmentTwin() async {
		let router = EventRouter()

		let helper = RenderContext.withCurrent(router: router) {
			replaceFragment("rf-helper") { _ in FragmentUpdate(id: "one", html: "<p>1</p>") }
		}
		let hand = RenderContext.withCurrent(router: router) {
			control("rf-hand", event: .click) { (_: EventData) async -> FragmentUpdate in
				FragmentUpdate(id: "one", html: "<p>1</p>")
			}
		}

		#expect(helper == " data-component-id=\"rf-helper\" data-event=\"click\"")
		#expect(hand == " data-component-id=\"rf-hand\" data-event=\"click\"")

		let helperFrames = _idFrames(await drive(router, "rf-helper", invalidate: { _ in }))
		let handFrames = _idFrames(await drive(router, "rf-hand", invalidate: { _ in }))
		#expect(helperFrames == handFrames && helperFrames == ["one"])
	}

	@Test("replaceView renders the view and replaces the firing component id (the twin)")
	func replaceViewTwin() async {
		let router = EventRouter()

		let helper = RenderContext.withCurrent(router: router) {
			replaceView("rv-helper") { _ in ProbeView(body: "via-helper") }
		}
		let hand = RenderContext.withCurrent(router: router) {
			control("rv-hand", event: .click) { (_: EventData) async -> ViewOutcome<ProbeView> in
				ViewOutcome(ProbeView(body: "via-hand"))
			}
		}

		let helperFrames = await drive(router, "rv-helper", invalidate: { _ in })
		let handFrames = await drive(router, "rv-hand", invalidate: { _ in })
		// each path replaces ITS OWN firing id with its rendered content — the
		// ids and view bodies differ (helper vs hand) by test design, so the
		// twin is "same mechanism": both paths replace the firing component id
		// with their own render, asserted per path below.
		#expect(helperFrames == [FragmentUpdate(id: "rv-helper", html: "<span>via-helper</span>")])
		#expect(handFrames == [FragmentUpdate(id: "rv-hand", html: "<span>via-hand</span>")])
	}

	@Test("invalidate declares the change through the dispatch context, no frames (the twin)")
	func invalidateTwin() async {
		let router = EventRouter()
		let helperRecorder = InvalidateRecorder()
		let handRecorder = InvalidateRecorder()

		let helper = RenderContext.withCurrent(router: router) {
			invalidate("iv-helper", ids: ["region-a", "region-c"])
		}
		let hand = RenderContext.withCurrent(router: router) {
			control("iv-hand", event: .click) { (_: EventData) -> RegionInvalidations in
				RegionInvalidations(["region-a", "region-c"])
			}
		}

		#expect(helper == " data-component-id=\"iv-helper\" data-event=\"click\"")
		#expect(hand == " data-component-id=\"iv-hand\" data-event=\"click\"")

		let helperFrames = await drive(router, "iv-helper", invalidate: helperRecorder.record)
		let handFrames = await drive(router, "iv-hand", invalidate: handRecorder.record)
		#expect(helperFrames.isEmpty && handFrames.isEmpty, "invalidations carry no fragments")
		#expect(helperRecorder.ids == handRecorder.ids && helperRecorder.ids == ["region-a", "region-c"],
			"the provider handed to the seam is the one the helper used")
	}

	@Test("updateThenInvalidate preserves the d-k ordering: the fragment before the push")
	func updateThenInvalidateOrdering() async {
		let router = EventRouter()
		let recorder = InvalidateRecorder()

		let helper = RenderContext.withCurrent(router: router) {
			updateThenInvalidate("ui-helper", ids: ["region-a"]) { _ in
				FragmentUpdate(id: "g-out", html: "<span id=\"g-out\">first</span>")
			}
		}
		// the hand twin — today's demo combined spelling.
		let hand = RenderContext.withCurrent(router: router) {
			control("ui-hand", event: .click) {
				(_: EventData) -> CombinedOutcome<FragmentUpdate, RegionInvalidations> in
				CombinedOutcome(
					FragmentUpdate(id: "g-out", html: "<span id=\"g-out\">first</span>"),
					RegionInvalidations(["region-a"])
				)
			}
		}

		#expect(helper == " data-component-id=\"ui-helper\" data-event=\"click\"")
		#expect(hand == " data-component-id=\"ui-hand\" data-event=\"click\"")

		let helperFrames = await drive(router, "ui-helper", invalidate: recorder.record)
		let handFrames = await drive(router, "ui-hand", invalidate: recorder.record)
		#expect(helperFrames == handFrames && helperFrames == [FragmentUpdate(id: "g-out", html: "<span id=\"g-out\">first</span>")])
		#expect(recorder.ids == ["region-a", "region-a"], "both paths invalidated the same ids, in order")
	}

	/// extract the frame ids for a compact equality comparison.
	private func _idFrames(_ frames: [FragmentUpdate]) -> [String] { frames.map(\.id) }
}
