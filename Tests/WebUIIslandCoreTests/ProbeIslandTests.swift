import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - ProbeIsland — typed state/actions/reduce (t2.5 wave 2)
//
// native parity for what the wasm island runs: decodeEvent → reduce → ops
// (encodeBatch) is pinned here, then asserted byte-for-byte against the wasm
// artifact in designer/probes/c-ops.mjs. reduce is pure and placement-free, so
// this native suite IS the logic the wasm executable executes.

@Test("increment/decrement mutate the counter and emit a text op on the counter id")
func counterOps() throws {
	var state = ProbeState()
	var ops = ProbeIsland.reduceOps(state: &state, action: .increment(3))
	#expect(state.counter == 3)
	#expect(ops == [.text("probe-counter", "3")])

	ops = ProbeIsland.reduceOps(state: &state, action: .decrement(1))
	#expect(state.counter == 2)
	#expect(ops == [.text("probe-counter", "2")])

	// the op bytes are the take_ops payload for a single event
	let bytes = try HotOpCodec.encodeBatch(ops)
	#expect(try HotOpCodec.decode(bytes) == .text("probe-counter", "2"))
}

@Test("addItem appends a keyed list row via insert and assigns stable keys")
func addItemOps() throws {
	var state = ProbeState()
	let ops = ProbeIsland.reduceOps(state: &state, action: .addItem("hello"))
	#expect(state.items == [ProbeListItem(key: "k0", value: "hello")])
	#expect(state.nextItemKey == 1)
	guard case .insert(let parent, let before, let html) = ops[0] else {
		Issue.record("expected an insert op, got \(ops)")
		return
	}
	#expect(parent == "probe-list")
	#expect(before == nil)
	#expect(html == "<li id=\"probe-item-k0\" class=\"island__item\">hello</li>")
}

@Test("addItem escapes html in the inserted row's value")
func addItemEscapes() throws {
	var state = ProbeState()
	let ops = ProbeIsland.reduceOps(state: &state, action: .addItem("<script>alert(1)</script>"))
	guard case .insert(_, _, let html) = ops[0] else {
		Issue.record("expected an insert op")
		return
	}
	#expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
	#expect(!html.contains("<script>"))
}

@Test("clear emits one remove per item and empties the list")
func clearOps() throws {
	var state = ProbeState()
	_ = ProbeIsland.reduceOps(state: &state, action: .addItem("a"))
	_ = ProbeIsland.reduceOps(state: &state, action: .addItem("b"))
	let ops = ProbeIsland.reduceOps(state: &state, action: .clear)
	#expect(state.items.isEmpty)
	#expect(ops == [.remove("probe-item-k0"), .remove("probe-item-k1")])
}

@Test("noop emits no ops and leaves state untouched")
func noopEmitsNothing() throws {
	var state = ProbeState()
	let ops = ProbeIsland.reduceOps(state: &state, action: .noop)
	#expect(ops.isEmpty)
	#expect(ProbeIsland.reduce(state: &state, action: .noop).isEmpty)
}

// MARK: events in — the {type, key, data} v1 decoder

@Test("key events map to counter actions")
func decodeKeyEvents() {
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"key","key":"ArrowUp"}"#) == .increment(1))
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"key","key":"ArrowDown"}"#) == .decrement(1))
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"key","key":"Enter"}"#) == .noop)
}

@Test("click events map to the probe controls")
func decodeClickEvents() {
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"click","key":"probe-inc"}"#) == .increment(1))
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"click","key":"probe-dec"}"#) == .decrement(1))
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"click","key":"probe-clear"}"#) == .clear)
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"click","key":"probe-other"}"#) == .noop)
}

@Test("input events carry the field value through data")
func decodeInputEvents() {
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"input","key":"probe-field","data":{"value":"todo one"}}"#) == .addItem("todo one"))
	// empty value → nothing to add
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"input","key":"probe-field","data":{"value":""}}"#) == .noop)
	// other field ids are not routed
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"input","key":"other","data":{"value":"x"}}"#) == .noop)
}

