// MARK: - the chart-spec proof type
//
// the first typed payload: a chart series that compiles into an island. it is
// deliberately *variable-length* — a title and an arbitrary number of values —
// because that is where string marshaling actually costs (a json number array
// is ~4x the bytes and a parse; a length-prefixed f64 run is neither).
//
// layout (big-endian, the house wire convention):
//	u16  title utf-8 byte count
//	bytes title
//	u16  value count
//	f64  value * count   (bit patterns, so NaN payloads survive round trips)
//
// encode clamps both counts at UInt16.max; a title whose bytes are cut
// mid-scalar fails the strict decode on the island, which lands on the
// server-rendered fallback — the safe degrade, never a crash.

import WebUIIslandWire
import WebUISharedCore

public struct ChartSpec: Sendable, Equatable {
	public var title: String
	public var values: [Double]

	public init(title: String, values: [Double]) {
		self.title = title
		self.values = values
	}
}

extension ChartSpec: IslandPayloadEncodable, IslandPayloadDecodable {
	public func islandEncode(count: inout Int) {
		count = encodedByteCount
	}

	@discardableResult
	public func islandEncode(_: UnsafeMutableRawPointer.Type, destination: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
		var cursor = destination
		let titleBytes = title.utf8
		let titleCount = min(titleBytes.count, Int(UInt16.max))
		Self.writeU16(UInt16(titleCount), to: &cursor)
		var written = 0
		for byte in titleBytes {
			guard written < titleCount else { break }
			cursor.storeBytes(of: byte, as: UInt8.self)
			cursor = cursor.advanced(by: 1)
			written += 1
		}
		let valueCount = min(values.count, Int(UInt16.max))
		Self.writeU16(UInt16(valueCount), to: &cursor)
		for index in 0..<valueCount {
			cursor.storeBytes(of: values[index].bitPattern.bigEndian, as: UInt64.self)
			cursor = cursor.advanced(by: 8)
		}
		return cursor
	}

	public init?(islandDecode buffer: UnsafeRawBufferPointer) {
		guard buffer.count >= 2 else { return nil }
		let titleCount = Int(Self.readU16(buffer, 0))
		var offset = 2
		guard titleCount <= buffer.count - offset else { return nil }
		guard let title = IslandUTF8.decode(UnsafeRawBufferPointer(rebasing: buffer[offset ..< offset + titleCount])) else {
			return nil
		}
		offset += titleCount
		guard buffer.count - offset >= 2 else { return nil }
		let valueCount = Int(Self.readU16(buffer, offset))
		offset += 2
		// exact consumption: every remaining byte is one of the declared f64s
		guard buffer.count - offset == valueCount * 8 else { return nil }
		var values: [Double] = []
		values.reserveCapacity(valueCount)
		for index in 0..<valueCount {
			values.append(Double(bitPattern: Self.readU64(buffer, offset + index * 8)))
		}
		self.init(title: title, values: values)
	}

	private var encodedByteCount: Int {
		let titleCount = min(title.utf8.count, Int(UInt16.max))
		let valueCount = min(values.count, Int(UInt16.max))
		return 2 + titleCount + 2 + valueCount * 8
	}

	private static func writeU16(_ value: UInt16, to cursor: inout UnsafeMutableRawPointer) {
		cursor.storeBytes(of: value.bigEndian, as: UInt16.self)
		cursor = cursor.advanced(by: 2)
	}

	private static func readU16(_ buffer: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
		UInt16(bigEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
	}

	private static func readU64(_ buffer: UnsafeRawBufferPointer, _ offset: Int) -> UInt64 {
		UInt64(bigEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
	}
}

// MARK: - the shared chart renderer

/// the render logic both sides run: the host for the region fallback
/// (`width: nil`) and the wasm module for the mount and every resize
/// re-render. no floating-point library calls — coordinates are integer
/// truncations, so the embedded link needs nothing beyond the core runtime.
public enum ChartSpecIsland {
	public static func render(_ spec: ChartSpec, width: Int?) -> String {
		let canvasWidth = max(160, min(width ?? 320, 4096))
		let canvasHeight = 120
		let bottom = 8
		let plotHeight = canvasHeight - bottom - 8
		let count = spec.values.count
		let maxValue = spec.values.max() ?? 0
		var html = "<figure class=\"island-chart\" data-chart-width=\"\(canvasWidth)\">"
		html += "<svg viewBox=\"0 0 \(canvasWidth) \(canvasHeight)\" width=\"100%\" height=\"\(canvasHeight)\" role=\"img\">"
		if count > 0, maxValue > 0 {
			let slot = Double(canvasWidth) / Double(count)
			let barWidth = max(2, Int(slot * 0.72))
			for (index, value) in spec.values.enumerated() {
				let ratio = max(0, min(1, value / maxValue))
				let height = Int(Double(plotHeight) * ratio)
				let x = Int(Double(index) * slot) + max(0, (Int(slot) - barWidth) / 2)
				let y = canvasHeight - bottom - height
				html += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(barWidth)\" height=\"\(height)\" fill=\"currentColor\"/>"
			}
		}
		html += "</svg>"
		if !spec.title.isEmpty {
			html += "<figcaption>\(htmlEscape(spec.title))</figcaption>"
		}
		html += "</figure>"
		return html
	}
}