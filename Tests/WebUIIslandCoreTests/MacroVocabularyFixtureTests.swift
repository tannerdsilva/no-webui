import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - W3 — the DX-9 equivalent fixture (CONTINUUM_DX §4.7 · d-docs §DX-9)
//
// lane D's @HotView macro (task/d-surface2) emits, per adapter, the id
// vocabulary in a documented spell (c-to-d.md W2 addendum):
//
//     public static var elementIDs: Set<ElementID> { [ElementID("…"), …] }
//     public static func isKnownElementID(_ id: ElementID) -> Bool { … }
//
// D's emission was NOT on origin/dev-continuum when this landed (checked at
// 3381e89 — no `elementIDs` in WebUIContinuumMacro.swift). the runtime half
// is therefore implemented against the DOCUMENTED shape and proven by a
// compilation-unit fixture that mirrors the emission spell verbatim: the
// probe's hand-written `ProbeIslandIDs` stays the always-compiled fallback,
// and this suite diffs the macro-shaped vocabulary against it (the
// equivalent-fixture diff — d-docs §DX-9: "keep the diff in the equivalent-
// fixture test, not in production code").
//
// both halves only exist under `-DCONTINUUM_ID_CHECK` (the vocabulary
// surface is flag-gated on `IslandRuntimeSurface`), so the diff suites are
// inside `#if CONTINUUM_ID_CHECK` and run with:
//
//     swift test -Xswiftc -DCONTINUUM_ID_CHECK

#if CONTINUUM_ID_CHECK

/// the vocabulary a `@HotView`-generated probe adapter would emit, spelled
/// EXACTLY as the macro documents (whole-body literal collection + the
/// dynamic-family override). over-collection here is deliberately none — the
/// literal set carries the two region roots and the family override accepts
/// the keyed rows, mirroring the probe's hand-written `ProbeIslandIDs`.
private enum MacroShapedProbeVocabulary {
	static var elementIDs: Set<ElementID> {
		[ElementID(ProbeIslandIDs.counter), ElementID(ProbeIslandIDs.list)]
	}

	static func isKnownElementID(_ id: ElementID) -> Bool {
		if elementIDs.contains(id) { return true }
		// the keyed-row family the literal set cannot carry
		// (`probe-item-k<n>`), mirroring ProbeIslandIDs.itemPrefix — scalar
		// prefix compare, the embedded-safe discipline.
		var i = id.raw.startIndex
		var j = ProbeIslandIDs.itemPrefix.startIndex
		while j < ProbeIslandIDs.itemPrefix.endIndex {
			guard i < id.raw.endIndex, id.raw[i] == ProbeIslandIDs.itemPrefix[j] else { return false }
			i = id.raw.index(after: i)
			j = ProbeIslandIDs.itemPrefix.index(after: j)
		}
		return true
	}
}

@Suite struct MacroVocabularyFixtureTests {

	// ── the equivalent-fixture diff: macro spell ⇄ hand-written fallback ──

	@Test("the macro-emitted-shaped vocabulary agrees with ProbeIslandIDs on every form")
	func diffAgreesWithHandWrittenFallback() {
		let probe = ProbeIslandIDs.self
		// literals
		#expect(MacroShapedProbeVocabulary.isKnownElementID(ElementID(probe.counter)))
		#expect(MacroShapedProbeVocabulary.isKnownElementID(ElementID(probe.list)))
		// keyed rows (membership by construction, k0 … k47 + edge forms)
		for key in ["k0", "k1", "k12", "k47"] {
			#expect(MacroShapedProbeVocabulary.isKnownElementID(ElementID(probe.item(key))))
		}
		#expect(MacroShapedProbeVocabulary.isKnownElementID(ElementID("probe-item-999999")))
		// rejections must match too
		for typo in ["probe-coutner", "probe-items-k0", "probe-counter ", "probe", "probe-item", "probe-itemk0"] {
			#expect(!MacroShapedProbeVocabulary.isKnownElementID(ElementID(typo)), "macro-shaped vocabulary must reject '\\(typo)' like ProbeIslandIDs")
		}
	}

	@Test("the diff is bidirectionally exhaustive on the probe's own vocabulary family")
	func diffIsExhaustiveOnFamily() {
		// every id ProbeIslandIDs.isKnown accepts must be accepted by the
		// macro-shaped spell, and vice versa, across a bounded input space —
		// the two vocabularies must not drift apart.
		let candidates = ["probe-counter", "probe-list", "probe-item-k0", "probe-item-k9",
		                  "probe-item-", "probe-item", "probe", "probe-coutner", "probe-items-k1",
		                  "probe-item-k", "probe-item-k-1", "probe-counter ", "probe-list "]
		for raw in candidates {
			let id = ElementID(raw)
			#expect(MacroShapedProbeVocabulary.isKnownElementID(id) == ProbeIslandIDs.isKnown(id),
			        "dissenting on '\\(raw)'")
		}
	}

	// ── the runtime consumes the macro-shaped vocabulary (check build) ────

	@Test("the runtime's pure detector accepts every op targeting a macro-shaped-known id and rejects the rest")
	func runtimeDetectorAgainstMacroVocabulary() {
		// the exact surface IslandIDCheck.enforce drives in check builds — the
		// check's `isKnown` closure IS the macro-shaped vocabulary, proving the
		// runtime half wires to the emitted spell end-to-end (d-docs §DX-9).
		#expect(IslandIDCheck.firstViolation(ops: [], isKnown: MacroShapedProbeVocabulary.isKnownElementID) == nil)
		let good: [HotOp] = [
			.text(ElementID(ProbeIslandIDs.counter), "1"),
			.insert(parent: ElementID(ProbeIslandIDs.list), before: nil, html: "<li></li>"),
			.remove(ElementID(ProbeIslandIDs.item("k0"))),
		]
		#expect(IslandIDCheck.firstViolation(ops: good, isKnown: MacroShapedProbeVocabulary.isKnownElementID) == nil)
		let bad = IslandIDCheck.firstViolation(ops: [.move(ElementID("probe-coutner"), before: nil)],
		                                       isKnown: MacroShapedProbeVocabulary.isKnownElementID)
		#expect(bad?.contains("'probe-coutner'") == true)
	}

	// ── the emitted `elementIDs` requirement is satisfiable verbatim ───────

	@Test("a gated conformance with the documented whole-body literal shape is satisfiable")
	func emittedShapeIsSatisfiable() {
		// the macro's shape (a get-only Set of ElementID literals) satisfies
		// IslandRuntimeSurface.elementIDs as the protocol declares it — this
		// compiles because the requirement is spelled `static var elementIDs:
		// Set<ElementID> { get }`; D's emission (an expression-bodied literal
		// collection) type-checks against it unchanged.
		#expect(ProbeIsland.elementIDs.count == 2)
	}
}

#endif
