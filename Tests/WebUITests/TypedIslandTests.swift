import Testing
import WebUI
import WebUICore
import WebUIIslandWire
import WebUIChartSpec

// the typed region's job: declare the capability, encode the input as a
// frame inside the args attribute, and render the same swift the island will
// run as the server-side fallback. the conformers here live *outside* the
// framework — the same shape a consumer package writes.

private struct TypedChartIsland: TypedIsland {
	static let name = "typed-chart"
	static func render(_ input: ChartSpec) -> String {
		ChartSpecIsland.render(input, width: nil)
	}
}

private struct TypedResizableChartIsland: TypedResizableIsland {
	static let name = "typed-resizable-chart"
	static func render(_ input: ChartSpec, width: Int?) -> String {
		ChartSpecIsland.render(input, width: width)
	}
}

@Suite("typed island region")
struct TypedIslandRegionTests {
	private let spec = ChartSpec(title: "series", values: [3, 5])

	@Test("a typed region declares the capability and carries the frame")
	func regionMarkup() {
		let html = TypedIslandRegion<TypedChartIsland>(spec).markup.html
		#expect(html.contains("data-webui-island=\"typed-chart\""))
		// the args object is html-escaped, so its quotes arrive as entities
		#expect(html.contains("data-webui-args='{&quot;frame&quot;:&quot;"))
		#expect(!html.contains("data-webui-island-resize"))
		#expect(html.contains(IslandEnvelope.encode(spec)))
		// the fallback is the nil-width render
		#expect(html.contains("data-chart-width=\"320\""))
	}

	@Test("a typed resizable region carries the watch flag and the nil-width fallback")
	func resizableRegionMarkup() {
		let html = TypedResizableIslandRegion<TypedResizableChartIsland>(spec).markup.html
		#expect(html.contains("data-webui-island=\"typed-resizable-chart\""))
		#expect(html.contains("data-webui-island-resize=\"true\""))
		#expect(html.contains("data-chart-width=\"320\""))
	}

	@Test("the frame embedded in the region decodes back to the input")
	func regionFrameDecodes() {
		let armored = IslandEnvelope.encode(spec)
		let mount: (payload: ChartSpec, width: Int?)? = IslandEnvelope.decodeMount("{\"frame\":\"\(armored)\",\"width\":774}")
		#expect(mount?.payload == spec)
		#expect(mount?.width == 774)
	}

	@Test("the fallback escapes a hostile title")
	func fallbackEscapesTitle() {
		let hostile = ChartSpec(title: "<script>alert(1)</script>", values: [1])
		let html = TypedIslandRegion<TypedChartIsland>(hostile).markup.html
		#expect(!html.contains("<script>"))
		#expect(html.contains("&lt;script&gt;"))
	}

	@Test("the renderer honors a measured width")
	func measuredWidth() {
		let html = ChartSpecIsland.render(spec, width: 774)
		#expect(html.contains("data-chart-width=\"774\""))
		#expect(html.contains("viewBox=\"0 0 774 120\""))
	}

	@Test("the renderer keeps a sane canvas for absent or absurd widths")
	func widthBounds() {
		#expect(ChartSpecIsland.render(spec, width: nil).contains("data-chart-width=\"320\""))
		#expect(ChartSpecIsland.render(spec, width: 0).contains("data-chart-width=\"160\""))
		#expect(ChartSpecIsland.render(spec, width: 99_999).contains("data-chart-width=\"4096\""))
	}
}