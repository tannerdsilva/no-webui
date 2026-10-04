// MARK: - Continuum
//
// the seam vocabulary — the types every hot path crosses, in the shape frozen
// by the DESKTOP_GRADE plan (§1.3.3–§1.3.5, record table §t2.3). lives in the
// zero-dep leaf (`WebUISharedCore`) so the islands and the engine/server
// surfaces share one source of truth. scalar-clean like `JSONValue`:
// `Codable` is `@_unavailableInEmbedded`, so those conformances are gated for
// the island build exactly as JSONValue gates its own — the island path carries
// values with the hand-rolled `HotOpCodec` below and `JSONValue`, never
// `Decoder`/`Encoder`.

// MARK: - element & attribute addresses

/// an element address hot paths patch by; one type so ids never juggle as raw strings.
public struct ElementID: Sendable, Hashable, ExpressibleByStringLiteral {
	public let raw: String
	public init(_ raw: String) { self.raw = raw }
	public init(stringLiteral value: String) { self.raw = value }
}

/// an attribute name with a policy: allowed names are generated per component.
public struct AttributeName: Sendable, Hashable, ExpressibleByStringLiteral {
	public let raw: String
	public init(_ raw: String) { self.raw = raw }
	public init(stringLiteral value: String) { self.raw = value }
}

// MARK: - Codable conformance (host/full-stdlib surface only)

// `Decoder`/`Encoder` are unavailable in embedded swift (JSONValue carries the
// same gate): the island path uses JSONValue + HotOpCodec, so these
// conformances are the host surface the server adapter compiles against.
#if !hasFeature(Embedded)
extension ElementID: Codable {}
extension AttributeName: Codable {}
#endif

// MARK: - the op vocabulary

/// one steady-state mutation an island emits. typed by construction.
public enum HotOp: Sendable, Equatable {
	case text(ElementID, String)
	case attr(ElementID, AttributeName, String)
	case insert(parent: ElementID, before: ElementID?, html: String) // sanitized once, at insert
	case remove(ElementID)
	case move(ElementID, before: ElementID?)
}

// MARK: - capabilities

/// a capability the host grants an island, keyed by `wireName`. islands declare
/// imports by capability *type*; the build lint checks them against host grants
/// at build time (DESKTOP_GRADE §1.3.4, t2.6).
public protocol HostCapability: Sendable {
	static var wireName: String { get }
}

public struct FrameSchedule: HostCapability      { public static let wireName = "frame_schedule" }
public struct InputSubscription: HostCapability  { public static let wireName = "input_subscribe" }
public struct SurfaceAcquisition: HostCapability { public static let wireName = "surface_acquire" }
public struct StatePersistence: HostCapability   { public static let wireName = "state_persist" }
public struct ClockCapability: HostCapability    { public static let wireName = "clock" }
public struct LogCapability: HostCapability      { public static let wireName = "log" }

// MARK: - the island protocol

/// a placement-independent island state value. `reduce` is pure, so the same
/// source runs inside wasm and in native unit tests (parity by construction).
#if !hasFeature(Embedded)
public protocol HotState: Codable, Sendable, Equatable {}
#else
public protocol HotState: Sendable, Equatable {}
#endif

/// an island event payload. same placement rule as `HotState`.
#if !hasFeature(Embedded)
public protocol HotAction: Codable, Sendable {}
#else
public protocol HotAction: Sendable {}
#endif

/// one effect `reduce` may return. `ops` are the typed data plane; `save` and
/// `log` ride the control plane.
public enum HotEffect: Sendable {
	case ops([HotOp])
	case save
	case log(String)
}

public struct IslandBudget: Sendable, Equatable {
	public let maxBytes: Int
	public let maxGzipBytes: Int?
	public init(maxBytes: Int, maxGzipBytes: Int? = nil) {
		self.maxBytes = maxBytes
		self.maxGzipBytes = maxGzipBytes
	}
}

/// the declarative island surface. `@HotView` emits conformance; hand-writing
/// it remains possible and tested (the "one hand-written equivalent" rule §9).
public protocol ContinuumIsland: Sendable {
	associatedtype State: HotState
	associatedtype Action: HotAction
	static var name: String { get }
	static var imports: [any HostCapability.Type] { get }
	static var budget: IslandBudget { get }
	static func reduce(state: inout State, action: Action) -> [HotEffect]
}

