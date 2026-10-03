import Testing
import WebUISharedCore

// MARK: - Continuum codec tests (record format v1, DESKTOP_GRADE §t2.3)
//
// the scalar-clean op-stream codec: every op shape round-trips; edge cases are
// the empty string, the 0xffff `before` sentinel, and multi-byte utf-8 ids.

@Test("every hot op shape round-trips")
func everyHotOpRoundTrips() throws {
	let ops: [HotOp] = [
		.text("row-17", "42"),
		.attr("row-17", "class", "tr--selected"),
		.insert(parent: "list", before: nil, html: "<li>tail</li>"),
		.insert(parent: "list", before: "anchor-2", html: "<li>mid</li>"),
		.remove("stale"),
		.move("row-3", before: nil),
		.move("row-3", before: "row-9"),
	]
	for op in ops {
		let bytes = try HotOpCodec.encode(op)
		let decoded = try HotOpCodec.decode(bytes)
		#expect(decoded == op)
		#expect(bytes[0] == HotOpCodec.formatVersion)
	}
}

@Test("empty strings round-trip on every string-carrying op")
func emptyStringsRoundTrip() throws {
	let text = HotOp.text("e", "")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(text)) == text)
	let attr = HotOp.attr("e", "class", "")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(attr)) == attr)
	let insert = HotOp.insert(parent: "e", before: "b", html: "")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(insert)) == insert)
}

@Test("empty element ids round-trip")
func emptyIDsRoundTrip() throws {
	let op = HotOp.text("", "value")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(op)) == op)
}

@Test("multi-byte utf-8 ids and values round-trip")
func multiByteUTF8RoundTrip() throws {
	// 3-byte sequences (CJK), 4-byte (emoji), and a 2-byte (é) mixed into ids.
	let op = HotOp.text("row-東京-😀-café", "値☕")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(op)) == op)
	let attr = HotOp.attr("漢字", "class", "wéird-値")
	#expect(try HotOpCodec.decode(HotOpCodec.encode(attr)) == attr)
}

@Test("insert and move: nil before encodes as the 0xffff sentinel")
func beforeEndSentinel() throws {
	let moveBytes = try HotOpCodec.encode(.move("a", before: nil))
	// version(1) · opcode(5) · id-len(u16=1) · id("a") · before(u16)
	#expect(Array(moveBytes.suffix(2)) == [0xff, 0xff])

	let insertBytes = try HotOpCodec.encode(.insert(parent: "p", before: nil, html: "<i>x</i>"))
	// version(1) · opcode(3) · id-len(u16=1) · id("p") · before(u16 sentinel) · html-len(u32) · html
	#expect(Array(insertBytes[5..<7]) == [0xff, 0xff])
}

@Test("non-nil before in insert round-trips (marker is length, not sentinel)")
func beforeLengthNotSentinel() throws {
	// an anchor whose utf-8 length is 0xffff can never be expressed (u16 max is
	// the sentinel); an anchor of length 4 must not be confused with it.
	let op = HotOp.insert(parent: "p", before: "abcd", html: "<i>x</i>")
	let bytes = try HotOpCodec.encode(op)
	#expect(Array(bytes[5..<7]) == [4, 0]) // u16 LE length of "abcd"
	#expect(try HotOpCodec.decode(bytes) == op)
}

@Test("record layout is byte-exact for a text op")
func textLayoutByteExact() throws {
	let bytes = try HotOpCodec.encode(.text("ab", "v"))
	// version(1) · opcode text(1) · id-len u16 LE (=2) · "ab" · value-len u32 LE (=1) · "v"
	#expect(bytes == [1, 1, 2, 0, 0x61, 0x62, 1, 0, 0, 0, 0x76])
}

@Test("unsupported version is rejected")
func unsupportedVersion() throws {
	let bytes = try HotOpCodec.encode(.remove("x"))
	var bad = bytes
	bad[0] = 2
	#expect(throws: HotOpCodecError.unsupportedVersion(2)) {
		_ = try HotOpCodec.decode(bad)
	}
}

@Test("unknown opcode is rejected")
func unknownOpcode() throws {
	var bytes = try HotOpCodec.encode(.remove("x"))
	bytes[1] = 99
	#expect(throws: HotOpCodecError.unknownOpcode(99)) {
		_ = try HotOpCodec.decode(bytes)
	}
}

@Test("truncated records throw instead of trapping")
func truncatedRecords() throws {
	let full = try HotOpCodec.encode(.attr("abcdef", "class", "value"))
	for cut in 0..<full.count {
		#expect(throws: (any Error).self) {
			_ = try HotOpCodec.decode(Array(full.prefix(cut)))
		}
	}
	#expect(throws: (any Error).self) {
		_ = try HotOpCodec.decode([])
	}
}

@Test("trailing bytes after one record are rejected")
func trailingBytesRejected() throws {
	var bytes = try HotOpCodec.encode(.remove("x"))
	bytes.append(0xAA)
	#expect(throws: HotOpCodecError.trailingBytes) {
		_ = try HotOpCodec.decode(bytes)
	}
}

@Test("invalid utf-8 in an id decodes to U+FFFD, never crashes")
func invalidUTF8BecomesReplacement() throws {
	// version(1) · opcode text(1) · id-len u16 LE (=2) + [0xC3, 0x28] (lone lead
	// byte 0xC3 followed by '(' — not a valid continuation) · value-len u32 + "x"
	let bytes: [UInt8] = [1, 1, 2, 0, 0xC3, 0x28, 1, 0, 0, 0, 0x78]
	let op = try HotOpCodec.decode(bytes)
	guard case .text(let id, "x") = op else {
		Issue.record("expected a text op")
		return
	}
	#expect(id.raw == "\u{FFFD}(")
}

// MARK: - seam vocabulary shape pins

@Test("element and attribute ids are string-literally constructible and hashable")
func seamAddresses() {
	let id: ElementID = "row-1"
	#expect(ElementID("row-1") == id)
	#expect(id.raw == "row-1")
	let name: AttributeName = "class"
	#expect(AttributeName("class") == name)
	#expect(Set([id, ElementID("row-1")]).count == 1)
}

@Test("capability wire names match the abi table")
func capabilityWireNames() {
	#expect(FrameSchedule.wireName == "frame_schedule")
	#expect(InputSubscription.wireName == "input_subscribe")
	#expect(SurfaceAcquisition.wireName == "surface_acquire")
	#expect(StatePersistence.wireName == "state_persist")
	#expect(ClockCapability.wireName == "clock")
	#expect(LogCapability.wireName == "log")
}

@Test("hot state and action refine the seam protocols natively")
func hotStateAndActionRefine() {
	struct CounterState: HotState { var count = 0 }
	struct TickAction: HotAction { var n = 1 }
	let state = CounterState()
	#expect(state.count == 0)
	let action = TickAction()
	#expect(action.n == 1)
}
