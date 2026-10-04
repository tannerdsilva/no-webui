// MARK: - FNV1a (t4.2 parity hashing)
//
// a 64-bit FNV-1a over the UTF-8 of a canonical result string. the choice is
// deliberate: it needs no Foundation, no crypto, and is pure integer math —
// so the native and embedded wasm runtimes compute byte-identical hashes for
// byte-identical strings (this is the t4.2 equality gate's only requirement;
// collision resistance is not a goal here, determinism is).

public enum FNV1a {
	/// FNV-1a 64-bit offset basis.
	public static let offsetBasis: UInt64 = 0xcbf29ce484222325
	/// FNV-1a 64-bit prime.
	public static let prime: UInt64 = 0x100000001b3

	/// the hash of `text`'s UTF-8 bytes.
	public static func hash(_ text: String) -> UInt64 {
		var h = offsetBasis
		for byte in text.utf8 {
			h = (h ^ UInt64(byte)) &* prime
		}
		return h
	}

	/// the hash as 16 lowercase hex digits — the compact comparison form both
	/// the native suite and the node probe compare.
	public static func hex(_ text: String) -> String {
		hex(hash(text))
	}

	public static func hex(_ value: UInt64) -> String {
		var out = ""
		out.reserveCapacity(16)
		for shift in stride(from: 60, through: 0, by: -4) {
			let nibble = Int((value >> UInt64(shift)) & 0xf)
			// 0..9 → 0x30…0x39, 10..15 → 0x61…0x66.
			let code: UInt32 = nibble < 10 ? UInt32(0x30 + nibble) : UInt32(0x57 + nibble)
			out.unicodeScalars.append(Unicode.Scalar(code)!)
		}
		return out
	}
}