// MARK: - HotOp codec (record format v1, §t2.3)

/// typed failures from `HotOpCodec`.
public enum HotOpCodecError: Error, Equatable, Sendable {
	case unsupportedVersion(UInt8)
	case unknownOpcode(UInt8)
	case truncatedRecord
	case truncatedString
	case trailingBytes
	/// encode-side: an identifier needs more than 65,535 utf-8 bytes (u16 field).
	case identifierTooLong
	/// encode-side: a bulk string beyond a u32 length field.
	case bulkTooLong
}

/// the hand-rolled, scalar-clean record codec for the island op stream —
/// frame-buffer record format v1 (DESKTOP_GRADE §t2.3):
///
/// | field | bytes | notes |
/// |---|---|---|
/// | version | u8 | 1 |
/// | opcode | u8 | 1 text · 2 attr · 3 insert · 4 remove · 5 move |
/// | id len | u16 | utf-8 bytes |
/// | id | n | the element the op targets (for insert: the parent) |
/// | payload | opcode-specific | text: u32 len + bytes · attr: u16 name + u32 value · insert: before + u32 html · remove: — · move: before (u16, 0xffff = end) |
///
/// a `before` field is a u16: `0xffff` = no anchor (append / move to end); any
/// other value is the utf-8 byte length of the anchor id that follows.
/// multi-byte integers are little-endian (wasm32 and every in-tree host).
public enum HotOpCodec {
	public static let formatVersion: UInt8 = 1

	public static let opcodeText: UInt8 = 1
	public static let opcodeAttr: UInt8 = 2
	public static let opcodeInsert: UInt8 = 3
	public static let opcodeRemove: UInt8 = 4
	public static let opcodeMove: UInt8 = 5

	/// the u16 `before` sentinel: no anchor — append / move to end.
	public static let beforeEndSentinel: UInt16 = 0xffff

	public static func encode(_ op: HotOp) throws -> [UInt8] {
		var writer = HotOpWriter()
		writer.writeUInt8(Self.formatVersion)
		switch op {
		case .text(let id, let value):
			writer.writeUInt8(Self.opcodeText)
			try writer.writeIdentifier(id.raw)
			try writer.writeBulk(value)
		case .attr(let id, let name, let value):
			writer.writeUInt8(Self.opcodeAttr)
			try writer.writeIdentifier(id.raw)
			try writer.writeIdentifier(name.raw)
			try writer.writeBulk(value)
		case .insert(let parent, let before, let html):
			writer.writeUInt8(Self.opcodeInsert)
			// the record id slot carries the parent (the element the op operates
			// on); the new element's id is not part of the v1 record — the engine
			// allocates it on apply. conservative reading of "parent/before".
			try writer.writeIdentifier(parent.raw)
			try writer.writeOptionalIdentifier(before?.raw)
			try writer.writeBulk(html)
		case .remove(let id):
			writer.writeUInt8(Self.opcodeRemove)
			try writer.writeIdentifier(id.raw)
		case .move(let id, let before):
			writer.writeUInt8(Self.opcodeMove)
			try writer.writeIdentifier(id.raw)
			try writer.writeOptionalIdentifier(before?.raw)
		}
		return writer.bytes
	}

	/// decodes exactly one record; a non-empty remainder is `trailingBytes`.
	public static func decode(_ bytes: [UInt8]) throws -> HotOp {
		var reader = HotOpReader(bytes: bytes)
		let op = try decodeRecord(from: &reader)
		guard reader.isAtEnd else { throw HotOpCodecError.trailingBytes }
		return op
	}

	/// decodes a back-to-back record stream (the exact inverse of
	/// `encodeBatch`) into its constituent ops — the native side of the drain
	/// walk `webui_take_ops()` serves and the shape lane D's generated
	/// `decodePendingOps()` delegation decodes (W3, d-to-c.md). one malformed
	/// record aborts the whole stream (the same strict contract as `decode`: a
	/// frame never silently truncates).
	public static func decodeBatch(_ bytes: [UInt8]) throws -> [HotOp] {
		var reader = HotOpReader(bytes: bytes)
		var ops: [HotOp] = []
		while !reader.isAtEnd {
			ops.append(try decodeRecord(from: &reader))
		}
		return ops
	}

