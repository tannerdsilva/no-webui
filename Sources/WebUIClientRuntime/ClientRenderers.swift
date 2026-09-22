import Synchronization

/// the applet-renderer registry (harness v2). an applet region is a page
/// region the *module* owns: the page marks it `[data-webui-applet]` and the
/// chamber asks this registry to compose it at boot (`webui_render_region`).
/// renderers are registered at boot (see `ClientRuntime.bootApplets`) and run
/// against the resident router, so their controls self-wire like any other
/// page control.
public enum ClientRenderers {
	public typealias Renderer = @Sendable (String) -> String

	private static let table = Mutex<[String: Renderer]>([:])

	/// register (or replace) the renderer for a region name. names are
	/// `applet:view`-shaped; replacement is idempotent (a re-boot re-registers).
	public static func register(_ name: String, _ renderer: @escaping Renderer) {
		table.withLock { $0[name] = renderer }
	}

	/// render a region by name with its JSON args, or `nil` when unregistered.
	public static func render(_ name: String, _ argsJSON: String) -> String? {
		guard let renderer = table.withLock({ $0[name] }) else { return nil }
		return renderer(argsJSON)
	}

	/// registered region names, sorted (diagnostic + gate use).
	public static func names() -> [String] {
		table.withLock { Array($0.keys).sorted() }
	}
}
