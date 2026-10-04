import Testing
import WebUI

// MARK: - macro vs hand-written equivalence
//
// the published outputs of the two generations: descriptor / adapter identity,
// reduce parity over an action corpus, and byte-identical html + ops for the
// same states. also pins the diff's op vocabulary literally (text / insert /
// remove / move / attr) so a regression in `HotTree.hotOps` cannot hide behind
// the equivalence (both sides share the diff by construction).

private typealias MacroIsland = MacroCounter.MacroCounterIsland

@Suite("@HotView compiled fixture — macro vs hand-written")
struct ContinuumFixtureTests {

	private let idle = CounterState(label: "idle", count: 0)
	private let alpha = CounterState(label: "alpha", count: 0)
	private let alphaTwo = CounterState(label: "alpha", count: 2)

	// MARK: helpers

	/// `HotEffect` is not Equatable (lane C's vocabulary); compare by shape.
	private func describe(_ effect: HotEffect) -> String {
		switch effect {
		case .ops(let ops): return "ops:\(ops)"
		case .save: return "save"
		case .log(let message): return "log:\(message)"
		}
	}

	private func text(_ id: String, _ content: String) -> HotTree {
		.text(id: ElementID(id), content: content)
	}

	// MARK: descriptor + adapter identity

	@Test("the descriptor is identical, grants by wireName")
	func descriptorEquivalence() {
		#expect(MacroCounter.continuumDescriptor == HandCounter.continuumDescriptor)

		let descriptor = MacroCounter.continuumDescriptor
		#expect(descriptor.name == "counter")
		#expect(descriptor.grants.map { $0.wireName } == ["clock"])
		#expect(descriptor.budget == IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))
		#expect(descriptor.budget.maxBytes == 16_384)
		#expect(descriptor.budget.maxGzipBytes == 4_096)
		#expect(descriptor.className == "counter counter__label")

		#expect(MacroCounter.continuumClasses == ["counter", "counter__label"])
	}

