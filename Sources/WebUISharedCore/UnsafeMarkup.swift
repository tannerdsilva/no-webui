// the typed trust token.
//
// shipping bytes into a page from a call site is the one thing the framework
// cannot verify — so it is the one thing that must be loud. `UnsafeMarkup` has
// no public initializer: the only public way to obtain one is `.trusted(_:)`,
// which makes every unverified byte in a page one grep away.
//
// it lives on the shared leaf rather than in `WebUICore` for one reason:
// `HTTPResponse.Body.html` names it, and the response model sits *below*
// `WebUICore` in the dependency graph. the boundary that must be typed is the
// response, not the view — so the token lives where the boundary does.
// `WebUICore` `@_exported`s this leaf, so every existing `import WebUI`
// consumer sees the type exactly as before.

/// html known to be safe by construction.
public struct UnsafeMarkup: Sendable, Equatable {
	/// the markup, verbatim.
	///
	/// readable so a host can inspect what it trusted; there is deliberately no
	/// public initializer, so it cannot be *created* from outside.
	public let html: String

	private init(_ html: String) { self.html = html }

	/// take responsibility for these bytes.
	///
	/// the only public door into this type, and therefore the only place a
	/// hand-written string becomes a page — greppable by design.
	public static func trusted(_ html: String) -> UnsafeMarkup { UnsafeMarkup(html) }

	/// markup the framework itself produced — a render, a sanitizer.
	///
	/// `package`, not `public`: a host cannot mint trust merely by calling a
	/// framework-named factory. the one public door stays ``trusted(_:)``.
	package static func rendered(_ html: String) -> UnsafeMarkup { UnsafeMarkup(html) }
}
