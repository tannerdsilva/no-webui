import Foundation

// MARK: - WebUIRuntime

public enum WebUIRuntime {
	public static let source: String = WebUIAssets.js
	public static let bootstrap: String = """
	WebUIRuntime.init();
	"""

	public static func bootstrap(config: RuntimeConfig?) -> String {
		guard let config, !config.isEmpty else { return bootstrap }
		return "WebUIRuntime.init(\(config.encodedJSON()));\n"
	}
}
