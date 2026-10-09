/// a value that writes itself into a render buffer but is not a ``View``.
///
/// a stylesheet and a document both write bytes into the same buffer a view
/// writes into, and neither frames a page element — so neither can be a `View`,
/// and neither can use `View.renderThroughBuffer()`. this is their shared
/// answer, and the reason it exists rather than four copies of the same three
/// lines: the 2.0 flip made `render(into:)` the primary route everywhere, and a
/// caller that genuinely needs a finished `String` (a theme sheet, a
/// reachability scan, the asset tool's minifier, a document handed to a server)
/// should be able to say so the same way.
///
/// `package`, not `public`: the convenience has to cross target boundaries
/// inside this package while staying out of the published API.
package protocol BufferRendering: Sendable {
    // no `package` on the requirement: a protocol's members inherit its access
    // level, and the modifier is rejected inside a declaration body.
    func render(into buffer: inout HTMLBuffer)
}

extension BufferRendering {
    /// the bytes as a string — the convenience for callers that need one.
    package func renderedString() -> String {
        var buffer = HTMLBuffer()
        render(into: &buffer)
        return String(decoding: buffer.bytes, as: UTF8.self)
    }
}
