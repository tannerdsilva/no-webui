// MARK: - shipped assets

// the contract generated asset code conforms to. a build tool produces the bytes, their
// address and their compressed variant as one value; the server (WebUIAsset) derives the
// url a document links and the registration it answers from that same value, so the two
// can never disagree about whether an asset is reachable.

/// an asset a build produced and a server ships: the payload, the address its url carries,
/// and its pre-compressed variant, declared once.
///
/// generated code conforms to this protocol — a consumer's build tool emits one type per
/// asset (`WebUIBuild` + the `WebUIEmbedPlugin` manifest), and the server's `WebUIAsset`
/// turns a conformance into the url a page links and the registration the server answers
/// with. both halves derive from the same bytes, so the class of bug where a page links an
/// address the server does not serve (a stamped path registered instead of a bare one, or
/// the reverse) is not expressible.
///
/// the protocol lives in this foundation-free core because generated code must conform
/// without linking a server, the view dsl, or a client runtime.
public protocol WebUIShippedAsset: Sendable {
	/// the `Content-Type` header value, e.g. `text/css; charset=utf-8`.
	static var contentType: String { get }
	/// the address the url carries: the first 12 hex characters of the sha256 of ``body``
	/// (the `?v=<12 hex>` convention). it changes exactly when the bytes do, which is what
	/// makes a year-long immutable cache safe — a rebuilt asset is a different url.
	static var stamp: String { get }
	/// the payload, exactly as it ships.
	static var body: [UInt8] { get }
	/// the pre-compressed (gzip) variant of ``body``, or `nil` when the build host had no
	/// `gzip`. nothing compresses at runtime: a variant is always a build product, and the
	/// server falls back to ``body`` rather than serving nothing.
	static var gzip: [UInt8]? { get }
}