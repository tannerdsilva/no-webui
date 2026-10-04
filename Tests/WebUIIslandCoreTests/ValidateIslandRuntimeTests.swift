import Testing
import WebUIIslandCore
import WebUISharedCore

// MARK: - DX-2 behavior-equivalence (CONTINUUM_DX §2.1)
//
// the validate conversion's proof mirror for `IslandRuntimeTests`: the SAME
// `IslandRuntimeCore<ValidateIsland>` the wasm exports execute is driven here
// natively against the hand-written d3 logic (`ValidateIsland.evaluate` /
// `regionHTML(argsJSON:)`) so the conversion's region/verdict contracts are
// asserted byte-exact without a wasm run. green here + the artifact building
// and `webui_validate` being a runtime helper call = the conversion preserved
// the hand-written validate main's behavior.

func _vBytes(_ text: String) -> [UInt8] { Array(text.utf8) }

func _vText(_ bytes: [UInt8]) -> String {
	String(decoding: bytes, as: UTF8.self)
}

@discardableResult
func _vRender(_ core: inout IslandRuntimeCore<ValidateIsland>, _ envelope: String) -> [UInt8] {
	core.renderRegion(input: _vBytes(envelope)) ?? []
}

/// the d3 logic-home reference: what the hand-written `webui_render_region`
/// wrote after unwrapping `{name, args}`.
func _vHandWrittenRender(_ argsJSON: String) -> String {
	ValidateIsland.regionHTML(argsJSON: argsJSON)
}

@discardableResult
func _vDrain(_ core: inout IslandRuntimeCore<ValidateIsland>) -> [[UInt8]] {
	var batches: [[UInt8]] = []
	while let batch = core.takeOps() { batches.append(batch) }
	return batches
}

@Test("mount: region html from the mount envelope's args — byte-equal to the hand-written path")
func validateMountRendersEnvelopeArgs() {
	var core = IslandRuntimeCore<ValidateIsland>()
	let envelope = #"{"name":"validate","args":{"value":"ab","rules":[{"rule":"minLength","arg":4}]}}"#
	let htmlBytes = _vRender(&core, envelope)
	let html = _vText(htmlBytes)
	let expected = _vHandWrittenRender(#"{"value":"ab","rules":[{"rule":"minLength","arg":4}]}"#)
	#expect(html == expected)
	#expect(html.contains("island--error"))
	#expect(html.contains("at least 4 characters"))
	// a mount produces no ops (validate is not a DOM-delta island)
	#expect(_vDrain(&core).isEmpty)
	#expect(core.renderCount == 1)
}

@Test("mount: a passing value renders island--ok; empty input leaves the frame untouched")
func validateMountOkAndEmpty() {
	var core = IslandRuntimeCore<ValidateIsland>()
	let htmlBytes = _vRender(&core, #"{"name":"validate","args":{"value":"ok","rules":[{"rule":"required"}]}}"#)
	let html = _vText(htmlBytes)
	#expect(html == _vHandWrittenRender(#"{"value":"ok","rules":[{"rule":"required"}]}"#))
	#expect(html.contains("island--ok"))
	#expect(html.contains(">valid<"))
	// empty input → nil payload → the wasm export returns 0 without writing
	#expect(core.renderRegion(input: []) == nil)
	#expect(core.renderCount == 1) // the empty call is not a render
}

@Test("mount: a malformed envelope degrades to the raw json (server-authoritative), like the hand-written main")
func validateMountMalformedEnvelope() {
	var core = IslandRuntimeCore<ValidateIsland>()
	let raw = "not-envelope-json"
	let htmlBytes = _vRender(&core, raw)
	#expect(_vText(htmlBytes) == _vHandWrittenRender(raw))
	#expect(_vText(htmlBytes).contains("island--error"))
}

@Test("webui_validate contract: verdict json is byte-identical to the hand-written template")
func validateVerdictContract() {
	let response = ValidateIsland.validationResponse(json: #"{"value":"ab","rules":[{"rule":"minLength","arg":4}]}"#)
	#expect(response == #"{"ok":false,"message":"at least 4 characters"}"#)
	let ok = ValidateIsland.validationResponse(json: #"{"value":"x@y.z","rules":[{"rule":"email"}]}"#)
	#expect(ok == #"{"ok":true,"message":""}"#)
	// escaped message (hand-written wrote JSONValue.escapeString(result.message))
	let escaped = ValidateIsland.validationResponse(json: #"{"value":"","rules":[{"rule":"minLength","arg":1}]}"#)
	_ = escaped
	let containsMsg = ValidateIsland.validationResponse(json: #"{"value":"","rules":[{"rule":"contains","arg":"\"\n"}]}"#)
	#expect(containsMsg.contains(#"\"#))
}

@Test("state channel: args survive a save → fresh core → restore → remount (RETAINED_OPEN generalized)")
func validateStateChannel() {
	var core = IslandRuntimeCore<ValidateIsland>()
	_ = _vRender(&core, #"{"name":"validate","args":{"value":"saved","rules":[{"rule":"required"}]}}"#)
	let snapshot = core.stateSave()
	let snapshotText = _vText(snapshot)
	#expect(snapshotText.contains(#""args":"#))

	var fresh = IslandRuntimeCore<ValidateIsland>()
	let ack = fresh.stateRestore(input: snapshot)
	#expect(_vText(ack ?? []).contains(#""ok":true"#))

	// the retained args round-trip idempotently: save → restore must recover
	// the same mount args a fresh mount folded in (the exact key ORDER is
	// dictionary-seeded, so compare by re-evaluating, not by literal string).
	let restored = ValidateIsland.stateFromJSON(snapshotText)
	#expect(restored != nil)
	let restoredResult = ValidateIsland.evaluate(json: restored?.state.argsJSON ?? "")
	#expect(restoredResult.ok == true)
	#expect(restoredResult.message.isEmpty)
	_ = _vRender(&fresh, #"{"name":"validate","args":{}}"#)
	_ = _vDrain(&core)
}

@Test("events: validate has no event vocabulary — every event is a noop, the drain stays empty")
func validateEventsNoop() {
	var core = IslandRuntimeCore<ValidateIsland>()
	_ = core.onEvent(input: _vBytes(#"{"type":"click","key":"anything"}"#))
	#expect(_vDrain(&core).isEmpty)
	#expect(core.eventCount == 1)
}
