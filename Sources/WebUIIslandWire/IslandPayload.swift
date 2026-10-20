// MARK: - the island payload protocol
//
// the typed contract's payload side: a value that can write its own bytes and
// be rebuilt from them. the requirements mirror rawdog's encode/decode shape
// deliberately — `count` reporting, a destination-advancing writer, and an
// all-or-nothing reader — because that discipline is the point: fixed layout,
// exact consumption, no schema in the middle.
//
// why not rawdog's own protocols: rawdog's module cannot compile for embedded
// wasm (its `RAW` target uses `Codable`, unavailable in embedded Swift, and
// `CRAW` requires mmap emulation), so a rawdog-conforming payload type can
// never be decoded inside an island. this pair is the wasm-safe subset, and a
// host-only rawdog type can bridge to it mechanically (forward `islandEncode`
// to `RAW_encode`, `init(islandDecode:)` to `init(RAW_decode:)`) wherever both
// sides can see rawdog.
//
// the reader contract: either every byte is consumed or the value is `nil`.
// the writer contract: the returned pointer advances by exactly the count
// reported from `islandEncode(count:)`.

/// a value that serializes into a fixed or self-describing byte layout.
public protocol IslandPayloadEncodable: Sendable {
	/// report the encoded byte length.
	func islandEncode(count: inout Int)
	/// write the encoding at `destination`; return the pointer advanced by the
	/// written byte count.
	@discardableResult
	func islandEncode(_: UnsafeMutableRawPointer.Type, destination: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer
}

/// a value that rebuilds itself from exactly one buffer.
public protocol IslandPayloadDecodable: Sendable {
	/// initialize from `buffer`, consuming all of it; return `nil` on any
	/// length, bounds, or content mismatch.
	init?(islandDecode buffer: UnsafeRawBufferPointer)
}