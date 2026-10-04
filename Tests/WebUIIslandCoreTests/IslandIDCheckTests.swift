import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - DX-9 — the runtime id dev check, natively exercised (CONTINUUM_DX §2.9)
//
// the check build (`-DCONTINUUM_ID_CHECK` compiled into the island graph) and
// this suite run the SAME pure detection code: `IslandIDCheck.firstViolation` /
// `target(of:)` plus the probes' hand-written vocabulary (`ProbeIslandIDs`).
// the flag-gated integration — the runtime calling `enforce` from `onEvent` —
// is exercised by running the whole island-core suite with the flag:
//
//     swift test -Xswiftc -DCONTINUUM_ID_CHECK
//
// if any probe op targeted an unknown id, the script tests in
// IslandRuntimeTests.swift would trap (that is the dev-time failure). the
// check is a dev-time assertion, NOT a type guarantee: derived ids are only
// knowable by the island's own family predicate (d-docs §DX-9).

@Suite struct IslandIDCheckTests {

	// ── the pure detector (compiled in every build) ────────────────────────

	@Test("firstViolation: nil for empty/known ops; names the id for every op shape")
	func namesUnknownIDs() {
		let known: (ElementID) -> Bool = { $0.raw == "ok-id" }
		#expect(IslandIDCheck.firstViolation(ops: [], isKnown: known) == nil)
		#expect(IslandIDCheck.firstViolation(ops: [.text("ok-id", "1")], isKnown: known) == nil)
		#expect(IslandIDCheck.firstViolation(
			ops: [.insert(parent: "ok-id", before: "ok-id", html: "<li></li>")], isKnown: known) == nil)

		let bad: [HotOp] = [
			.text("missing-text", "v"),
			.attr("missing-attr", "data-x", "1"),
			.insert(parent: "missing-parent", before: nil, html: "<li></li>"),
			.remove("missing-remove"),
			.move("missing-move", before: "ok-id"),
		]
		for op in bad {
			let target = IslandIDCheck.target(of: op).raw
			let violation = IslandIDCheck.firstViolation(ops: [op], isKnown: known)
			#expect(violation?.contains("'\(target)'") == true, "must name '\(target)'")
			#expect(violation?.contains(IslandIDCheck.diagnosticPrefix) == true)
		}
	}

	@Test("firstViolation: reports the FIRST bad op in a batch, and only it")
	func firstBadInBatch() {
		let known: (ElementID) -> Bool = { $0.raw == "ok-id" }
		let ops: [HotOp] = [.text("ok-id", "1"), .text("bad-1", "1"), .text("bad-2", "1")]
		let violation = IslandIDCheck.firstViolation(ops: ops, isKnown: known)
		#expect(violation?.contains("'bad-1'") == true)
		#expect(violation?.contains("bad-2") == false)
	}

	@Test("target(of:): insert → parent; before anchors are references, not targets")
	func targetMapping() {
		#expect(IslandIDCheck.target(of: .text("a", "v")).raw == "a")
		#expect(IslandIDCheck.target(of: .attr("b", "data-x", "v")).raw == "b")
		#expect(IslandIDCheck.target(of: .insert(parent: "p", before: "b", html: "")).raw == "p")
		#expect(IslandIDCheck.target(of: .remove("c")).raw == "c")
		#expect(IslandIDCheck.target(of: .move("d", before: "p")).raw == "d")
	}

	// ── the probe's hand-written fallback vocabulary (always compiled) ─────

	@Test("ProbeIslandIDs.isKnown: literals + the keyed-row family; typos rejected")
	func probeVocabulary() {
		#expect(ProbeIslandIDs.isKnown(ElementID(ProbeIslandIDs.counter)))
		#expect(ProbeIslandIDs.isKnown(ElementID(ProbeIslandIDs.list)))
		#expect(ProbeIslandIDs.isKnown(ElementID(ProbeIslandIDs.item("k0"))))
		#expect(ProbeIslandIDs.isKnown(ElementID("probe-item-k12")))
		#expect(!ProbeIslandIDs.isKnown(ElementID("probe-coutner")))
		#expect(!ProbeIslandIDs.isKnown(ElementID("probe-items-k0")))
		#expect(!ProbeIslandIDs.isKnown(ElementID("probe-counter ")))
		#expect(!ProbeIslandIDs.isKnown(ElementID("probe")))
	}

	// ── the property: every op the probe can emit passes the dev check ─────

	@Test("every op ProbeIsland can emit targets a known id")
	func everyEmittedOpIsKnown() {
		var state = ProbeState()
		state.items = [
			ProbeListItem(key: "k0", value: "one"),
			ProbeListItem(key: "k1", value: "two"),
		]
		state.nextItemKey = 2

		var ops: [HotOp] = []
		let actions: [ProbeAction] = [
			.increment(1), .decrement(3), .addItem("third"), .clear, .noop,
		]
		for action in actions {
			ops.append(contentsOf: ProbeIsland.reduceOps(state: &state, action: action))
		}
		#expect(!ops.isEmpty)
		#expect(IslandIDCheck.firstViolation(ops: ops, isKnown: ProbeIslandIDs.isKnown) == nil)
	}

	// ── the gating itself ─────────────────────────────────────────────────

	@Test("IslandIDCheck.enforced reflects the build flag; gated vocabulary exists when on")
	func enforcementMatchesBuild() {
		#if CONTINUUM_ID_CHECK
		#expect(IslandIDCheck.enforced == true)
		#expect(ProbeIsland.elementIDs.contains(ElementID(ProbeIslandIDs.counter)))
		#expect(ProbeIsland.elementIDs.contains(ElementID(ProbeIslandIDs.list)))
		#expect(ProbeIsland.isKnownElementID(ElementID("probe-item-k7")))
		#expect(!ProbeIsland.isKnownElementID(ElementID("probe-coutner")))
		// validate emits no ops and declares no literal ids — check stays vacuous
		#expect(ValidateIsland.elementIDs.isEmpty)
		#else
		#expect(IslandIDCheck.enforced == false)
		#endif
	}
}