import WebUI

/// design-system assets derived from the embedded working files.
public enum DesignSystemAssets {
	/// `design-system.css`, minified once. the reference servers serve this on
	/// their `/__assets/css` endpoint instead of the raw working file, which
	/// carries designer comments (the first law: shipped web assets are
	/// comment-free) and roughly 6% more bytes on a constrained link.
	public static let minifiedCss: String = minifyCSS(WebUIAssets.css)

	/// eagerly initialise the hoisted minified sheets so the one-time minify
	/// cost (~10 ms) never lands inside a request handler. servers call this
	/// once at startup.
	public static func prewarm() {
		_ = minifiedCss
		_ = WebUIDocument.minifiedDesignStyles
	}
}
