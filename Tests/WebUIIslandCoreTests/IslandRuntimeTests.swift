import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - DX-1 behavior-equivalence (CONTINUUM_DX §2.1)
//
// the recorded probe fixtures live in designer/probes/c-ops.mjs (15 assertions,
// byte-exact record-v1 batches). this suite drives the SAME script through the
// runtime slice (`IslandRuntimeCore<ProbeIsland>` — the exact code the wasm
// exports execute) and asserts the same byte-exact frames/batches. green here
// + c-ops 15/15 on the converted wasm artifact = the conversion is
// behavior-equivalent to the hand-written probe.
//
// the fixture builders below mirror c-ops.mjs's HotOpCodec fixtures (record-v1,
// little-endian, before-sentinel 0xffff) so both sides share one byte language.

// ── record-v1 fixture builders (mirror c-ops.mjs verbatim semantics) ──────

func _rtU16(_ n: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: n & 0xff), UInt8(truncatingIfNeeded: (n >> 8) & 0xff)] }
func _rtU32(_ n: Int) -> [UInt8] {
	[UInt8(truncatingIfNeeded: n & 0xff), UInt8(truncatingIfNeeded: (n >> 8) & 0xff),
	 UInt8(truncatingIfNeeded: (n >> 16) & 0xff), UInt8(truncatingIfNeeded: (n >> 24) & 0xff)]
}
func _rtIDF(_ s: String) -> [UInt8] { let b = Array(s.utf8); return _rtU16(b.count) + b }
func _rtBulk(_ s: String) -> [UInt8] { let b = Array(s.utf8); return _rtU32(b.count) + b }
func _rtText(_ id: String, _ value: String) -> [UInt8] { [1, 1] + _rtIDF(id) + _rtBulk(value) }
func _rtRemove(_ id: String) -> [UInt8] { [1, 4] + _rtIDF(id) }
func _rtInsert(_ parent: String, _ before: String?, _ html: String) -> [UInt8] {
	[1, 3] + _rtIDF(parent) + (before == nil ? [0xff, 0xff] : _rtIDF(before!)) + _rtBulk(html)
}
func _rtTextBytes(_ text: String) -> [UInt8] { Array(text.utf8) }

/// the c-ops script's `invoke` analog: decode the mount/event envelope text.
func _rtEnvelope(_ core: inout IslandRuntimeCore<ProbeIsland>, render: String) -> [UInt8] {
	core.renderRegion(input: _rtTextBytes(render)) ?? []
}

/// drain-all analog: pull batches until empty.
func _rtDrain(_ core: inout IslandRuntimeCore<ProbeIsland>) -> [[UInt8]] {
	var batches: [[UInt8]] = []
	while let batch = core.takeOps() { batches.append(batch) }
	return batches
}

// ── the probe script's running-state sequence, byte-exact ─────────────────

@Test("mount: region html stamps counter 0, renders=1; stream empty")
func runtimeMount() {
	var core = IslandRuntimeCore<ProbeIsland>()
	let htmlBytes = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	let html = String(decoding: htmlBytes, as: UTF8.self)
	#expect(html.contains(#"id="probe-counter""#))
	#expect(html.contains(#"class="island__counter">0<"#))
	#expect(html.contains(#"data-island-renders="1""#))
	#expect(core.renderCount == 1)
	#expect(_rtDrain(&core).isEmpty)
}