	/// parses one record from a reader positioned at a record start — the
	/// shared decode core for `decode` (strict single-record) and `decodeBatch`
	/// (whole-stream). behavior-identical to the original inline `decode`
	/// body (the trailing-bytes guard stays in `decode`).
	private static func decodeRecord(from reader: inout HotOpReader) throws -> HotOp {
		let version = try reader.readUInt8()
		guard version == Self.formatVersion else { throw HotOpCodecError.unsupportedVersion(version) }
		let opcode = try reader.readUInt8()
		let id = try reader.readIdentifier()
		let op: HotOp
		switch opcode {
		case Self.opcodeText:
			op = .text(id, try reader.readBulk())
		case Self.opcodeAttr:
			let name = try reader.readIdentifier()
			let value = try reader.readBulk()
			op = .attr(id, AttributeName(name.raw), value)
		case Self.opcodeInsert:
			let before = try reader.readOptionalIdentifier()
			let html = try reader.readBulk()
			op = .insert(parent: id, before: before, html: html)
		case Self.opcodeRemove:
			op = .remove(id)
		case Self.opcodeMove:
			let before = try reader.readOptionalIdentifier()
			op = .move(id, before: before)
		default:
			throw HotOpCodecError.unknownOpcode(opcode)
		}
		return op
	}

	/// encodes an op sequence into one back-to-back record stream — the exact
	/// payload `webui_take_ops()` serves (the wave-2 freeze: records back-to-back,
	/// each record-v1; the engine drains until 0). one failing op aborts the whole
	/// batch with the same typed error `encode` throws, so a frame never carries a
	/// silently-truncated record.
	public static func encodeBatch(_ ops: [HotOp]) throws -> [UInt8] {
		var out: [UInt8] = []
		out.reserveCapacity(ops.count * 8)
		for op in ops {
			out.append(contentsOf: try encode(op))
		}
		return out
	}
}

// MARK: - codec writers

private struct HotOpWriter {
	var bytes: [UInt8] = []

	mutating func writeUInt8(_ value: UInt8) {
		bytes.append(value)
	}

	// little-endian all the way down; masking instead of truncatingIfNeeded so
	// the embedded build has no conversion-surface surprises.
	mutating func writeUInt16(_ value: UInt16) {
		bytes.append(UInt8(value & 0xff))
		bytes.append(UInt8((value >> 8) & 0xff))
	}

	mutating func writeUInt32(_ value: UInt32) {
		bytes.append(UInt8(value & 0xff))
		bytes.append(UInt8((value >> 8) & 0xff))
		bytes.append(UInt8((value >> 16) & 0xff))
		bytes.append(UInt8((value >> 24) & 0xff))
	}

	mutating func writeRaw(_ value: [UInt8]) {
		bytes.append(contentsOf: value)
	}

	/// an identifier-class field: u16 utf-8 byte length + bytes.
	mutating func writeIdentifier(_ raw: String) throws {
		let utf8 = Array(raw.utf8)
		guard utf8.count <= 0xffff else { throw HotOpCodecError.identifierTooLong }
		writeUInt16(UInt16(utf8.count))
		writeRaw(utf8)
	}

	/// the `before` field shared by insert/move: 0xffff = end, else u16 len + id.
	mutating func writeOptionalIdentifier(_ raw: String?) throws {
		guard let raw else {
			writeUInt16(HotOpCodec.beforeEndSentinel)
			return
		}
		try writeIdentifier(raw)
	}

	/// a bulk field: u32 utf-8 byte length + bytes.
	mutating func writeBulk(_ raw: String) throws {
		let utf8 = Array(raw.utf8)
		// `exactly:` — on wasm32 Int is 32-bit so the count always fits u32;
		// the failable init turns the pathological host-only > 4 GiB case
		// into a typed error instead of a conversion trap.
		guard let byteCount = UInt32(exactly: utf8.count) else { throw HotOpCodecError.bulkTooLong }
		writeUInt32(byteCount)
		writeRaw(utf8)
	}
}

