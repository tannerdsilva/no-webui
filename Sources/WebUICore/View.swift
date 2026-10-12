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
public protocol ViewModifier: Sendable {
    func apply(to html: String) -> String

    /// apply this modifier to `content` through the render buffer, so a
    /// migrated modifier writes its attributes into the buffer instead of
    /// re-parsing finished html (the S2 win). a requirement for the same
    /// reason as `View.render(into:)`; the default lives in `ModifiedView.swift`
    /// and applies to the content's string render.
    func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer)
}

// MARK: - EmptyView
public struct EmptyView: View {
    public init() {}
    public func render(into buffer: inout HTMLBuffer) { buffer.append("") }
}
