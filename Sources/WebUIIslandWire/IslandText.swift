// MARK: - foundation-free utf-8 decoding for the island boundary
//
// `String(decoding:as:)` canonicalizes through the unicode normalization
// tables, which the embedded wasm runtime omits — an island link that
// referenced them would fail on `_swift_stdlib_nfd_*`. this scanner is the
// one place island text bytes become a `String`, in two policies: strict
// (`nil` on the first invalid sequence) for typed payloads, and
// replace-with-U+FFFD for the lenient harness path the engine's json has
// always used.

public enum IslandUTF8 {
	/// decode utf-8 strictly — the first invalid sequence returns `nil`.
	///
	/// rejects: truncated sequences, lone continuation bytes, overlong
	/// encodings, surrogates, and values above U+10FFFF. a typed payload that
	/// does not decode cleanly is not the payload the encoder wrote, so the
	/// region falls back rather than rendering replacement characters.
	public static func decode(_ bytes: UnsafeRawBufferPointer) -> String? {
		var out = ""
		out.reserveCapacity(bytes.count)
		var index = 0
		while index < bytes.count {
			guard let (scalar, width) = nextScalar(bytes, index) else { return nil }
			guard let value = Unicode.Scalar(scalar) else { return nil }
			out.unicodeScalars.append(value)
			index += width
		}
		return out
	}

	/// decode utf-8, replacing each invalid sequence with U+FFFD.
	///
	/// the lenient policy: the harness decodes the engine's mount envelope,
	/// and a torn byte becomes a replacement character the json parser then
	/// rejects — never a crash.
	public static func decodeReplacingInvalid(_ bytes: UnsafeRawBufferPointer) -> String {
		var out = ""
		out.reserveCapacity(bytes.count)
		var index = 0
		while index < bytes.count {
			if let (scalar, width) = nextScalar(bytes, index), let value = Unicode.Scalar(scalar) {
				out.unicodeScalars.append(value)
				index += width
			} else {
				out.unicodeScalars.append("\u{FFFD}")
				index += 1
			}
		}
		return out
	}

	/// the scalar starting at `index`, or `nil` when the sequence is invalid.
	/// returns the scalar's value and its byte width.
	static func nextScalar(_ bytes: UnsafeRawBufferPointer, _ index: Int) -> (value: UInt32, width: Int)? {
		let b = bytes[index]
		if b < 0x80 { return (UInt32(b), 1) }
		if (b & 0xE0) == 0xC0, index + 1 < bytes.count, (bytes[index + 1] & 0xC0) == 0x80 {
			let v = (UInt32(b & 0x1F) << 6) | UInt32(bytes[index + 1] & 0x3F)
			// overlong: a two-byte sequence must encode >= U+0080
			return v >= 0x80 ? (v, 2) : nil
		}
		if (b & 0xF0) == 0xE0, index + 2 < bytes.count,
		   (bytes[index + 1] & 0xC0) == 0x80, (bytes[index + 2] & 0xC0) == 0x80 {
			let v = (UInt32(b & 0x0F) << 12) | (UInt32(bytes[index + 1] & 0x3F) << 6) | UInt32(bytes[index + 2] & 0x3F)
			// overlong floor U+0800; the surrogate range is rejected by
			// `Unicode.Scalar(_:)` at the call site
			return v >= 0x800 ? (v, 3) : nil
		}
		if (b & 0xF8) == 0xF0, index + 3 < bytes.count,
		   (bytes[index + 1] & 0xC0) == 0x80, (bytes[index + 2] & 0xC0) == 0x80,
		   (bytes[index + 3] & 0xC0) == 0x80 {
			let v = (UInt32(b & 0x07) << 18) | (UInt32(bytes[index + 1] & 0x3F) << 12)
				| (UInt32(bytes[index + 2] & 0x3F) << 6) | UInt32(bytes[index + 3] & 0x3F)
			// overlong floor U+10000; the >U+10FFFF ceiling is rejected by
			// `Unicode.Scalar(_:)` at the call site
			return v >= 0x10000 ? (v, 4) : nil
		}
		return nil
	}
}