// MARK: - codec readers

private struct HotOpReader {
	let bytes: [UInt8]
	var index = 0

	var isAtEnd: Bool { index >= bytes.count }

	mutating func readUInt8() throws -> UInt8 {
		guard index < bytes.count else { throw HotOpCodecError.truncatedRecord }
		let value = bytes[index]
		index += 1
		return value
	}

	// little-endian, mirroring the writer.
	mutating func readUInt16() throws -> UInt16 {
		guard index + 2 <= bytes.count else { throw HotOpCodecError.truncatedRecord }
		let value = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
		index += 2
		return value
	}

	mutating func readUInt32() throws -> UInt32 {
		guard index + 4 <= bytes.count else { throw HotOpCodecError.truncatedRecord }
		let value = UInt32(bytes[index])
			| (UInt32(bytes[index + 1]) << 8)
			| (UInt32(bytes[index + 2]) << 16)
			| (UInt32(bytes[index + 3]) << 24)
		index += 4
		return value
	}

	mutating func readIdentifier() throws -> ElementID {
		let length = Int(try readUInt16())
		return ElementID(try readUTF8(count: length))
	}

	mutating func readOptionalIdentifier() throws -> ElementID? {
		let marker = try readUInt16()
		guard marker != HotOpCodec.beforeEndSentinel else { return nil }
		return ElementID(try readUTF8(count: Int(marker)))
	}

	mutating func readBulk() throws -> String {
		let length = Int(try readUInt32())
		return try readUTF8(count: length)
	}

	private mutating func readUTF8(count: Int) throws -> String {
		guard count >= 0, index + count <= bytes.count else { throw HotOpCodecError.truncatedString }
		let rawBytes = bytes[index..<(index + count)]
		index += count
		return rawBytes.withUnsafeBufferPointer { decodeUTF8(UnsafeRawBufferPointer($0)) }
	}
}

// MARK: - scalar-clean utf-8

/// strict-enough utf-8 decode into a `String` without touching the
/// normalization tables: `String(decoding:as:)` canonicalizes, which the
/// embedded runtime omits, so an island referencing it would fail to link on
/// the `_swift_stdlib_nfd_*` symbols. invalid sequences become U+FFFD.
/// mirrors the island template's `utf8Decode` (Main.swift:61-103).
private func decodeUTF8(_ bytes: UnsafeRawBufferPointer) -> String {
	var out = ""
	var i = 0
	while i < bytes.count {
		let b = bytes[i]
		let scalar: UInt32
		let width: Int
		if b < 0x80 {
			scalar = UInt32(b)
			width = 1
		} else if (b & 0xE0) == 0xC0, i + 1 < bytes.count, (bytes[i + 1] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x1F) << 6) | UInt32(bytes[i + 1] & 0x3F)
			width = 2
		} else if (b & 0xF0) == 0xE0, i + 2 < bytes.count,
		          (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x0F) << 12) | (UInt32(bytes[i + 1] & 0x3F) << 6)
				| UInt32(bytes[i + 2] & 0x3F)
			width = 3
		} else if (b & 0xF8) == 0xF0, i + 3 < bytes.count,
		          (bytes[i + 1] & 0xC0) == 0x80, (bytes[i + 2] & 0xC0) == 0x80,
		          (bytes[i + 3] & 0xC0) == 0x80 {
			scalar = (UInt32(b & 0x07) << 18) | (UInt32(bytes[i + 1] & 0x3F) << 12)
				| (UInt32(bytes[i + 2] & 0x3F) << 6) | UInt32(bytes[i + 3] & 0x3F)
			width = 4
		} else {
			out.unicodeScalars.append("\u{FFFD}")
			i += 1
			continue
		}
		// `Unicode.Scalar(_:)` rejects exactly what utf-8 forbids here: values
		// above U+10FFFF and the surrogate range, so the failable init is the
		// validity check itself — no force unwrap, no separate range test.
		if let scalarValue = Unicode.Scalar(scalar) {
			out.unicodeScalars.append(scalarValue)
		} else {
			out.unicodeScalars.append("\u{FFFD}")
		}
		i += width
	}
	return out
}