@Test("key ArrowUp → text('probe-counter','1') record — byte-exact hard fixture")
func runtimeArrowUpByteExact() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.renderRegion(input: _rtTextBytes(#"{"name":"probe","args":{}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	let batch = core.takeOps()
	let expected: [UInt8] = [1, 1, 13, 0, 0x70, 0x72, 0x6f, 0x62, 0x65, 0x2d, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x65, 0x72, 1, 0, 0, 0, 0x31]
	#expect(batch == expected)
	#expect(core.takeOps() == nil)
	#expect(core.probe.counter == 1)
}

@Test("two ArrowDown events → one back-to-back batch (text 0, text -1)")
func runtimeArrowDownTwice() {
	// c-ops running state: ArrowUp first (counter 0 → 1), then two ArrowDowns.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	_ = core.takeOps() // c-ops drains each event's batch before the next
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	let batches = _rtDrain(&core)
	#expect(batches.count == 1)
	#expect(batches[0] == _rtText("probe-counter", "0") + _rtText("probe-counter", "-1"))
}

@Test("click probe-inc → text('probe-counter','0'); input → insert escaped row byte-exact")
func runtimeClickAndInsert() {
	// c-ops running state: ArrowUp, ArrowDown ×2 (counter -1), then click inc → 0.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = _rtDrain(&core)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-inc"}"#))
	#expect(core.takeOps() == _rtText("probe-counter", "0"))

	let itemValue = "todo <one>"
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"\#(itemValue)"}}"#))
	let expectedAdd = _rtInsert("probe-list", nil, #"<li id="probe-item-k0" class="island__item">todo &lt;one&gt;</li>"#)
	#expect(core.takeOps() == expectedAdd)
}

@Test("two queued inserts drain as ONE back-to-back batch (records contiguous)")
func runtimeMultiRecord() {
	// c-ops running state: ArrowUp, ArrowDown ×2, click inc (counter 0), then
	// input "todo <one>" (k0); now two more inputs queue k1, k2.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-inc"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"todo <one>"}}"#))
	_ = _rtDrain(&core)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"second"}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"third"}}"#))
	let batches = _rtDrain(&core)
	#expect(batches.count == 1)
	let expected = _rtInsert("probe-list", nil, #"<li id="probe-item-k1" class="island__item">second</li>"#)
		+ _rtInsert("probe-list", nil, #"<li id="probe-item-k2" class="island__item">third</li>"#)
	#expect(batches[0] == expected)
}

@Test("unknown/malformed events emit no ops (drain is empty)")
func runtimeNoopEvents() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"hover","key":"probe-inc"}"#))
	_ = core.onEvent(input: _rtTextBytes("this is not json"))
	_ = core.onEvent(input: _rtTextBytes(#"{"key":"ArrowUp"}"#))
	#expect(_rtDrain(&core).isEmpty)
	#expect(core.probe.counter == 0)
}

@Test("click probe-clear → remove k0,k1,k2 as one back-to-back batch")
func runtimeClear() {
	// c-ops running state through the multi-record: counter 0, items k0,k1,k2.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-inc"}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"todo <one>"}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"second"}}"#))
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"third"}}"#))
	_ = _rtDrain(&core)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-clear"}"#))
	let batches = _rtDrain(&core)
	let expected = _rtRemove("probe-item-k0") + _rtRemove("probe-item-k1") + _rtRemove("probe-item-k2")
	#expect(batches.count == 1)
	#expect(batches[0] == expected)
	#expect(core.probe.items.isEmpty)
}

