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

	/// The default policy with this render's nonce authorised for inline scripts, plus any
	/// host directives (`extras`) merged per name.
	///
	/// `defaultCSP` names no `'nonce-…'` source, so it *blocks* any inline script —
	/// including the pre-paint theme prelude `HTMLDocument` emits carrying a nonce.
	/// measured: the browser smoke gate and the block sweeps both reported the
	/// `script-src 'self' 'wasm-unsafe-eval'` violation and the prelude never ran, so
	/// the served default policy carries the render's nonce. a host that passes its
	/// whole own policy keeps it, and `HTMLDocument` skips the prelude in that case rather
	/// than emitting a script the browser will refuse — which is exactly why a host that
	/// needs one more directive should extend the default with `extras` instead.
	public static func csp(nonce: String, extras: String? = nil) -> String {
		merging(
			policy: defaultCSP.replacingOccurrences(
				of: "script-src 'self' 'wasm-unsafe-eval';",
				with: "script-src 'self' 'wasm-unsafe-eval' 'nonce-\(nonce)';"
			),
			extras: extras
		)
	}

	/// Merge host directives into a policy, by name.
	///
	/// Repeating a directive name inside one policy is undefined — a client may honour
	/// either — so an extra **replaces** the base's directive of that name, and every name
	/// the host did not mention is carried over untouched, including the nonce
	/// `csp(nonce:)` installed. That is what lets a host add `img-src`/`font-src` without
	/// losing the pre-paint theme prelude to a policy that names no nonce source.
	///
	/// Emitted in base order with new directives appended, so the same inputs render the
	/// same bytes — the sheet's content-addressing argument applies to a policy too.
	static func merging(policy: String, extras: String?) -> String {
		guard let extras, !extras.isEmpty else { return policy }
		var order: [String] = []
		var values: [String: String] = [:]
		func absorb(_ source: String) {
			for part in source.split(separator: ";") {
				let piece = part.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !piece.isEmpty else { continue }
				let name = piece.prefix(while: { $0 != " " }).lowercased()
				let value = piece.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines)
				if values[name] == nil { order.append(name) }
				values[name] = value
			}
		}
		absorb(policy)
		absorb(extras)
		return order.map { name in
			guard let value = values[name], !value.isEmpty else { return name }
			return "\(name) \(value)"
		}.joined(separator: "; ") + ";"
	}

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