import Foundation
import Testing
import WebUI
import WebUICore
import WebUIDesignSystem

// MARK: - the resizable-island contract (rev 2, sibling protocol)
//
// `Island` is frozen surface: the width-aware door is a refinement, not a
// requirement added to the base protocol. these tests pin the region markup,
// the server-side `width == nil` fact, and the byte-identity of the base
// region view after the shared-emitter refactor.

/// a resizable conformer that renders the width it was given, so the test
/// reads the contract off the output rather than off shared mutable state.
struct RecordingWidthIsland: ResizableIsland {
	static let name = "width-probe-test"
	static func render(_ input: String) -> String { render(input, width: nil) }
	static func render(_ input: String, width: Int?) -> String {
		"<span data-width=\"\(width.map(String.init) ?? "nil")\">\(htmlEscape(input))</span>"
	}
}

/// a base conformer for the byte-identity pin.
struct GoldIsland: Island {
	static let name = "gold"
	static func render(_ input: String) -> String { "<b>\(htmlEscape(input))</b>" }
}

@Suite("resizable islands")
struct ResizeContractTests {

	@Test("ResizableIslandRegion emits the resize flag and the mount attributes")
	func resizableRegionAttributes() {
		let html = ResizableIslandRegion<RecordingWidthIsland>("seed").markup.html
		#expect(html.hasPrefix("<div "))
		#expect(html.contains("data-webui-island=\"width-probe-test\""))
		#expect(html.contains("data-webui-island-resize=\"true\""))
		#expect(html.hasSuffix("</div>"))
	}

	@Test("the server render passes width nil — the width is a client fact")
	func serverRenderHasNoWidth() {
		let html = ResizableIslandRegion<RecordingWidthIsland>("seed").markup.html
		#expect(html.contains("data-width=\"nil\""))
	}

	@Test("the region carries the engine's args envelope with the input under 'input'")
	func resizableRegionArgsEnvelope() throws {
		let html = ResizableIslandRegion<RecordingWidthIsland>("hello world").markup.html
		let decoded = try #require(IslandTests.decodedArgs(from: html))
		let object = try #require(
			try JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: String]
		)
		#expect(object == ["input": "hello world"])
	}

	@Test("IslandRegion output is byte-identical to the pre-sibling markup")
	func baseRegionByteIdentity() {
		// the emitter refactor must not move a byte of the frozen view's
		// output: this expectation is the old construction, written out.
		let input = "say \"hi\" & <bye>"
		let argsJSON = "{\"input\":" + goldenJSONString(input) + "}"
		let expected = "<div data-webui-island=\"gold\" data-webui-args='\(htmlEscape(argsJSON))'><b>\(htmlEscape(input))</b></div>"
		let actual = IslandRegion<GoldIsland>(input).markup.html
		#expect(actual == expected)
	}

	@Test("a ResizableIsland is usable as an Island (refinement, not replacement)")
	func refinementCompiles() {
		func takesAnIsland<I: Island>(_ type: I.Type) -> String { I.name }
		#expect(takesAnIsland(RecordingWidthIsland.self) == "width-probe-test")
	}
}

// the pre-refactor json-string encoder, reproduced for the golden pin.
private func goldenJSONString(_ string: String) -> String {
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
				result += "\\u" + String(format: "%04x", scalar.value)
			} else {
				result.unicodeScalars.append(scalar)
			}
		}
	}
	result += "\""
	return result
}