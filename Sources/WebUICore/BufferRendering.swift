/// a value that writes itself into a render buffer.
///
/// a stylesheet, a document and a view all write bytes into the same buffer; the
/// first two frame no page element, so neither can be a `View`. this is their
/// shared answer — and since the typed-markup arc `View` refines it, so one
/// materializer serves the whole family.
///
/// `public` since 2.0: ``markup`` is the consumer's door to a rendered value.
/// it shipped `package` while `View.render()` was deprecated, which left a host
/// with no public, non-deprecated way to materialize anything; every host
/// hand-rolled the same three lines instead (`String(decoding: buffer.bytes…)`).
/// a restriction three lines bypass is friction, not a boundary — this is the
/// door the framework owns.
public protocol BufferRendering: Sendable {
	// no `package` on the requirement: a protocol's members inherit its access
	// level, and the modifier is rejected inside a declaration body.
	func render(into buffer: inout HTMLBuffer)
}

extension BufferRendering {
	/// the rendered bytes, as markup the framework vouches for.
	///
	/// the framework's own door: it produces an ``UnsafeMarkup`` without asking
	/// a human to take responsibility, because a render *is* the framework's
	/// responsibility. a caller that wants the string reads `.html` — an
	/// inspection the type permits by design, now attached to a value that says
	/// where it came from.
	public var markup: UnsafeMarkup {
		var buffer = HTMLBuffer()
		render(into: &buffer)
		return .rendered(buffer.finish())
	}
}
