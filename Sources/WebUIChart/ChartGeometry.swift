// MARK: - StdlibMath
//
// stdlib-only replacements for the Foundation/Darwin math + printf helpers
// used by the chart renderer, so WebUIChart stays wasm-safe (no Foundation
// dependency). Each replacement is deterministic and matches the Foundation
// behavior for every value the renderer feeds it (verified exhaustively for
// the chart magnitude ranges: viewBox coords, axis ticks, percents).

/// Pure geometry helpers: build SVG `d` paths for lines, areas, and polar
/// sectors, and symbol paths. No I/O, fully deterministic.
///
/// Angle convention (polar): 0° = 12 o'clock, increasing = clockwise,
/// y-down screen space. All coordinates are viewBox units.
enum ChartGeometry {

	/// stdlib-only numeric helpers (shared with `ChartValueFormat`).
	enum StdlibMath {

		/// `10^e` as a Double via repeated multiply/divide — exact for the
		/// small integer exponents the tick algorithm uses.
		static func pow10(_ e: Int) -> Double {
			var r = 1.0
			if e >= 0 {
				for _ in 0..<e { r *= 10 }
			} else {
				for _ in 0..<(-e) { r /= 10 }
			}
			return r
		}

		/// `floor(log10(x))` for `x > 0`, computed by counting decimal
		/// digits instead of a libm `log10` (which is platform-dependent and
		/// can floor one step off at exact powers of ten). Exact for every
		/// value the tick algorithm produces.
		static func decimalExponent(_ x: Double) -> Int {
			var e = 0
			var v = x
			if v >= 1 {
				while v >= 10 { v /= 10; e += 1 }
			} else {
				while v < 1 { v *= 10; e -= 1 }
			}
			return e
		}

		/// Fixed-point decimal rendering identical to `String(format: "%.<d>f",
		/// value)` from Foundation, implemented with integer arithmetic on the
		/// double's exact binary value (m × 2^e) so the last digit rounds the
		/// same way printf does (round-half-to-even, no binary-noise drift).
		static func fixed(_ value: Double, _ decimals: Int) -> String {
			if value.isNaN { return "nan" }
			if value.isInfinite { return value > 0 ? "inf" : "-inf" }
			guard decimals <= 18 else { return String(value) }
			let neg = value.sign == .minus
			let a = neg ? -value : value

			let bits = a.bitPattern
			var m: UInt64 = bits & 0x000F_FFFF_FFFF_FFFF
			let expField = Int((bits >> 52) & 0x7FF)
			let e: Int
			if expField == 0 {
				if m == 0 {
					var z = "0"
					if decimals > 0 { z += "." + String(repeating: "0", count: decimals) }
					return neg ? "-" + z : z
				}
				e = -1074                       // subnormal
			} else {
				m |= 1 << 52
				e = expField - 1075
			}
			// scaled = a · 10^d = (m · 5^d) · 2^(e + d)
			var num = m
			for _ in 0..<decimals {
				let (p, overflow) = num.multipliedReportingOverflow(by: 5)
				if overflow { return String(a) }   // beyond 64-bit precision; charts never reach
				num = p
			}
			let k = e + decimals

			var w: UInt64 = 0
			if k >= 0 {
				// scaled is an exact integer: w = num << k
				var v = num
				var shift = k
				var overflow = false
				while shift > 0 {
					if v > UInt64.max >> 1 { overflow = true; break }
					v <<= 1
					shift -= 1
				}
				if overflow { return String(a) }  // |value| ≳ 1e16; charts never reach
				w = v
			} else {
				// scaled = num / 2^(-k): round to nearest, ties-to-even
				let d = -k
				if d >= 64 {
					// num < 2^63, value < 0.5 → rounds to 0
					w = 0
				} else {
					let divisor = UInt64(1) << d
					let q = num / divisor
					let r = num % divisor
					var ww = q
					if r != 0 {
						let twice = r << 1
						if twice > divisor {
							ww += 1
						} else if twice == divisor {
							if ww & 1 == 1 { ww += 1 }   // exact tie → even
						}
					}
					w = ww
				}
			}

			guard w <= UInt64(Int64.max) else { return String(a) }
			let ten: UInt64 = decimals > 0 ? UInt64(StdlibMath.pow10(decimals)) : 1
			let whole = Int64(w / ten)
			let frac = Int64(w % ten)
			var s = String(whole)
			if decimals > 0 {
				var digits = String(frac)
				while digits.count < decimals { digits = "0" + digits }
				s += "." + digits
			}
			return neg ? "-" + s : s
		}

		/// Stdlib `sin` (no libm). Range-reduces to [0, π] then folds into
		/// [0, π/2] and uses a Taylor series — matches libm to ~1e-15 on
		/// [−2π, 2π], far tighter than the 2-decimal SVG output needs.
		static func sin(_ x: Double) -> Double {
			var t = x.truncatingRemainder(dividingBy: 2 * Double.pi)
			if t > Double.pi { t -= 2 * Double.pi } else if t < -Double.pi { t += 2 * Double.pi }
			let positive = t >= 0
			let a = positive ? t : -t
			let s: Double = a <= Double.pi / 2 ? sinTaylor(a) : sinTaylor(Double.pi - a)
			return positive ? s : -s
		}

