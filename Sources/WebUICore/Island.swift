// MARK: - Capability Islands

/// same-Swift logic that compiles into a small standalone wasm module and is
/// fetched lazily by a page that declares the capability.
///
/// a conformer is *both* sides of the island: `render(_:)` runs on the server
/// for the region's first-render fallback and compiles (via the `wasm-island`
/// verb) into the `webui_render_region` export the engine calls on mount.
/// `name` is the capability grant — the engine fetches
/// `/__assets/webui-<name>.wasm` only when the page's emitted
/// `capabilities` list contains it.
public protocol Island: Sendable {
	/// wires to the capability grant: the engine fetches
	/// `/__assets/webui-<name>.wasm` and mounts every region carrying
	/// `data-webui-island="<name>"` only when the emitted config grants it.
	static var name: String { get }
	/// the region's output for a given input. same swift both sides means
	/// the server-rendered fallback and the wasm mount agree.
	static func render(_ input: String) -> String
}

/// declares the island's capability and mounts a region for it.
///
/// declaring this view is the whole wiring: `WebUIDocument` collects the
/// capability names out of the rendered body and folds them into the emitted
/// `RuntimeConfig`, so the engine's existing lazy fetch grants and mounts the
/// region with no further step. the region renders `I.render(input)` server
/// side as its first-render fallback — an absent artifact degrades to that
/// markup (`data-webui-island-state="unmapped"`) and the page stays fully
/// server-rendered.
public struct IslandRegion<I: Island>: View {
	private let input: String

	public init(_ input: @autoclosure () -> String) {
		self.input = input()
	}

	public func render(into buffer: inout HTMLBuffer) {
		// the single-quoted args attribute follows the engine's region
		// contract (`data-webui-args` is JSON the module parses; the mount
		// envelope is `{name, args}`), and everything is escaped — the JSON
		// first, then the whole attribute value, so a hostile input cannot
		// break the attribute no matter which quote it carries.
		let argsJSON = "{\"input\":" + Self.jsonString(input) + "}"
		buffer.append("<div data-webui-island=\"\(htmlEscape(I.name))\" data-webui-args='\(htmlEscape(argsJSON))'>")
		buffer.append(I.render(input))
		buffer.append("</div>")
	}

	/// a foundation-free json string literal (WebUICore never imports
	/// Foundation): backslash and quote escaped, control characters as
	/// `\uXXXX` — the same hand-rolled encoder `RuntimeConfig` uses.
	private static func jsonString(_ string: String) -> String {
		var result = "\""
		for scalar in string.unicodeScalars {
			switch scalar {
			case "\\": result += "\\\\"
			case "\"": result += "\\\""
			case "\n": result += "\\n"
			case "\r": result += "\\r"
			case "\t": result += "\\t"
			case "\0": result += "\\u0000"
			default:
				if scalar.value < 0x20 {
					result += "\\u" + Self.hex4LowerCase(scalar.value)
				} else {
					result.unicodeScalars.append(scalar)
				}
			}
		}
		result += "\""
		return result
	}

	/// 4 lowercase zero-padded hex digits of a unicode scalar value (the
	/// `\uXXXX` half of a foundation-free json escape).
	private static func hex4LowerCase(_ value: UInt32) -> String {
		let digits = Array("0123456789abcdef")
		func d(_ shift: UInt32) -> Character { digits[Int((value >> shift) & 0xf)] }
		return String([d(12), d(8), d(4), d(0)])
	}
}
