import WebUI

// MARK: - ThemeSheet

/// A rendered theme catalog, addressed by its own content.
///
/// The point of the address is caching: a rebuilt sheet is a *different url*, so the response
/// can be immutable for a year and no consumer ever needs cache invalidation. Without this the
/// theme bytes ride every navigation (the plan's B7), and they grow with the scheme count.
///
/// The host renders it once and hands the same value to the server (which serves `url`) and to
/// the document (which links `url`). Computing the address from the bytes is what guarantees
/// those two agree — a mismatch would be a page linking a sheet the server will not serve,
/// which fails as a 404 in a stylesheet position: silently, and only in the cascade.
public struct ThemeSheet: Sendable, Equatable {
	/// the scoped css, as `ThemeCatalog.stylesheet()` renders it.
	public let css: String
	/// the pre-compressed variant, served when the client accepts `gzip`.
	///
	/// a build product like every other compressed variant in the framework: the runtime
	/// links no compressor, so a host that wants the smaller transfer builds this (e.g. with
	/// `WebUIBuild.gzip`) and hands both forms over. `nil` serves ``css`` to every client.
	public let gzip: [UInt8]?
	/// the content-addressed route, `/__assets/theme.<sha256>`.
	public let url: String

	public init(css: String, gzip: [UInt8]? = nil) {
		self.css = css
		self.gzip = gzip
		self.url = "/__assets/theme.\(SHA256.hex(Array(css.utf8)))"
	}

	/// render a catalog into a sheet.
	public init<T: ThemeCatalog>(catalog: T.Type) {
		self.init(css: T.stylesheet())
	}

	/// true when the catalog rendered nothing (an empty catalog, or every theme `.standard`).
	public var isEmpty: Bool { css.isEmpty }
}
