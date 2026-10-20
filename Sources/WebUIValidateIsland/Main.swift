import WebUIIslandCore
import WebUISharedCore

// the host build just needs a main (the target is wasm-only in practice);
// the real surface is the wasi exports: the four standard ones live in
// `IslandEntry`, and this product adds `webui_validate` on top.
@main
struct WebUIValidateIsland {
	static func main() {
		#if os(WASI)
		// the engine invokes `_start` (this main) before any export call, so
		// the harness hook is installed before the first render request.
		IslandEntry.render = { argsJSON in
			ValidateIsland.regionHTML(argsJSON: argsJSON)
		}
		#endif
	}
}

#if os(WASI)
// validate's own extra export: input-driven revalidation without a render
// round trip.
@_expose(wasm, "webui_validate")
func webuiValidate(_ ptr: UnsafeRawPointer?, _ len: Int) -> Int {
	guard let ptr, len > 0 else { return 0 }
	let result = ValidateIsland.evaluate(json: IslandEntry.decode(ptr, len))
	return IslandEntry.writeFrame("{\"ok\":\(result.ok),\"message\":\"\(JSONValue.escapeString(result.message))\"}")
}
#endif