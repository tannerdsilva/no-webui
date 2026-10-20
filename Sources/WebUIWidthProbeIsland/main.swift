import WebUIIslandCore
import WebUISharedCore

// the width-probe capability island: the reference product for the resizable
// contract. ~10 lines — the shared `IslandEntry` harness owns the wasi
// plumbing, and this product owns only its logic.
@main
struct WebUIWidthProbeIsland {
	static func main() {
		#if os(WASI)
		IslandEntry.render = { argsJSON in
			WidthProbeIsland.render(argsJSON: argsJSON)
		}
		#endif
	}
}