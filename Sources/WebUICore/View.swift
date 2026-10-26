// MARK: - View Protocol
/// a renderable page element.
///
/// the requirement is inherited from ``BufferRendering``: a view writes bytes,
/// and a caller that wants the finished markup asks for ``BufferRendering/markup``.
public protocol View: BufferRendering, Sendable {}

extension View {
	/// the 1.x spelling: materialize the markup as a string.
	///
	/// deprecated — ``BufferRendering/markup`` is the 2.0 door and it carries the
	/// trust this spelling threw away. kept so 1.x call sites keep compiling and
	/// rendering byte-identically.
	@available(*, deprecated, message: "use `markup` — `render()` is the 1.x string spelling")
	public func render() -> String { markup.html }
}

// MARK: - ViewModifier Protocol
/// a layer that wraps a rendered view.
///
/// the one requirement is the buffered door: a modifier contributes into the
/// buffer its content renders through — `buffer.mark`, contribute
/// (`addAttribute`) and/or register, render the content, then
/// `settlePendingAttributes(from:)` — so the finished markup is never re-parsed
/// on the way out.
///
/// `apply(to:)` is the compatibility door for callers that already hold a
/// finished string. it is DERIVED from ``decorate(_:into:)`` (see
/// `ModifiedView.swift`), never a second implementation: a modifier has one
/// behaviour, and both doors are that behaviour.
public protocol ViewModifier: Sendable {
    /// apply this modifier to `content` by writing into the render buffer.
    func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)
}

// MARK: - EmptyView
public struct EmptyView: View {
    public init() {}
    public func render(into buffer: inout HTMLBuffer) { buffer.append("") }
}
