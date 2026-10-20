// MARK: - base64 armor for the args attribute
//
// the frame rides `data-webui-args` as text, so it needs an armor that needs
// no escaping and no json string gymnastics. standard base64 with `=` padding.
// the decoder is strict (alphabet, quad length, padding placement) because a
// lenient decoder is how two implementations drift apart.

package enum IslandBase64 {
	private static let alphabet: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

	package static func encode(_ bytes: [UInt8]) -> String {
		var out: [UInt8] = []
		out.reserveCapacity((bytes.count + 2) / 3 * 4)
		var index = 0
		while index < bytes.count {
			let b0 = bytes[index]
			let b1 = index + 1 < bytes.count ? bytes[index + 1] : 0
			let b2 = index + 2 < bytes.count ? bytes[index + 2] : 0
			let triple = UInt32(b0) << 16 | UInt32(b1) << 8 | UInt32(b2)
			out.append(alphabet[Int(triple >> 18 & 0x3F)])
			out.append(alphabet[Int(triple >> 12 & 0x3F)])
			out.append(index + 1 < bytes.count ? alphabet[Int(triple >> 6 & 0x3F)] : 0x3D)
			out.append(index + 2 < bytes.count ? alphabet[Int(triple & 0x3F)] : 0x3D)
			index += 3
		}
		// scalar-append, not `String(decoding:as:)` — the latter canonicalizes
		// through the normalization tables the embedded runtime omits
		var text = ""
		text.reserveCapacity(out.count)
		for byte in out {
			text.unicodeScalars.append(Unicode.Scalar(byte))
		}
		return text
	}

	package static func decode(_ text: String) -> [UInt8]? {
		let scalars = Array(text.unicodeScalars)
		guard !scalars.isEmpty, scalars.count % 4 == 0 else { return nil }
		var out: [UInt8] = []
		out.reserveCapacity(scalars.count / 4 * 3)
		var index = 0
		while index < scalars.count {
			var values = [Int](repeating: 0, count: 4)
			var padding = 0
			for slot in 0..<4 {
				let scalar = scalars[index + slot]
				if scalar == "=" {
					// padding is legal only in the final quad, and only the last
					// two slots may carry it
					guard index + 4 == scalars.count, slot >= 2 else { return nil }
					padding += 1
				} else {
					guard padding == 0, let value = self.value(of: scalar) else { return nil }
					values[slot] = value
				}
			}
			let triple = UInt32(values[0]) << 18 | UInt32(values[1]) << 12
				| UInt32(values[2]) << 6 | UInt32(values[3])
			out.append(UInt8(triple >> 16 & 0xFF))
			if padding < 2 { out.append(UInt8(triple >> 8 & 0xFF)) }
			if padding < 1 { out.append(UInt8(triple & 0xFF)) }
			index += 4
		}
		return out
	}

	private static func value(of scalar: Unicode.Scalar) -> Int? {
		switch scalar {
		case "A" ... "Z": return Int(scalar.value - 65)
		case "a" ... "z": return Int(scalar.value - 97) + 26
		case "0" ... "9": return Int(scalar.value - 48) + 52
		case "+": return 62
		case "/": return 63
		default: return nil
		}
	}
}