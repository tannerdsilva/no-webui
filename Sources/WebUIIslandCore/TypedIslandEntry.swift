#if os(WASI)

// MARK: - the typed entry installer
//
// a typed product's `main` is one call: install the renderer, and the shared
// harness decodes every mount envelope into the typed payload before handing
// it over. decode failure returns an empty frame, which the engine reads as
// "keep the server-rendered fallback" — the same degrade a missing artifact
// gets, with no new mechanism on the js side.

/// installs a typed region renderer as the artifact's `webui_render_region`.
public enum TypedIslandEntry {
	/// static region: the mount args' frame is the whole input.
	public static func install<T: IslandPayloadDecodable>(_ input: T.Type, render: @escaping (T) -> String) {
		IslandEntry.render = { argsJSON in
			guard let mount: (payload: T, width: Int?) = IslandEnvelope.decodeMount(argsJSON) else {
				return ""
			}
			return render(mount.payload)
		}
	}

	/// resizable region: the mount args carry the engine-measured width beside
	/// the frame, and it rides into the renderer exactly as the server's
	/// `width: nil` fallback expects.
	public static func installResizable<T: IslandPayloadDecodable>(_ input: T.Type, render: @escaping (T, Int?) -> String) {
		IslandEntry.render = { argsJSON in
			guard let mount: (payload: T, width: Int?) = IslandEnvelope.decodeMount(argsJSON) else {
				return ""
			}
			return render(mount.payload, mount.width)
		}
	}
}
#endif