// MARK: - View Protocol
public protocol View: Sendable {
    func render() -> String

    /// write this view into a shared render buffer.
    ///
    /// this is a protocol *requirement* with a default below — deliberately not
    /// a plain extension method. an extension method resolves statically, so a
    /// migrated view's override would never run through `any View` or a generic
    /// call and the migration would silently be dead code (pinned by the
    /// dispatch probes in `RenderIntoBufferTests`). the default is what keeps
    /// the requirement additive: a view that implements only `render()` keeps
    /// rendering its string.
    func render(into buffer: inout HTMLBuffer)
}

extension View {
    /// the fallback for a view that has not migrated: its string render.
    public func render(into buffer: inout HTMLBuffer) {
        buffer.append(render())
    }

    /// render through the buffer and materialize the string — the transition
    /// body a migrated view's `render()` uses until the 2.0 flip makes
    /// `render(into:)` the requirement and deprecates `render()`. the
    /// conforming type's own `render(into:)` wins here because the call below
    /// is a requirement.
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
    public func render() -> String { "" }
}