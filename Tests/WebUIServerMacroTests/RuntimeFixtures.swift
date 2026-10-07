import Synchronization
import Testing
import WebUIServer

// MARK: - the compiled runtime fixtures
//
// these types are compiled by the REAL compiler through the EXTERNAL plugin, so
// the generated splices are type-checked and the runtime behavior is exercised.
// text fixtures only assert emitted text; only a compiled fixture proves the
// generated conformance, the member injection and the isolation hold up.
//
// the shape deliberately mirrors the demo's hand-written control group
// (`Sources/WebUIExample/main.swift`): one custom `LiveRegion` struct with a
// marked source, one custom `LiveState` actor, and a group mixing regions with
// states — so the classifier's skip path is exercised too.

@LiveRegions
struct MacroWidgetGroup {
	@LiveRegion(id: "macro-region-a")
	struct Tick {
		@RegionState let box: LiveBox<Int>

		func render() async -> String? {
			let value = box.value
			return "<div id=\"macro-region-a\">\(value)</div>"
		}
	}

	@LiveState
	actor Feed {
		private var value = 0

		func bump() {
			value += 1
			notify()
		}

		func snapshot() -> Int { value }
	}

	@LiveRegion(id: "macro-region-c", cadence: .milliseconds(50))
	struct Metronome {
		@RegionState let box: LiveBox<Int>

		func render() async -> String? {
			let value = box.value
			return "<div id=\"macro-region-c\">\(value)</div>"
		}
	}

	/// a region with no `@RegionState` marker — its `source` must be nil (the
	/// protocol default), so nothing subscribes at `start()`.
	@LiveRegion(id: "macro-region-e")
	struct Driven {
		func render() async -> String? {
			"<div id=\"macro-region-e\">driven</div>"
		}
	}

	let tick = Tick(box: LiveBox(0))
	let feed = Feed()
	let clock = ClosureLiveRegion(id: "macro-region-b") { () async -> String? in
		"<div id=\"macro-region-b\">clock</div>"
	}
	let count = StateLiveRegion(id: "macro-region-d", state: LiveBox(0)) { box -> String? in
		"<div id=\"macro-region-d\">\(box.value)</div>"
	}
	let metronome = Metronome(box: LiveBox(0))
	let driven = Driven()
}

/// a Sendable delivery counter for the actor fixture.
private final class Deliveries: Sendable {
	private let count = Mutex(0)
	var value: Int { count.withLock { $0 } }
	func record() { count.withLock { $0 += 1 } }
}

@Suite("the live-data macros, compiled and running")
struct LiveMacroRuntimeFixtureTests {
	@Test("the generated region conformance carries the attribute's id and cadence")
	func regionConformance() {
		let tick = MacroWidgetGroup.Tick(box: LiveBox(0))
		#expect(tick.id == "macro-region-a")
		#expect(tick.cadence == nil)
	}

	@Test("the marked property IS the source — the same box, not a copy")
	func markedPropertyIsTheSource() {
		let box = LiveBox(0)
		let tick = MacroWidgetGroup.Tick(box: box)
		let source = tick.source as? LiveBox<Int>
		#expect(source === box)
	}

	@Test("the generated region renders its own value")
	func regionRenders() async {
		let tick = MacroWidgetGroup.Tick(box: LiveBox(7))
		let html = await tick.render()
		#expect(html == "<div id=\"macro-region-a\">7</div>")
	}

	@Test("an explicit cadence is carried by the generated witness; a region with no marker has a nil source")
	func cadenceAndNoSource() {
		let metronome = MacroWidgetGroup.Metronome(box: LiveBox(0))
		#expect(metronome.cadence == .milliseconds(50))
		let driven = MacroWidgetGroup.Driven()
		#expect(driven.source == nil)
		#expect(driven.id == "macro-region-e")
	}

	@Test("subscribe is nonisolated (called synchronously) and notify delivers once per change")
	func stateActorNotifies() async {
		let group = MacroWidgetGroup()
		let deliveries = Deliveries()
		let subscription = group.feed.subscribe { deliveries.record() }
		#expect(deliveries.value == 0)

		await group.feed.bump()
		#expect(deliveries.value == 1)

		subscription.cancel()
		await group.feed.bump()
		#expect(deliveries.value == 1)
	}

	@Test("the assembly produces a WebUILiveRegions from the region properties")
	func assemblyBuildsTheRegistry() {
		let group = MacroWidgetGroup()
		let registry: WebUILiveRegions = group.registry
		#expect(registry.currentHTML("macro-region-a") == nil)
		#expect(registry.currentHTML("macro-region-b") == nil)
		#expect(registry.currentHTML("macro-region-c") == nil)
		#expect(registry.currentHTML("macro-region-d") == nil)
		#expect(registry.currentHTML("macro-region-e") == nil)
	}
}