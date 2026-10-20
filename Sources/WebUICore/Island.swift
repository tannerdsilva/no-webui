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

/// an island whose output depends on its container width.
///
/// the engine re-invokes ``render(_:width:)`` when the region's container
/// resizes (and on first mount), passing the measured pixel width; the region
/// carries `data-webui-island-resize="true"` so the engine knows to watch it.
/// server rendering passes `nil` — the width is a *client* fact, and the
/// fallback must render a legible default layout without one.
///
/// one protocol per job: `Island` stays the static region renderer; this
/// refines it with the container-aware door. a requirement added to `Island`
/// instead would have silently no-opped through `any Island` existentials
/// (extension defaults dispatch statically), and `Island` is frozen surface.
public protocol ResizableIsland: Island {
	/// `width` is the measured container width in css pixels, or `nil` when
	/// unknown (server render, no layout yet). implement `nil` as the default
	/// layout — it must render something legible without a width.
	static func render(_ input: String, width: Int?) -> String
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
		buffer.append(islandRegionMarkup(
			name: I.name,
			argsJSON: islandArgsJSON(input),
			resize: false,
			fallback: I.render(input)
		))
	}
}

/// declares a resizable island's capability and mounts its region.
///
/// emits the same markup as ``IslandRegion`` plus
/// `data-webui-island-resize="true"`, which is what the engine watches. the
/// server-rendered fallback is `I.render(input, width: nil)` — the same swift
/// the wasm mount runs once it knows the real width.
public struct ResizableIslandRegion<I: ResizableIsland>: View {
	private let input: String

	public init(_ input: @autoclosure () -> String) {
		self.input = input()
	}

	public func render(into buffer: inout HTMLBuffer) {
		buffer.append(islandRegionMarkup(
			name: I.name,
			argsJSON: islandArgsJSON(input),
			resize: true,
			fallback: I.render(input, width: nil)
		))
	}
}

// MARK: - the shared region emitter
//
// one emitter behind both region views, so their markup cannot drift. the
// single-quoted args attribute follows the engine's region contract
// (`data-webui-args` is JSON the module parses; the mount envelope is
// `{name, args}`), and everything is escaped — the JSON first, then the whole
// attribute value, so a hostile input cannot break the attribute no matter
// which quote it carries.

/// the region div both region views emit.
///
/// `resize` adds the engine's watch flag; nothing else differs between the
/// static and resizable markup, which is what keeps `IslandRegion`'s output
/// byte-identical to its pre-sibling construction.
@discardableResult
package func islandRegionMarkup(name: String, argsJSON: String, resize: Bool, fallback: String) -> String {
	var html = "<div data-webui-island=\"\(htmlEscape(name))\""
	if resize {
		html += " data-webui-island-resize=\"true\""
	}
	html += " data-webui-args='\(htmlEscape(argsJSON))'>"
	html += fallback
	html += "</div>"
	return html
}

/// the engine's mount envelope for a region: `{"input": <json string>}`.
package func islandArgsJSON(_ input: String) -> String {
	"{\"input\":" + islandJSONString(input) + "}"
}

/// a foundation-free json string literal (WebUICore never imports
/// Foundation): backslash and quote escaped, control characters as
/// `\uXXXX` — the same hand-rolled encoder `RuntimeConfig` uses.
private func islandJSONString(_ string: String) -> String {
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
				result += "\\u" + islandHex4LowerCase(scalar.value)
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
private func islandHex4LowerCase(_ value: UInt32) -> String {
	let digits = Array("0123456789abcdef")
	func d(_ shift: UInt32) -> Character { digits[Int((value >> shift) & 0xf)] }
	return String([d(12), d(8), d(4), d(0)])
}