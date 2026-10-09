// MARK: - View Protocol
public protocol View: Sendable {
    /// write this view into a shared render buffer.
    ///
    /// the one requirement, since the 2.0 flip: a view writes bytes, and a
    /// caller that wants a string asks for one (``renderThroughBuffer()`` inside
    /// this package, the deprecated ``render()`` outside it).
    ///
    /// a requirement rather than a plain extension method, deliberately: an
    /// extension method resolves statically, so a view's own implementation would
    /// never run through `any View` or a generic call, and the work would be
    /// silently dead code (pinned by the dispatch probes in
    /// `RenderIntoBufferTests`).
    func render(into buffer: inout HTMLBuffer)
}

extension View {
    /// the 1.x spelling: render into a buffer and materialize the string.
    ///
    /// deprecated. implement `render(into:)` and let the caller choose the shape
    /// — the requirement is the contract, this is the migration signal. it stays
    /// through 1.x so existing call sites keep compiling and rendering
    /// byte-identically.
    @available(*, deprecated, message: "implement render(into:) instead — render() is materialized from the buffer")
    public func render() -> String {
        renderThroughBuffer()
    }

    /// render through the buffer and materialize the string — for callers inside
    /// this package that want the string without tripping the deprecation.
    package func renderThroughBuffer() -> String {
        var buffer = HTMLBuffer()
        render(into: &buffer)
        return buffer.finish()
    }
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