import WebUIChartSpec
import WebUIIslandRuntime

// arc b's proof product: a typed chart spec arrives as a versioned rawdog
// frame inside the mount envelope, decodes without a json parse, and renders
// at the engine-measured container width. the shared harness owns the wasi
// plumbing; this product owns the render hook.
@main
struct WebUIChartIsland {
	static func main() {
		#if os(WASI)
		TypedIslandEntry.installResizable(ChartSpec.self, render: ChartSpecIsland.render)
		#endif
	}
}