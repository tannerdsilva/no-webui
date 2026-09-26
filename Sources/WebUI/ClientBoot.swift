import Foundation

/// the client boot configuration emitted by `HTMLDocument(clientMode:)` and
/// `WebUIDocument(clientMode:)`.
///
/// the engine is the framework's client runtime: this emits the `webui-config`
/// meta (the boot glue reads it during script execution, so it must precede the
/// script tag) and the engine script. capability islands are declared per page.
///
/// the wasm monolith boot this type used to describe (`flavor: .wasm`, the
/// chamber plus a content-addressed 55 mb artifact) was deleted: it fetched and
/// instantiated that module on every app-mode page for work a ~37 kb runtime
/// does, and it could not render server views. see `NEXT_ARCHITECTURE.md`.
public struct ClientBoot: Sendable {
	/// the route the engine boot references.
	public static let defaultEngineScriptURL = "/ui/webui-engine.js"

	/// the csp for a page that boots the engine and may load a wasm capability
	/// island (`wasm-unsafe-eval` is required to instantiate one). a page with no
	/// island capability still carries it today; scoping it per declared
	/// capability is a follow-up.
	public static let defaultCSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"

	/// only-set `RuntimeConfig` knobs. behavior knobs ride through to the boot;
	/// transport knobs (debounce, reconnect) stay runtime-owned.
	public let config: RuntimeConfig?

	public init(config: RuntimeConfig? = nil) {
		self.config = config
	}

	/// the `<head>` slot markup: the config meta (always emitted, `{}` when
	/// empty, so the engine's meta-driven auto-boot always fires) then the
	/// engine script.
	public func headMarkup() -> String {
		var parts: [String] = []
		if let config, !config.isEmpty {
			parts.append("<meta name=\"webui-config\" content=\"\(htmlEscape(config.encodedJSON()))\">")
		} else {
			parts.append("<meta name=\"webui-config\" content=\"{}\">")
		}
		parts.append("<script src=\"\(htmlEscape(Self.defaultEngineScriptURL))\"></script>")
		return parts.joined(separator: "\n")
	}
}