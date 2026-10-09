// the typed escape hatches (W2.3).
//
// shipping bytes into a page from a call site is the one thing the framework
// cannot verify — so it is the one thing that must be loud. `UnsafeMarkup` has no
// public initializer: the only way to obtain one is `.trusted(_:)`. that makes
// every unverified byte in a page one grep away, and `UnsafeMarkup.trusted` names
// the exact lines where someone took responsibility.

/// html known to be safe by construction.
///
/// the only way to obtain one is ``trusted(_:)`` — an explicit, grep-able act —
/// or a value the framework itself produced (a sanitizer, or a `View`'s own
/// render).
public struct UnsafeMarkup: Sendable, Equatable {
    /// the markup, verbatim.
    ///
    /// readable so a host can inspect what it trusted; there is deliberately no
    /// public initializer, so it cannot be *created* from outside.
    public let html: String

    private init(_ html: String) { self.html = html }

    /// take responsibility for these bytes.
    public static func trusted(_ html: String) -> UnsafeMarkup { UnsafeMarkup(html) }
}

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

    public func render() -> String { markup.html }

    /// the buffer route appends the caller's bytes verbatim — `Raw`'s contract —
    /// and `render()` stays direct for the same reason as `Text`: no element is
    /// framed, so a round trip would buy nothing. a modifier wrapping `Raw`
    /// settles against this fragment (its own scan, never the page).
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