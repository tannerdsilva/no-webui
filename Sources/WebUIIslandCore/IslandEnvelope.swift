// MARK: - the typed island envelope
//
// a typed region ships its input as a versioned binary frame instead of the
// json args object a string island uses. the frame rides the same
// `data-webui-args` attribute — base64-armored inside `{"frame":"…"}` — so
// the engine stays byte-for-byte unchanged: it parses the args object, adds
// the measured width for resize-flagged regions, and hands the module the
// mount envelope. no javascript knows what a frame is.
//
//	frame := magic "WUI1" | u16be version | u16be reserved | u32be length | payload
//	payload := the value's `IslandPayloadEncodable` bytes, exactly `length`
//
// the header exists for the same reason any wire format has one: a stale
// cached artifact and a fresh page can disagree about the payload layout, and
// the versioned magic turns that into a clean fallback instead of a decoder
// reading garbage. decode is all-or-nothing — a frame is accepted only when
// every byte is accounted for.
//
// (the original sketch called for rawdog frames; rawdog's module cannot
// compile for embedded wasm — `Codable` is unavailable there — so the payload
// contract is the wasm-safe `IslandPayloadEncodable`/`IslandPayloadDecodable`
// pair. the layout discipline, and the byte format, are unchanged.)

import WebUISharedCore

public enum IslandEnvelope {
	/// the frame's leading four bytes: `W` `U` `I` `1`.
	public static let magic: [UInt8] = [0x57, 0x55, 0x49, 0x31]
	/// the payload-layout version this build writes and reads.
	public static let version: UInt16 = 1
	/// magic (4) + version (2) + reserved (2) + payload length (4).
	public static let headerByteCount = 12
	/// the args-object key that carries the base64 frame.
	public static let argsKey = "frame"

	/// encode `value` as a base64-armored frame.
	public static func encode<T: IslandPayloadEncodable>(_ value: T) -> String {
		var payloadCount = 0
		value.islandEncode(count: &payloadCount)
		var bytes = [UInt8](repeating: 0, count: headerByteCount + payloadCount)
		bytes[0] = magic[0]
		bytes[1] = magic[1]
		bytes[2] = magic[2]
		bytes[3] = magic[3]
		bytes[4] = UInt8(truncatingIfNeeded: version >> 8)
		bytes[5] = UInt8(truncatingIfNeeded: version)
		bytes[8] = UInt8(truncatingIfNeeded: payloadCount >> 24)
		bytes[9] = UInt8(truncatingIfNeeded: payloadCount >> 16)
		bytes[10] = UInt8(truncatingIfNeeded: payloadCount >> 8)
		bytes[11] = UInt8(truncatingIfNeeded: payloadCount)
		bytes.withUnsafeMutableBytes { raw in
			guard let base = raw.baseAddress else { return }
			_ = value.islandEncode(UnsafeMutableRawPointer.self, destination: base.advanced(by: headerByteCount))
		}
		return IslandBase64.encode(bytes)
	}

	/// decode a base64-armored frame; `nil` on any header, version, length,
	/// base64, or payload mismatch (the region then keeps its server-rendered
	/// fallback).
	public static func decode<T: IslandPayloadDecodable>(_ armored: String) -> T? {
		guard let bytes = IslandBase64.decode(armored) else { return nil }
		guard bytes.count >= headerByteCount else { return nil }
		guard bytes[0] == magic[0], bytes[1] == magic[1],
		      bytes[2] == magic[2], bytes[3] == magic[3] else { return nil }
		let frameVersion = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
		guard frameVersion == version else { return nil }
		let declared = UInt32(bytes[8]) << 24 | UInt32(bytes[9]) << 16
			| UInt32(bytes[10]) << 8 | UInt32(bytes[11])
		guard Int(declared) == bytes.count - headerByteCount else { return nil }
		return bytes.withUnsafeBytes { raw -> T? in
			guard let base = raw.baseAddress else { return nil }
			let payload = UnsafeRawBufferPointer(
				start: base.advanced(by: headerByteCount),
				count: Int(declared)
			)
			return T(islandDecode: payload)
		}
	}

	/// decode the mount envelope's args object: the typed payload plus the
	/// engine-measured container width when the region is resize-flagged.
	///
	/// `argsJSON` is the `args` payload the engine unwraps from `{name, args}`
	/// — `{"frame":"…"}` for a static region, `{"frame":"…","width":774}` once
	/// the engine has measured a resizable one. a non-positive or absurd width
	/// is not a measurement and decodes as `nil`.
	public static func decodeMount<T: IslandPayloadDecodable>(_ argsJSON: String) -> (payload: T, width: Int?)? {
		guard let root = try? JSONValue.parse(argsJSON),
		      case .object(let object) = root,
		      case .string(let armored)? = object[argsKey],
		      let payload: T = decode(armored) else {
			return nil
		}
		var width: Int?
		if case .number(let measured)? = object["width"],
		   measured > 0, measured < 1_000_000 {
			width = Int(measured)
		}
		return (payload, width)
	}
}