// the view-level escape hatch.
//
// every byte that reaches a page is escaped by the framework's encoders except
// through this one type: `Raw` emits its payload verbatim. the payload is the
// leaf's trust token, `UnsafeMarkup` (from `WebUISharedCore`) — the only public
// way to obtain one is `.trusted(_:)`, which makes the lines where someone took
// responsibility for unescaped bytes one grep away.

/// a view whose content is emitted verbatim, with no escaping.
public struct Raw: View {
    /// the trusted payload.
    public let markup: UnsafeMarkup

    /// 2.0's primary initializer: the call site says out loud that it is
    /// bypassing escaping.
    public init(_ markup: UnsafeMarkup) { self.markup = markup }

    /// the 1.x initializer.
    ///
    /// kept — and deprecated — because every 1.x call site still has to compile;
    /// the deprecation warning is the migration instruction, and the fix is one
    /// word (`Raw(UnsafeMarkup.trusted(...))`).
    @available(*, deprecated, message: "wrap in UnsafeMarkup.trusted(_:) to make the trust explicit")
    public init(_ content: String) { self.markup = .trusted(content) }

    /// the 1.x spelling of the payload, kept for source compatibility.
    @available(*, deprecated, renamed: "markup")
    public var content: String { markup.html }

    /// the buffer route appends the caller's bytes verbatim — `Raw`'s contract.
    /// no element is framed, so there is nothing for a modifier to settle
    /// against on the page: a modifier wrapping `Raw` scans this fragment alone.
    public func render(into buffer: inout HTMLBuffer) { buffer.append(markup.html) }
}

/// the document's base writing direction.
///
/// it lives here, beside ``Raw``, rather than in the design system's vocabulary
/// where W1 first declared it: `HTMLDocument` is in the core-facing module and
/// cannot see the design system (that module imports this one, never the
/// reverse), and a second `Directionality` for the document would be exactly the
/// duplicate-type defect W1 existed to remove. the design system re-exports it,
/// so the name reads the same from either import.
public enum Directionality: String, Sendable, CaseIterable {
    case ltr, rtl
}