		static func cos(_ x: Double) -> Double {
			sin(x + Double.pi / 2)
		}

		private static func sinTaylor(_ x: Double) -> Double {
			var term = x
			var s = x
			let x2 = x * x
			for n in 1...24 {
				term *= -x2 / Double((2 * n) * (2 * n + 1))
				s += term
				if abs(term) < 1e-19 { break }
			}
			return s
		}
	}

	// MARK: Line / area

	/// A line path through the given points using the requested interpolation.
	/// Points must be sorted by x (the renderer guarantees this).
	static func linePath(points: [(px: Double, py: Double)], interpolation: InterpolationMethod) -> String {
		guard let first = points.first else { return "" }
		var d = "M\(fmt(first.px)),\(fmt(first.py))"
		switch interpolation {
		case .linear:
			for i in 1..<points.count {
				d += " L\(fmt(points[i].px)),\(fmt(points[i].py))"
			}
		case .stepStart:
			// vertical jump at the start of each segment, then horizontal
			for i in 1..<points.count {
				d += " L\(fmt(points[i - 1].px)),\(fmt(points[i].py)) L\(fmt(points[i].px)),\(fmt(points[i].py))"
			}
		case .stepEnd:
			// horizontal at the previous value, vertical jump at the end
			for i in 1..<points.count {
				d += " L\(fmt(points[i].px)),\(fmt(points[i - 1].py)) L\(fmt(points[i].px)),\(fmt(points[i].py))"
			}
		case .cardinal(let tension):
			// uniform spline → cubic Bézier
			for i in 1..<points.count {
				d += splineSegment(points: points, index: i, k: (1.0 - tension) / 6.0)
			}
		case .catmullRom:
			// Catmull-Rom = uniform spline with fixed 1/6 control offset
			for i in 1..<points.count {
				d += splineSegment(points: points, index: i, k: 1.0 / 6.0)
			}
		case .monotone:
			// Fritsch–Carlsen monotone Hermite: no overshoot between points
			d += monotoneCubics(points)
		}
		return d
	}

	/// One cubic-Bézier segment (points[i-1] → points[i]) of a uniform
	/// cardinal/Catmull-Rom spline, using `k` × (neighbor delta) for the
	/// control offsets.
	private static func splineSegment(points: [(px: Double, py: Double)], index: Int, k: Double) -> String {
		let n = points.count
		let a = points[index - 1]
		let b = points[index]
		let p0 = index - 2 >= 0 ? points[index - 2] : a
		let p3 = index + 1 < n ? points[index + 1] : b
		let c1x = a.px + (b.px - p0.px) * k
		let c1y = a.py + (b.py - p0.py) * k
		let c2x = b.px - (p3.px - a.px) * k
		let c2y = b.py - (p3.py - a.py) * k
		return " C\(fmt(c1x)),\(fmt(c1y)) \(fmt(c2x)),\(fmt(c2y)) \(fmt(b.px)),\(fmt(b.py))"
	}

	/// Fritsch–Carlsen tangents for the interior points, emitted as a chain
	/// of cubic Béziers. Guarantees a monotone curve (no local extrema
	/// between data points) when x is non-decreasing.
	private static func monotoneCubics(_ pts: [(px: Double, py: Double)]) -> String {
		let n = pts.count
		guard n >= 3 else {
			return n == 2 ? " L\(fmt(pts[1].px)),\(fmt(pts[1].py))" : ""
		}
		// per-segment slopes
		var s = [Double]()
		s.reserveCapacity(n - 1)
		for i in 0..<(n - 1) {
			let dx = pts[i + 1].px - pts[i].px
			s.append(dx == 0 ? 0 : (pts[i + 1].py - pts[i].py) / dx)
		}
		// tangent at each point
		var m = [Double](repeating: 0, count: n)
		m[0] = s[0]
		m[n - 1] = s[n - 2]
		for i in 1..<(n - 1) {
			if s[i - 1] == 0 || s[i] == 0 || s[i - 1].sign != s[i].sign {
				m[i] = 0
			} else {
				let dxTotal = pts[i + 1].px - pts[i - 1].px
				m[i] = 3 * dxTotal / ((2 * pts[i + 1].px - pts[i - 1].px) / s[i - 1] + (pts[i + 1].px - pts[i - 1].px) / s[i])
			}
		}
		var d = ""
		for i in 0..<(n - 1) {
			let a = pts[i]
			let b = pts[i + 1]
			let dx = b.px - a.px
			let c1x = a.px + dx / 3
			let c1y = a.py + m[i] * dx / 3
			let c2x = b.px - dx / 3
			let c2y = b.py - m[i + 1] * dx / 3
			d += " C\(fmt(c1x)),\(fmt(c1y)) \(fmt(c2x)),\(fmt(c2y)) \(fmt(b.px)),\(fmt(b.py))"
		}
		return d
	}

