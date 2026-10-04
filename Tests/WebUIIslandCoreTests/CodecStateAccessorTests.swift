import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - W3 — the codec-state accessors (CONTINUUM_DX W3 · d-to-c.md W2 delta)
//
// lane D's generated `_continuumEncode`/`_continuumDecode` swap their bodies
// to `IslandRuntime<<Type>Island>.encodedState()` / `.decodePendingOps()`.
// both read the BOUND runtime instance; on host builds nothing is ever bound
// (the bind shim is wasm-only), so the statics report the drained contract
// (`[]` / empty). the CORE halves (`IslandRuntimeCore.stateSave()` and the new
// `decodePendingOps()`) are native-testable here — the same code the wasm
// bridge executes.

// ── the core decode accessor (native-testable, wasm-exact) ────────────────

@Test("core.decodePendingOps: decodes the queued records into leaf effects")
func coreDecodePendingOps() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.renderRegion(input: _rtTextBytes(#"{"name":"probe","args":{}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))     // text counter 1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))   // text counter 0
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))   // text counter -1

	let effects = core.decodePendingOps()
	#expect(effects.count == 3)
	var ops: [HotOp] = []
	for effect in effects {
		guard case .ops(let batch) = effect else { Issue.record("expected .ops, got \(effect)"); continue }
		ops.append(contentsOf: batch)
	}
	#expect(ops == [.text(ElementID(ProbeIslandIDs.counter), "1"),
	                .text(ElementID(ProbeIslandIDs.counter), "0"),
	                .text(ElementID(ProbeIslandIDs.counter), "-1")])
}

@Test("core.decodePendingOps: a multi-op event decodes as ONE contiguous batch")
func coreDecodeMultiOpBatch() {
	// clear emits remove k0/k1/k2 as a single event's op batch — one queued
	// record (encodeBatch of 3 removals). the decode must return it as one
	// `.ops([...])` effect with all three removals, byte-faithful.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.renderRegion(input: _rtTextBytes(#"{"name":"probe","args":{}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"a"}}"#)) // k0
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"b"}}"#)) // k1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"c"}}"#)) // k2
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-clear"}"#)) // remove k0,k1,k2 — one event, 3 records back-to-back

	let effects = core.decodePendingOps()
	// four queued records: three single-op inserts then one 3-op clear batch.
	#expect(effects.count == 4)
	guard case .ops(let clearOps)? = effects.last else {
		Issue.record("the clear record must decode to .ops")
		return
	}
	#expect(clearOps == [.remove(ElementID(ProbeIslandIDs.item("k0"))),
	                     .remove(ElementID(ProbeIslandIDs.item("k1"))),
	                     .remove(ElementID(ProbeIslandIDs.item("k2")))])
}

@Test("core.decodePendingOps: reads, never drains — takeOps still serves the batch")
func coreDecodeDoesNotDrain() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.renderRegion(input: _rtTextBytes(#"{"name":"probe","args":{}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))

	let effectsBefore = core.decodePendingOps()
	#expect(effectsBefore.count == 1)
	// the batch is still queued: a decode is a read, the drain is takeOps.
	let batch = core.takeOps()
	#expect(batch == _rtText("probe-counter", "1"))
	#expect(core.decodePendingOps().isEmpty)
	#expect(core.takeOps() == nil)
}

@Test("core.decodePendingOps: empty queue decodes to no effects")
func coreDecodeEmpty() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"hover","key":"probe-inc"}"#)) // noop — nothing queues
	#expect(core.decodePendingOps().isEmpty)
}

// ── the statics' unbound contract (host builds bind no runtime) ───────────

@Test("IslandRuntime<ProbeIsland>.encodedState()/decodePendingOps() report the drained surface on host")
func staticsUnboundContract() {
	// host/native builds never call the bind shim, so nothing is ever bound —
	// the accessors return the recorded drained values (d-docs "why not
	// verbatim" §2: an untethered surface holds no retained state).
	#expect(IslandRuntime<ProbeIsland>.encodedState() == [])
	#expect(IslandRuntime<ProbeIsland>.decodePendingOps().isEmpty)
}