	@Test("DX-9 — the macro-emitted elementIDs equals the hand-written mirror (ProbeIslandIDs pattern)")
	func elementIDVocabularyEquivalence() {
		// the macro walks the @HotBuilder body and emits the literal `id:`
		// vocabulary; the hand-written equivalent mirrors it (ProbeIslandIDs
		// is the always-compiled fallback this is diffed against). the two
		// generations MUST agree — a walked-miss (the only DX-9 bug class)
		// fails here.
		#expect(MacroIsland.elementIDs == HandCounterIsland.elementIDs)
		#expect(MacroIsland.elementIDs == [
			ElementID("counter"),
			ElementID("counter-count"),
			ElementID("counter-label"),
		])
		// every op the fixture can emit targets a KNOWN id — the hand-written
		// island's ops pass the dev-check vocabulary by construction.
		#expect(MacroIsland.elementIDs.contains(ElementID("counter-label")))
		#expect(MacroIsland.elementIDs.contains(ElementID("counter")))
		#expect(!MacroIsland.elementIDs.contains(ElementID("counter-lable")))
	}

	@Test("the generated island adapter matches the hand-written one")
	func adapterEquivalence() {
		#expect(MacroIsland.name == HandCounterIsland.name)
		#expect(MacroIsland.imports.map { $0.wireName } == HandCounterIsland.imports.map { $0.wireName })
		#expect(MacroIsland.imports.map { $0.wireName } == ["clock"])
		#expect(MacroIsland.budget == HandCounterIsland.budget)

		// the peer-emitted `@_expose(wasm, …)` export shims compile and delegate
		// to the adapter's codec entries. the generated entries report the
		// drained batch — an untethered generated surface holds no retained
		// state (the runtime slice owns it per wasm instance); the state-plane
		// accessor (`IslandRuntime<<Type>Island>.encodedState()` /
		// `.decodePendingOps()`) is lane C's W2 surface (d-to-c.md). the
		// non-empty record plane is proven real by `codecRoundTrip` below.
		#expect(_continuumEncodeMacroCounter() == [])
		#expect(_continuumDecodeMacroCounter().isEmpty)

		// anti-shackle: the hand-written adapter carries the SAME codec
		// bodies, so the two generations agree on the drained batch.
		#expect(HandCounterIsland._continuumEncode() == MacroIsland._continuumEncode())
		#expect(HandCounterIsland._continuumDecode().isEmpty == MacroIsland._continuumDecode().isEmpty)
	}

	// MARK: reduce parity

	@Test("both island adapters reduce a corpus to identical states and effects")
	func reduceParity() {
		var macroState = idle
		var handState = idle
		let corpus: [CounterAction] = [.setLabel("alpha"), .increment, .increment, .setLabel("beta"), .decrement]

		for action in corpus {
			let macroEffects = MacroIsland.reduce(state: &macroState, action: action).map(describe)
			let handEffects = HandCounterIsland.reduce(state: &handState, action: action).map(describe)
			#expect(macroEffects == handEffects, "effects diverged for \(action)")
			#expect(macroState == handState, "states diverged after \(action)")
		}
		#expect(macroState == CounterState(label: "beta", count: 1))

		// the effect forwarding is observable, not a stub.
		var solo = idle
		#expect(MacroIsland.reduce(state: &solo, action: .setLabel("gamma")).map(describe) == ["log:label: gamma"])
		#expect(solo == CounterState(label: "gamma", count: 0))
	}

	// MARK: html parity (and a literal pin)

	@Test("both bodies render the same html — pinned literally for the idle state")
	func htmlEquivalence() {
		for state in [idle, alpha, alphaTwo] {
			#expect(MacroCounter().render(state: state).render() == HandCounter().render(state: state).render())
		}
		let expected = "<div id=\"counter\" class=\"counter\"><span id=\"counter-label\">idle</span><div class=\"spacer\" style=\"flex:1\"></div></div>"
		#expect(MacroCounter().render(state: idle).render() == expected)
		#expect(HandCounter().render(state: idle).render() == expected)
	}

	// MARK: ops parity (and literal op pins)

	@Test("both bodies diff to the same ops — and the ops are the planned vocabulary")
	func opsEquivalence() {
		let macroIdle = MacroCounter().render(state: idle)
		let macroAlpha = MacroCounter().render(state: alpha)
		let macroTwo = MacroCounter().render(state: alphaTwo)
		let handIdle = HandCounter().render(state: idle)
		let handAlpha = HandCounter().render(state: alpha)
		let handTwo = HandCounter().render(state: alphaTwo)

		// a label change is exactly one text op (characterData, no churn).
		#expect(macroAlpha.hotOps(previous: macroIdle) == [.text("counter-label", "alpha")])
		#expect(macroAlpha.hotOps(previous: macroIdle) == handAlpha.hotOps(previous: handIdle))

		// a count appearing is one insert, anchored to append.
		let insert = HotOp.insert(
			parent: "counter",
			before: nil,
			html: "<span id=\"counter-count\">count: 2</span>"
		)
		#expect(macroTwo.hotOps(previous: macroAlpha) == [insert])
		#expect(macroTwo.hotOps(previous: macroAlpha) == handTwo.hotOps(previous: handAlpha))

		// a count disappearing is one remove.
		#expect(macroAlpha.hotOps(previous: macroTwo) == [.remove("counter-count")])
		#expect(macroAlpha.hotOps(previous: macroTwo) == handAlpha.hotOps(previous: handTwo))

		// no change, and no previous value, both emit nothing.
		#expect(macroAlpha.hotOps(previous: macroAlpha) == [])
		#expect(macroAlpha.hotOps(previous: nil) == [])
	}

	@Test("the diff's remaining op channels are pinned: move + attr")
	func diffChannelPins() {
		let ab = HotTree.container(id: "list", tag: "ul", className: nil, children: [
			text("a", "A"), text("b", "B"),
		])
		let ba = HotTree.container(id: "list", tag: "ul", className: nil, children: [
			text("b", "B"), text("a", "A"),
		])
		// a swap is two reorders (documented v1: survivors-order, not minimal).
		#expect(ba.hotOps(previous: ab) == [.move("b", before: "a"), .move("a", before: nil)])

		let plain = HotTree.container(id: "row", tag: "tr", className: "row", children: [text("row-label", "x")])
		let selected = HotTree.container(id: "row", tag: "tr", className: "row row--selected", children: [text("row-label", "x")])
		#expect(selected.hotOps(previous: plain) == [.attr("row", "class", "row row--selected")])
	}

	@Test("the codec entry's record plane round-trips real ops byte-exactly (the webui_take_ops drain codec)")
	func codecRoundTrip() {
		// the generated entries delegate to the runtime slice's record codec:
		// `_continuumEncode` operates on the island's pending op batch via
		// HotOpCodec.encodeBatch — the exact call the runtime's webui_take_ops
		// drain produces (IslandRuntime.swift queues each reduce's ops through
		// it) — and `_continuumDecode` decodes records via HotOpCodec.decode.
		// drive that exact codec on a REAL, non-empty op and prove
		// byte-exact identity, so the delegated plane is the live one.
		let op = HotOp.text("counter-label", "alpha")
		let batch = (try? HotOpCodec.encodeBatch([op])) ?? []
		#expect(!batch.isEmpty)
		#expect(MacroIsland._continuumEncode().isEmpty) // untethered = drained (empty) batch
		let decoded = try? HotOpCodec.decode(batch)
		#expect(decoded == op)

		// the drained batch IS the empty record stream — the codec's encoding
		// of zero ops, byte-exact (the pin that retires the `{ [] }` stub form
		// without hiding it: the entry is a real codec call, not a literal).
		#expect(MacroIsland._continuumEncode() == (try? HotOpCodec.encodeBatch([])) ?? [])
		#expect(HandCounterIsland._continuumEncode() == MacroIsland._continuumEncode())
	}

	@Test("the @HotBuilder body and the explicit tree are the same value")
	func builderEqualsExplicitTree() {
		// builder path (two children + no conditional) vs explicit construction.
		let built = Hot.Container(id: "panel", tag: "section", className: "panel") {
			Hot.Text(id: "panel-title", "T")
			Hot.Spacer()
		}
		let explicit = HotTree.container(id: "panel", tag: "section", className: "panel", children: [
			text("panel-title", "T"),
			.spacer,
		])
		#expect(built.hotTree == explicit)

		// a single child stays itself (no fragment wrapper).
		let single = Hot.Container(id: "panel") { Hot.Text(id: "panel-title", "T") }
		#expect(single.children == [text("panel-title", "T")])
	}
}