import Foundation
import WebUIBuild
import WebUIDesignSystemCore

// MARK: - WebUIThemeBuild
//
// the host-side library the DX-15a pipeline runs: a consumer's `ThemeCatalog`
// becomes a rendered, stamped, gzipped `WebUIShippedAsset` conformance through
// the SAME emitter the framework's own assets ride (WebUIAssetBuilder). the
// plugin/tool driven by lane T (mechanism (a): a framework build-tool plugin
// that spawns a direct `swiftc` over the consumer's theme sources — spike
// verdict `dx2-notes/t-theme-spike-verdict.md`) calls this; a ≤3-line consumer
// shim would call the same function under mechanism (b).
//
// host-only by construction (like WebUIBuild): it links the emitter and the
// theme vocabulary, so a consumer target that imports it is a build-time host,
// never shipped bytes.

/// the theme-emission entry point: render a consumer catalog to a sheet and
/// emit it as a `WebUIShippedAsset` conformance.
public enum WebUIThemeBuild {

	/// render `catalog` to its scoped stylesheet and emit a generated
	/// `WebUIShippedAsset` conformance named `typeName` into `url`.
	///
	/// - catalog: the consumer's `ThemeCatalog` type (its providers may be
	///   `@Theme`-derived or hand-written — the twin — both flow through the
	///   same path).
	/// - typeName: the emitted type's name; the consumer's server references
	///   it via `WebUIAsset(_:path:)` exactly like any other registered asset.
	/// - options: the emitter options (`WebUIAssetBuilder.Options` — minify,
	///   prose policy, and the served `Content-Type`).
	/// - url: where the generated Swift source is written.
	/// - returns: the build receipt (`WebUIBuild.Emitted`) — bytes, gzip size
	///   and the content-addressed stamp.
	@discardableResult
	public static func emit(
		catalog: any ThemeCatalog.Type,
		typeName: String,
		options: WebUIAssetBuilder.Options,
		to url: URL
	) throws -> WebUIBuild.Emitted {
		// the sheet is the catalog's scoped stylesheet, rendered once and
		// byte-stable across runs (ThemeCatalog.stylesheet sorts declarations
		// and rules deterministically — the same property that makes the
		// framework's own content-addressed theme cache safe).
		let css = catalog.stylesheet()
		return try WebUIAssetBuilder.emit(
			shipped: css,
			typeName: typeName,
			options: options,
			to: url
		)
	}
}
