import Foundation

// MARK: - ChartGeometry

/// Pure geometry helpers: build SVG `d` paths for lines, areas, and polar
/// sectors, and symbol paths. No I/O, fully deterministic.
///
/// Angle convention (polar): 0° = 12 o'clock, increasing = clockwise,
/// y-down screen space. All coordinates are viewBox units.
enum ChartGeometry {

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
		return (cx + r * cos(rad), cy + r * sin(rad))
	}

	// MARK: Formatting

	/// Format a viewBox coordinate: up to 2 decimals, trailing zeros
	/// stripped. Never corrupts internal zeros (1.05 stays 1.05).
	static func fmt(_ v: Double) -> String {
		guard v.isFinite else { return "0" }
		var s = String(format: "%.2f", v)
		while s.hasSuffix("0") { s = String(s.dropLast()) }
		if s.hasSuffix(".") { s = String(s.dropLast()) }
		return s == "-0" ? "0" : s
	}
}
