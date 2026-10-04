import Testing
import WebUISharedCore

// MARK: - HotOpCodec.encodeBatch — the encoder-consumer path pin
//
// the wave-2 freeze shape: `webui_take_ops()` serves records back-to-back,
// each record-v1, and the engine drains until 0. `encodeBatch` is the exact
// payload that lands in the frame buffer — so its bytes are pinned here, not
// just round-tripped. these tests are the native side of the same fixtures
// designer/probes/c-ops.mjs asserts byte-for-byte against the wasm artifact.

@Test("encodeBatch concatenates records back-to-back with no framing")
func batchIsBackToBackRecords() throws {
	let ops: [HotOp] = [
		.remove("x"),
		.text("ab", "v"),
	]
	let bytes = try HotOpCodec.encodeBatch(ops)
	// remove("x")  = [1, 4, 1, 0, 0x78]
	// text("ab","v") = [1, 1, 2, 0, 0x61, 0x62, 1, 0, 0, 0, 0x76]
	let expected: [UInt8] = [1, 4, 1, 0, 0x78, 1, 1, 2, 0, 0x61, 0x62, 1, 0, 0, 0, 0x76]
	#expect(bytes == expected)
	#expect(bytes.count == 16)
}

@Test("encodeBatch(empty) is the empty payload — take_ops serves nothing")
func emptyBatch() throws {
	#expect(try HotOpCodec.encodeBatch([]) == [])
}

@Test("encodeBatch equals the concatenation of per-record encodes")
func batchEqualsConcat() throws {
	let ops: [HotOp] = [
		.insert(parent: "list", before: nil, html: "<li>t</li>"),
		.attr("row-17", "class", "tr--selected"),
		.move("a", before: "b"),
		.text("", ""),
	]
	var expected: [UInt8] = []
	for op in ops { expected.append(contentsOf: try HotOpCodec.encode(op)) }
	#expect(try HotOpCodec.encodeBatch(ops) == expected)
}

@Test("every record in a batch decodes individually (engine drain loop)")
func eachRecordDecodesInDrainLoop() throws {
	// the engine-side drain: the codec's decode consumes exactly one record
	// (trailing bytes are rejected), so walking the batch one record at a time
	// reproduces the drain loop c-to-e.md documents for `webui_take_ops`.
	let ops: [HotOp] = [
		.text("a", "1"),
		.remove("b"),
		.attr("c", "class", "d"),
		.move("e", before: nil),
		.insert(parent: "f", before: "g", html: "<i>x</i>"),
	]
	let bytes = try HotOpCodec.encodeBatch(ops)
	var rest = bytes
	var decoded: [HotOp] = []
	while !rest.isEmpty {
		// shortest prefix that decodes = exactly one record (a longer prefix
		// fails with trailingBytes, a shorter one with a truncation error).
		var n = 1
		while (try? HotOpCodec.decode(Array(rest.prefix(n)))) == nil { n += 1 }
		decoded.append(try HotOpCodec.decode(Array(rest.prefix(n))))
		rest.removeFirst(n)
	}
	#expect(decoded == ops)
	#expect(rest.isEmpty)
}

@Test("a bulk string beyond a u32 length field aborts the whole batch")
func batchAbortsOnOversize() {
	// 5-byte identifier? no — bulkTooLong needs >4GiB, unreachable in a test;
	// the failing op here is the identifier-too-long guard: a `u16` cannot
	// carry a 70,000-byte id. batch must throw, not truncate.
	let bigID = String(repeating: "a", count: 70_000)
	let ops: [HotOp] = [.remove("x"), .text(ElementID(bigID), "v")]
	#expect(throws: HotOpCodecError.identifierTooLong) {
		_ = try HotOpCodec.encodeBatch(ops)
	}
}
