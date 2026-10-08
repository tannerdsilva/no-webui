// MARK: - RenderSessionID

/// the identity of one rendered page instance.
///
/// component ids are minted *within* a session and a message is only ever routed
/// back into the session that minted it, so two pages can reuse the same id space
/// without ever sharing a handler. that is what makes a re-render idempotent
/// (same mint order → same ids → dictionary assignment) instead of a leak.
///
/// before sessions existed the mint counter lived on the router and only ever
/// incremented: every render of every page appended a fresh `c0…cN` range, so a
/// long-lived server grew its handler table until the cap and then silently
/// stopped routing. see `RouterSoakTests`.
public struct RenderSessionID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// the session every session-less call site shares — the 1.x behaviour,
    /// preserved so existing hosts and tests are unaffected.
    public static let `default` = RenderSessionID("__default__")

    public var description: String { rawValue }
}