@Test("state channel: save → (fresh core) restore → remount continues (RETAINED_OPEN)")
func runtimeStateChannel() {
	// replicate the c-ops.mjs running state through the save point exactly,
	// so the saved snapshot fixture is the recorded one.
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = _rtEnvelope(&core, render: #"{"name":"probe","args":{}}"#)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))     // 1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))   // 0
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowDown"}"#))   // -1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-inc"}"#)) // 0
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"todo <one>"}}"#)) // k0
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"second"}}"#))     // k1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"third"}}"#))      // k2
	_ = _rtDrain(&core)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"click","key":"probe-clear"}"#)) // removes k0,k1,k2; nextItemKey=3
	_ = _rtDrain(&core)
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))       // counter → 1
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"input","key":"probe-field","data":{"value":"stateful"}}"#)) // k3
	_ = _rtDrain(&core)
	#expect(core.probe.nextItemKey == 4)
	let snapshotBytes = core.stateSave()
	let snapshotText = String(decoding: snapshotBytes, as: UTF8.self)
	#expect(snapshotText.contains("\"counter\":1"))
	#expect(snapshotText.contains("\"value\":\"stateful\""))
	#expect(snapshotText.contains("\"key\":\"k3\""))
	#expect(snapshotText.contains("\"items\":["))
	#expect(!snapshotText.contains("\"k0\""))

	// a remount = a fresh core (retained state wiped) + restore + render.
	var fresh = IslandRuntimeCore<ProbeIsland>()
	let ack = fresh.stateRestore(input: snapshotBytes)
	let ackText = String(decoding: ack ?? [], as: UTF8.self)
	#expect(ackText.contains("\"ok\":true"))
	#expect(ackText.contains("\"restored\":\(snapshotText.utf8.count)"))
	#expect(fresh.restoredBytes == snapshotBytes.count)

	let htmlBytes = _rtEnvelope(&fresh, render: #"{"name":"probe","args":{}}"#)
	let html = String(decoding: htmlBytes, as: UTF8.self)
	#expect(html.contains(#"class="island__counter">1<"#))
	#expect(html.contains(#"id="probe-item-k3""#))
	#expect(html.contains(">stateful<"))

	// the restored island still emits ops against the live ids
	_ = fresh.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	#expect(fresh.takeOps() == _rtText("probe-counter", "2"))
}

@Test("garbage restore keeps live state and leaves the stream empty")
func runtimeGarbageRestore() {
	var core = IslandRuntimeCore<ProbeIsland>()
	_ = core.onEvent(input: _rtTextBytes(#"{"type":"key","key":"ArrowUp"}"#))
	_ = _rtDrain(&core)
	let ack = core.stateRestore(input: _rtTextBytes("garbage"))
	#expect(ack != nil)
	#expect(core.probe.counter == 1) // live state not wiped
	#expect(_rtDrain(&core).isEmpty)
}

// ── runtime dispatch == hand-written reduceOps (the equivalence core) ─────

@Test("runtime onEvent dispatch is byte-identical to the hand-written reduceOps path")
func runtimeDispatchMatchesHandWritten() {
	// every op-producing event in the vocabulary: run BOTH paths side-by-side
	// on identical starting states and compare the streamed batch bytes.
	let events: [String] = [
		#"{"type":"key","key":"ArrowUp"}"#,
		#"{"type":"key","key":"ArrowDown"}"#,
		#"{"type":"click","key":"probe-inc"}"#,
		#"{"type":"click","key":"probe-dec"}"#,
		#"{"type":"input","key":"probe-field","data":{"value":"alpha"}}"#,
		#"{"type":"click","key":"probe-clear"}"#,
	]
	var runtime = IslandRuntimeCore<ProbeIsland>()
	var hand: (probe: ProbeState, records: [[UInt8]]) = (ProbeState(), [])
	func handWritten(_ text: String) {
		let action = ProbeIsland.decodeEvent(json: text)
		var state = hand.probe
		let ops = ProbeIsland.reduceOps(state: &state, action: action)
		hand.probe = state
		if !ops.isEmpty, let record = try? HotOpCodec.encodeBatch(ops) {
			hand.records.append(record)
		}
	}
	var runtimeRecords: [[UInt8]] = []
	func runtimeStep(_ text: String) {
		_ = runtime.onEvent(input: _rtTextBytes(text))
		while let batch = runtime.takeOps() { runtimeRecords.append(batch) }
	}

	for (i, event) in events.enumerated() {
		runtimeStep(event)
		handWritten(event)
		#expect(runtime.probe == hand.probe, "state diverged at event \(i): \(event)")
		for (r, h) in zip(runtimeRecords, hand.records) {
			#expect(r == h, "record diverged at event \(i): \(event)")
		}
		#expect(runtimeRecords.count == hand.records.count)
	}
}
