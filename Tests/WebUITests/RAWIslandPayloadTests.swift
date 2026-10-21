import Testing
import RAW
import WebUIIslandWire
import WebUIIslandWireRAW

// a rawdog-native fixed-layout payload, declared the way an island author would:
// the storage macro plus the adapter conformance replaces a hand-written codec.
@RAW_staticbuff(bytes: 4)
@RAW_staticbuff_fixedwidthinteger_type<UInt32>(bigEndian: true)
struct RAWCounterPayload: Sendable, RAW_native, Hashable, Comparable, Equatable, RAWIslandPayload {}

@Suite("RAWIslandPayload")
struct RAWIslandPayloadTests {
	@Test func encodesRawdogLayoutAndDecodesBack() {
		let value = RAWCounterPayload(RAW_native: 0x0102_0304)
		var count = 0
		value.islandEncode(count: &count)
		#expect(count == 4, "a staticbuff reports its compile-time byte count")

		var bytes = [UInt8](repeating: 0, count: count)
		bytes.withUnsafeMutableBytes { raw in
			guard let base = raw.baseAddress else { return }
			value.islandEncode(UnsafeMutableRawPointer.self, destination: base)
		}
		// big-endian declaration: the wire bytes are the declared layout, not a
		// host-endian copy of the storage.
		#expect(bytes == [0x01, 0x02, 0x03, 0x04])

		let decoded = bytes.withUnsafeBytes { RAWCounterPayload(islandDecode: $0) }
		#expect(decoded == value, "the pair round-trips through rawdog's decode")
	}

	@Test func rejectsABufferOfTheWrongLength() {
		for length in [0, 3, 5] {
			let bytes = [UInt8](repeating: 0, count: length)
			let decoded = bytes.withUnsafeBytes { RAWCounterPayload(islandDecode: $0) }
			#expect(decoded == nil, "a \(length)-byte buffer is not a 4-byte payload")
		}
	}
}