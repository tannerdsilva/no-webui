// MARK: - width-probe capability island
//
// the reference conformer for the resizable contract: same swift renders the
// server-side fallback (width nil) and the wasm mount (measured width), and
// the region carries a stable `data-probe-width` marker so a gate can assert
// a re-render by reading one attribute.

import WebUISharedCore

public enum WidthProbeIsland {
	/// the region markup: the measured width as a stable attribute, `nil`
	/// before any layout has happened.
	public static func render(_ input: String, width: Int?) -> String {
		let widthText = width.map(String.init) ?? "nil"
		var html = "<div class=\"island island--width-probe\" data-probe-width=\"\(widthText)\">"
		html += "<span class=\"island__msg\">\(htmlEscape(input)) — width \(widthText)px</span>"
		html += "</div>"
		return html
	}

	/// decode the engine's args envelope (`{"input": …, "width": …}`) and
	/// render; malformed json falls back to an empty input with no width.
	///
	/// on the server the region view calls ``render(_:width:)`` directly with
	/// `nil`; on the wasm side this is the harness's render hook.
	public static func render(argsJSON: String) -> String {
		guard let root = try? JSONValue.parse(argsJSON),
		      case .object(let dict) = root else {
			return render("", width: nil)
		}
		var input = ""
		if case .string(let value)? = dict["input"] { input = value }
		var width: Int?
		if case .number(let n)? = dict["width"] {
			width = Int(n)
		} else if case .string(let s)? = dict["width"] {
			width = Int(s)
		}
		return render(input, width: width)
	}
}