@Test("malformed and unknown payloads degrade to noop")
func decodeMalformed() {
	#expect(ProbeIsland.decodeEvent(json: "not json") == .noop)
	#expect(ProbeIsland.decodeEvent(json: #"{"key":"ArrowUp"}"#) == .noop)
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"hover","key":"probe-inc"}"#) == .noop)
	#expect(ProbeIsland.decodeEvent(json: #"{"type":"key","data":{}}"#) == .noop)
}

// MARK: state channel round-trip

@Test("stateToJSON serializes counter, keys, and list in order; parse restores exactly")
func stateRoundTrip() throws {
	var state = ProbeState()
	_ = ProbeIsland.reduceOps(state: &state, action: .addItem("first"))
	_ = ProbeIsland.reduceOps(state: &state, action: .addItem("second"))
	_ = ProbeIsland.reduceOps(state: &state, action: .increment(7))

	let json = ProbeIsland.stateToJSON(state: state, renderCount: 3, eventCount: 12).serialize()
	guard let restored = ProbeIsland.stateFromJSON(json) else {
		Issue.record("state round-trip failed to parse")
		return
	}
	#expect(restored.state == state)
	#expect(restored.renderCount == 3)
	#expect(restored.eventCount == 12)
}

@Test("stateFromJSON rejects malformed snapshots (restore never wipes live state)")
func stateFromMalformed() {
	#expect(ProbeIsland.stateFromJSON("not json") == nil)
	#expect(ProbeIsland.stateFromJSON(#"{"renderCount":1}"#) == nil)
	#expect(ProbeIsland.stateFromJSON(#"{"probe":"oops"}"#) == nil)
	// unknown fields are ignored; known ones win
	let parsed = ProbeIsland.stateFromJSON(#"{"probe":{"counter":4,"nextItemKey":9,"items":[]},"renderCount":1,"other":true}"#)
	#expect(parsed?.state.counter == 4)
	#expect(parsed?.state.nextItemKey == 9)
	#expect(parsed?.renderCount == 1)
}

// MARK: mount html

@Test("region html stamps the state and agrees with the reduce op targets")
func probeRegionHTML() {
	var state = ProbeState()
	_ = ProbeIsland.reduceOps(state: &state, action: .increment(5))
	_ = ProbeIsland.reduceOps(state: &state, action: .addItem("a<b"))
	let html = ProbeIsland.regionHTML(state: state, renderCount: 1, eventCount: 2)
	#expect(html.contains("data-island-renders=\"1\""))
	#expect(html.contains("data-island-events=\"2\""))
	#expect(html.contains("id=\"probe-counter\""))
	#expect(html.contains("class=\"island__counter\">5<"))
	#expect(html.contains("id=\"probe-item-k0\""))
	#expect(html.contains("a&lt;b"))
	#expect(html.contains("id=\"probe-list\""))
}

// MARK: the full loop — decode → reduce → batch → drain (native parity)

@Test("event to take_ops payload: decodeEvent → reduce → encodeBatch (byte-exact)")
func eventToOpsBytes() throws {
	// a single ArrowUp keystroke, as the engine would deliver it
	let action = ProbeIsland.decodeEvent(json: #"{"type":"key","key":"ArrowUp"}"#)
	var state = ProbeState()
	let ops = ProbeIsland.reduceOps(state: &state, action: action)
	let payload = try HotOpCodec.encodeBatch(ops)
	// version(1) opcode text(1) id-len(u16 LE = 13) "probe-counter" value-len(u32 LE = 1) "1"
	let expected: [UInt8] = [1, 1, 13, 0, 0x70, 0x72, 0x6f, 0x62, 0x65, 0x2d, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x65, 0x72, 1, 0, 0, 0, 0x31]
	#expect(payload == expected)
	#expect(state.counter == 1)
}
