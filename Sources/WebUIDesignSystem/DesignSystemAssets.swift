import WebUI

/// design-system assets derived from the embedded working files.
public enum DesignSystemAssets {
	/// `design-system.css` + the layout rules, minified once — the exact bytes
	/// a page inlines today, now served on `/__assets/css` so browsers (and
	/// the offline shell) can cache them. the reference servers serve this on
	/// their `/__assets/css` endpoint instead of the raw working file, which
	/// carries designer comments (the first law: shipped web assets are
	/// comment-free) and roughly 6% more bytes on a constrained link.
	public static let minifiedCss: String = WebUIAssets.cssMinified

	/// sha-256 (lowercase hex) of the minified sheet — the content address for
	/// the immutable css route. hashed with the framework's own `SHA256` (not
	/// `CryptoKit`, which does not exist on linux).
	public static let cssSHA256: String = SHA256.hex(Array(minifiedCss.utf8))

	/// the content-addressed stylesheet url: `/__assets/css.<sha256>`. pages
	/// link this by default (`WebUIDocument.stylesheetURL`), so a rebuilt
	/// sheet — a different URL — never needs cache invalidation, and the
	/// route can be served `immutable` for a year. hosts that need the old
	/// stable path can still serve `/__assets/css` (see `WebUIServer`).
	public static let stylesheetURL: String = "/__assets/css.\(cssSHA256)"

	/// eagerly initialise the hoisted minified sheets so the one-time minify
	/// cost (~10 ms) never lands inside a request handler. servers call this
	/// once at startup.
	public static func prewarm() {
		_ = minifiedCss
		_ = cssSHA256
		_ = WebUIDocument.minifiedDesignStyles
	}
}
