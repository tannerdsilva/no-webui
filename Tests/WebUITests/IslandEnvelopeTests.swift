import Testing
import WebUIIslandWire
import WebUIChartSpec

// the envelope's job: a value goes in, a base64 frame comes out, and only a
// frame with the right magic, the right version, a consistent declared
// length, valid armor, and a payload the codec consumes *exactly* comes back
// out as a value. every rejection here is a region that keeps its
// server-rendered fallback.

@Suite("island envelope")
struct IslandEnvelopeTests {
	private static var spec: ChartSpec {
		ChartSpec(title: "revenue — q3 ✓", values: [0, 1.5, 2, 1000])
	}

	@Test("a chart spec survives the frame round trip")
	func roundTrip() {
		let decoded: ChartSpec? = IslandEnvelope.decode(IslandEnvelope.encode(Self.spec))
		#expect(decoded == Self.spec)
	}

	@Test("an empty series and an empty title round-trip")
	func emptySpec() {
		let spec = ChartSpec(title: "", values: [])
		let decoded: ChartSpec? = IslandEnvelope.decode(IslandEnvelope.encode(spec))
		#expect(decoded == spec)
	}

	@Test("nan bit patterns survive (the codec moves bits, not numbers)")
	func nanPayload() {
		let spec = ChartSpec(title: "x", values: [.nan, 1])
		let decoded: ChartSpec? = IslandEnvelope.decode(IslandEnvelope.encode(spec))
		#expect(decoded?.values.count == 2)
		#expect(decoded?.values.first?.isNaN == true)
		#expect(decoded?.values.last == 1)
	}

	@Test("a foreign version is refused")
	func wrongVersion() {
		let armored = Self.frame(payload: Self.payloadBytes(Self.spec), version: 2)
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("a foreign magic is refused")
	func wrongMagic() {
		let armored = Self.frame(payload: Self.payloadBytes(Self.spec), magic: [0x57, 0x55, 0x49, 0x32])
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("a declared length that disagrees with the buffer is refused")
	func lengthMismatch() {
		let payload = Self.payloadBytes(Self.spec)
		let armored = Self.frame(payload: payload, declared: payload.count + 1)
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("a header shorter than twelve bytes is refused")
	func shortHeader() {
		let armored = Self.armor([0x57, 0x55])
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("a payload with trailing bytes is refused (exact consumption)")
	func trailingBytes() {
		var payload = Self.payloadBytes(Self.spec)
		payload.append(0x00)
		let armored = Self.frame(payload: payload)
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("garbage armor is refused")
	func garbageArmor() {
		let decoded: ChartSpec? = IslandEnvelope.decode("not!base64!!")
		#expect(decoded == nil)
	}

	@Test("a title longer than the buffer is refused")
	func titleOverrun() {
		let armored = Self.frame(payload: [0x00, 0x0A, 0x41, 0x42])
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("an invalid utf-8 title is refused")
	func invalidUTF8Title() {
		// title length 2, bytes C3 28 — a truncated two-byte sequence
		let armored = Self.frame(payload: [0x00, 0x02, 0xC3, 0x28, 0x00, 0x00])
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("a value count that leaves a remainder is refused")
	func valueRemainder() {
		// empty title, count 1, four payload bytes where eight are required
		let armored = Self.frame(payload: [0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0])
		let decoded: ChartSpec? = IslandEnvelope.decode(armored)
		#expect(decoded == nil)
	}

	@Test("decodeMount reads the frame and the engine-measured width")
	func mountWidth() {
		let armored = IslandEnvelope.encode(Self.spec)
		let mount: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"frame\":\"\(armored)\",\"width\":774}")
		#expect(mount?.payload == Self.spec)
		#expect(mount?.width == 774)
	}

	@Test("decodeMount without a width decodes nil width")
	func mountNoWidth() {
		let armored = IslandEnvelope.encode(Self.spec)
		let mount: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"frame\":\"\(armored)\"}")
		#expect(mount?.payload == Self.spec)
		#expect(mount?.width == nil)
	}

	@Test("decodeMount treats a non-measurement as no width")
	func mountBadWidth() {
		let armored = IslandEnvelope.encode(Self.spec)
		let zero: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"frame\":\"\(armored)\",\"width\":0}")
		#expect(zero?.width == nil)
		let negative: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"frame\":\"\(armored)\",\"width\":-5}")
		#expect(negative?.width == nil)
	}

	@Test("decodeMount refuses a missing or malformed frame")
	func mountBadFrame() {
		let missing: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"width\":774}")
		#expect(missing == nil)
		let emptyObject: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{}")
		#expect(emptyObject == nil)
		let notJSON: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("nope")
		#expect(notJSON == nil)
	}

	// MARK: - frame construction for the rejection cases

	/// standard base64 with padding, matching `IslandEnvelope`'s armor.
	private static func armor(_ bytes: [UInt8]) -> String {
		IslandBase64.encode(bytes)
	}

	/// a frame with an overridable header field.
	private static func frame(
		payload: [UInt8],
		version: UInt16 = IslandEnvelope.version,
		magic: [UInt8] = IslandEnvelope.magic,
		declared: Int? = nil
	) -> String {
		let length = declared ?? payload.count
		var bytes = magic
		bytes += [UInt8(truncatingIfNeeded: version >> 8), UInt8(truncatingIfNeeded: version)]
		bytes += [0, 0]
		bytes += [
			UInt8(truncatingIfNeeded: length >> 24),
			UInt8(truncatingIfNeeded: length >> 16),
			UInt8(truncatingIfNeeded: length >> 8),
			UInt8(truncatingIfNeeded: length),
		]
		bytes += payload
		return armor(bytes)
	}

	/// a spec's payload bytes, recovered from a well-formed frame.
	private static func payloadBytes(_ spec: ChartSpec) -> [UInt8] {
		let armored = IslandEnvelope.encode(spec)
		let bytes = IslandBase64.decode(armored) ?? []
		return Array(bytes.dropFirst(IslandEnvelope.headerByteCount))
	}
}