	// MARK: Symbols

	/// A small centered symbol (for point marks other than the default
	/// circle). Returns a self-contained SVG shape; the caller wraps it in a
	/// styled `<g>`.
	static func symbolPath(shape: ChartSymbolShape, x: Double, y: Double, size s: Double) -> String {
		switch shape {
		case .none, .circle:
			return ""
		case .square:
			return "<rect x=\"\(fmt(x - s))\" y=\"\(fmt(y - s))\" width=\"\(fmt(2 * s))\" height=\"\(fmt(2 * s))\"/>"
		case .triangle:
			let h = s * 1.1547
			return "<polygon points=\"\(fmt(x)),\(fmt(y - h)) \(fmt(x - s)),\(fmt(y + h / 2)) \(fmt(x + s)),\(fmt(y + h / 2))\"/>"
		case .diamond:
			return "<polygon points=\"\(fmt(x)),\(fmt(y - s * 1.4)) \(fmt(x + s * 1.4)),\(fmt(y)) \(fmt(x)),\(fmt(y + s * 1.4)) \(fmt(x - s * 1.4)),\(fmt(y))\"/>"
		case .cross:
			return "<path d=\"M\(fmt(x - s)),\(fmt(y - s)) L\(fmt(x + s)),\(fmt(y + s)) M\(fmt(x - s)),\(fmt(y + s)) L\(fmt(x + s)),\(fmt(y - s))\"/>"
		case .asterisk:
			return "<path d=\"M\(fmt(x - s)),\(fmt(y)) L\(fmt(x + s)),\(fmt(y)) M\(fmt(x)),\(fmt(y - s)) L\(fmt(x)),\(fmt(y + s)) M\(fmt(x - s * 0.7)),\(fmt(y - s * 0.7)) L\(fmt(x + s * 0.7)),\(fmt(y + s * 0.7)) M\(fmt(x - s * 0.7)),\(fmt(y + s * 0.7)) L\(fmt(x + s * 0.7)),\(fmt(y - s * 0.7))\"/>"
		}
	}

	// MARK: Polar (sector)

	/// An arc path for a pie/donut sector from `startAngle` to `endAngle`
	/// (degrees, 0 = 12 o'clock, clockwise). If `innerRadius` > 0, a donut
	/// (annulus) wedge; otherwise a pie wedge to the center.
	static func sectorPath(centerX cx: Double, centerY cy: Double, innerRadius rIn: Double, outerRadius rOut: Double, startAngle: Double, endAngle: Double) -> String {
		let start = polarPoint(cx: cx, cy: cy, r: rOut, angle: startAngle)
		let end = polarPoint(cx: cx, cy: cy, r: rOut, angle: endAngle)
		let largeArc = (endAngle - startAngle) > 180 ? 1 : 0
		if rIn > 0.5 {
			let innerStart = polarPoint(cx: cx, cy: cy, r: rIn, angle: endAngle)
			let innerEnd = polarPoint(cx: cx, cy: cy, r: rIn, angle: startAngle)
			return "M\(fmt(start.x)),\(fmt(start.y)) "
				+ "A\(fmt(rOut)),\(fmt(rOut)) 0 \(largeArc) 1 \(fmt(end.x)),\(fmt(end.y)) "
				+ "L\(fmt(innerStart.x)),\(fmt(innerStart.y)) "
				+ "A\(fmt(rIn)),\(fmt(rIn)) 0 \(largeArc) 0 \(fmt(innerEnd.x)),\(fmt(innerEnd.y)) Z"
		} else {
			return "M\(fmt(cx)),\(fmt(cy)) "
				+ "L\(fmt(start.x)),\(fmt(start.y)) "
				+ "A\(fmt(rOut)),\(fmt(rOut)) 0 \(largeArc) 1 \(fmt(end.x)),\(fmt(end.y)) Z"
		}
	}

	/// Convert polar (r, angle-degrees-from-12oclock-cw) to cartesian (y-down).
	private static func polarPoint(cx: Double, cy: Double, r: Double, angle: Double) -> (x: Double, y: Double) {
		let rad = (angle - 90) * .pi / 180
		return (cx + r * StdlibMath.cos(rad), cy + r * StdlibMath.sin(rad))
	}

	// MARK: Formatting

	/// Format a viewBox coordinate: up to 2 decimals, trailing zeros
	/// stripped. Never corrupts internal zeros (1.05 stays 1.05).
	static func fmt(_ v: Double) -> String {
		guard v.isFinite else { return "0" }
		var s = StdlibMath.fixed(v, 2)
		while s.hasSuffix("0") { s = String(s.dropLast()) }
		if s.hasSuffix(".") { s = String(s.dropLast()) }
		return s == "-0" ? "0" : s
	}
}
