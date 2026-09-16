import Foundation

/// the client-mode boot configuration emitted by `HTMLDocument(clientMode:)`
/// and `WebUIDocument(clientMode:)`.
///
/// the caller supplies the content-addressed wasm url (`WebUIBoot.wasmHash`
/// helps compute it); the framework emits the `<meta name="webui-wasm">`
/// contract plus the external chamber/boot script tags — serving those routes
/// stays the host server's job. `mode` selects the hydration-compat render
/// vs the full interactive boot; `config` channels only-set `RuntimeConfig`
/// knobs (transport knobs stay js-owned; behavior knobs ride through to the
/// wasm boot, trajectory w§2.1.11).
public struct ClientBoot: Sendable {
	/// the boot flavor the chamber performs against the served artifact.
	public enum Mode: Sendable {
		/// ssr-compat: the wasm renders the hydration view for byte-identity
		/// verification (demo/probe use).
		case hydrate
		/// full interactive boot: resident router + local handlers (default).
		case app
	}

	/// the default chamber + boot script routes a client-mode page references.
	/// hosts that serve under different prefixes (the demo servers use
	/// `/__assets/…`) pass their own urls.
	public static let defaultScriptURLs: [String] = [
		"/ui/webui-client.js",
		"/ui/webui-app-boot.js",
	]

	/// the client-mode csp (trajectory w§3.7): `'self'` + `'wasm-unsafe-eval'`,
	/// never `'unsafe-inline'` in script-src. used when the caller provides no
	/// explicit policy.
	public static let defaultCSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"

	public let wasmURL: String
	public let mode: Mode
	public let config: RuntimeConfig?
	public let scriptURLs: [String]

	public init(
		wasmURL: String,
		mode: Mode = .app,
		config: RuntimeConfig? = nil,
		scriptURLs: [String] = ClientBoot.defaultScriptURLs
	) {
		self.wasmURL = wasmURL
		self.mode = mode
		self.config = config
		self.scriptURLs = scriptURLs
	}

	/// the `<head>` slot markup a client-mode page carries: the `webui-wasm`
	/// meta contract, the external chamber/boot script tags, and (when a
	/// config is present) the only-set `webui-config` meta the chamber's boot
	/// glue reads for the a4 knob split.
	public func headMarkup() -> String {
		var parts: [String] = []
		parts.append("<meta name=\"webui-wasm\" content=\"\(htmlEscape(wasmURL))\">")
		for url in scriptURLs {
			parts.append("<script src=\"\(htmlEscape(url))\"></script>")
		}
		if let config, !config.isEmpty {
			parts.append("<meta name=\"webui-config\" content=\"\(htmlEscape(config.encodedJSON()))\">")
		}
		return parts.joined(separator: "\n")
	}
}
