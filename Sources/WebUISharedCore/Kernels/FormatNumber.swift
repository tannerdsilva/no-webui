// MARK: - NumberFormat (t4.1, shared kernels)
//
// hand-rolled number formatting — no Foundation, no `String(format:)`,
// no `String(Double)` (whose digit generation the embedded stdlib may render
// differently). all four recipes reduce to INTEGER arithmetic on the scaled
// magnitude, which is bit-identical across the native and embedded wasm
// runtimes — that determinism is exactly what the t4.2 parity corpus hashes.
//
// input contract: for the fixed/percent recipes, |value| must stay below
//   2^53 ÷ 10^fractionDigits (≈9e15 / 10^places)
// so the scaled value always fits Int64. out-of-contract magnitudes clamp to
// Int64.max instead of trapping (documented at the clamp site).

public enum NumberFormat {

	/// `-` prefix when the value is negative, "" otherwise.
	private static func signPrefix(_ negative: Bool) -> String {
		negative ? "-" : ""
	}

	/// the exact base-10 digits of an Int64 via repeated /10. the magnitude is
	/// taken in UInt64 so `Int64.min` (whose negation overflows) formats
	/// correctly too.
	private static func decimalString(_ value: Int64) -> String {
		if value == 0 { return "0" }
		let negative = value < 0
		var magnitude: UInt64 = negative
			? UInt64(0 &- UInt64(bitPattern: value))
			: UInt64(value)
		var digits: [Int] = []
		while magnitude > 0 {
			digits.append(Int(magnitude % 10))
			magnitude /= 10
		}
		var out = ""
		out.reserveCapacity(digits.count + (negative ? 1 : 0))
		if negative { out.unicodeScalars.append("-") }
		for position in digits.reversed() {
			out.unicodeScalars.append(Self.asciiDigit(position))
		}
		return out
	}

	/// `0x30 + digit` — always a valid scalar for 0…9.
	private static func asciiDigit(_ digit: Int) -> Unicode.Scalar {
		Unicode.Scalar(UInt32(0x30 + digit))!
	}

	/// `digits` (most significant first) rendered into a string.
	private static func digitsString(_ digits: [Int]) -> String {
		var out = ""
		out.reserveCapacity(digits.count)
		for d in digits { out.unicodeScalars.append(Self.asciiDigit(d)) }
		return out
	}

	/// plain base-10 rendering of an integer: "0", "-12345",
	/// "-9223372036854775808".
	public static func integer(_ value: Int) -> String {
		decimalString(Int64(value))
	}

	/// thousands-grouped integer: "1,234,567", "-1,234,567". grouping is from
	/// the right, every three digits; the sign never groups. `separator`
	/// defaults to the ASCII comma. scalar-clean: everything below operates
	/// on `unicodeScalars` (the embedded runtime omits grapheme-break tables,
	/// so Character-view APIs like `String.dropFirst`/`.hasPrefix` are out).
	public static func grouped(_ value: Int, separator: Unicode.Scalar = ",") -> String {
		let body = decimalString(Int64(value))
		let scalars = body.unicodeScalars
		let negative = scalars.first?.value == 0x2D
		let digitScalars = scalars.dropFirst(negative ? 1 : 0)
		var out = ""
		out.reserveCapacity(body.utf8.count + body.utf8.count / 3 + 1)
		if negative { out.unicodeScalars.append("-") }
		var seen = 0
		let n = digitScalars.count
		for scalar in digitScalars {
			if seen > 0, (n - seen) % 3 == 0 { out.unicodeScalars.append(separator) }
			out.unicodeScalars.append(scalar)
			seen += 1
		}
		return out
	}

	/// fixed-point rendering of a double with exactly `fractionDigits` decimal
	/// places. rounding is half-away-from-zero applied to the SCALED value —
	/// i.e. the output is what binary IEEE 754 arithmetic yields, not always
	/// what a decimal reader expects for binary non-representables (1.015 has
	/// no exact double; see KernelTests for the pinned digits). that behaviour
	/// is deterministic and identical on every placement.
	public static func fixed(_ value: Double, fractionDigits: Int) -> String {
		let places = max(0, min(fractionDigits, 12))
		guard value.isFinite else { return "NaN" }
		if value == 0 {
			return places == 0 ? "0" : "0." + Self.zeros(places)
		}
		let negative = value < 0
		let magnitude = negative ? -value : value

		// scale = 10^places as a double (exact for places ≤ 12).
		var scale: Double = 1
		for _ in 0..<places { scale *= 10 }

		// half-away-from-zero on the scaled magnitude: (x * scale + 0.5)
		// rounded down. for negative inputs we already took magnitude, so
		// this is the positive half-away branch throughout.
		let scaled = (magnitude * scale + 0.5).rounded(.down)
		let scaledInt: Int64 = scaled >= Double(Int64.max)
			? Int64.max          // out-of-contract clamp — documented in the header
			: Int64(scaled)

		let pow10 = Self.powerOfTen(places)
		let whole = scaledInt / pow10
		var frac = scaledInt % pow10

		var fracDigits: [Int] = []
		fracDigits.reserveCapacity(places)
		var count = places
		while count > 0 {
			let divisor = Self.powerOfTen(count - 1)
			fracDigits.append(Int(frac / divisor))
			frac %= divisor
			count -= 1
		}

		var text = decimalString(whole)
		if places > 0 {
			text.unicodeScalars.append(".")
			text += digitsString(fracDigits)
		}
		return signPrefix(negative) + text
	}

	/// percentage form: `value` is the ratio (0.125 → "12.50%" at two places).
	public static func percent(_ value: Double, fractionDigits: Int) -> String {
		fixed(value * 100, fractionDigits: fractionDigits) + "%"
	}

	// MARK: internals

	private static func zeros(_ count: Int) -> String {
		digitsString([Int](repeating: 0, count: count))
	}

	private static func powerOfTen(_ n: Int) -> Int64 {
		var result: Int64 = 1
		for _ in 0..<n { result *= 10 }
		return result
	}
}
