@_exported import RAW
import WebUIIslandWire

/// a rawdog-native value that crosses the island boundary with no adapter code.
///
/// conform a `@RAW_staticbuff` type to this and it satisfies both island payload
/// requirements through rawdog's own `RAW_encode`/`RAW_decode`: the same count
/// discipline, destination-advancing writer, and all-or-nothing reader, with no
/// hand-written codec.
///
/// this is wasm-safe as of rawdog 22.1: `RAW` builds for
/// `wasm32-unknown-wasip1` under the embedded sdk (its `Codable` conformance is
/// gated on `!hasFeature(Embedded)`, which island payloads never need). before
/// 22.1 the island had to hand-roll the pair for every payload.
///
/// scope: fixed-layout values. a staticbuff has a compile-time byte count, which
/// is exactly what the frame's length prefix wants. a variable-length payload
/// (a title plus an array of values) still implements ``IslandPayloadEncodable``
/// / ``IslandPayloadDecodable`` directly, writing its own length prefixes.
///
/// opt-in by construction: string islands never link this target, so their
/// artifacts stay rawdog-free.
public protocol RAWIslandPayload: IslandPayloadEncodable, IslandPayloadDecodable, RAW_encodable, RAW_decodable {
	/// restated (it is inherited from ``IslandPayloadDecodable``) so the default
	/// implementation below can witness it: an initializer declared in a protocol
	/// extension must match a requirement declared on that protocol.
	init?(islandDecode buffer: UnsafeRawBufferPointer)
}

extension RAWIslandPayload {
	/// report the encoded length — rawdog's count, forwarded.
	public func islandEncode(count: inout Int) {
		RAW_encode(count: &count)
	}

	/// write the fixed storage at `destination`, returning the advanced pointer.
	@discardableResult
	public func islandEncode(_: UnsafeMutableRawPointer.Type, destination: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
		RAW_encode(UnsafeMutableRawPointer.self, destination: destination)
	}

	/// rebuild from exactly one buffer; rawdog rejects a mismatched length.
	public init?(islandDecode buffer: UnsafeRawBufferPointer) {
		self.init(RAW_decode: buffer)
	}
}