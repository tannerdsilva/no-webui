// MARK: - EventOutcome builder helpers (the s-sugar verdict, lane S)
//
// the per-shape outcome helpers: one typed entry point per outcome shape, each
// a one-liner over the frozen generic `control<O: EventOutcome>`. the shape is
// the function's NAME — the no-op case is `noOutcome`, never a silent default —
// and each body spells the conformance it adapts in plain sight, so the
// protocol stays first-class (no hidden grouping, no hidden type).
//
// additive over EventHandling.swift, which remains byte-unchanged: the
// hand-written `control("id") { ... }` spelling keeps compiling, keeps its
// bytes, and keeps its lone-effect guard (a body without an outcome is still a
// compile error at `control`; the Void here is the CALLER's named intent).

/// nothing to send: run `body` for its side effects, yield `NoOutcome()`.
/// the body is `Void` by signature, so "yields nothing" is the entry point's
/// contract, not an inference accident.
public func noOutcome(
    _ id: String,
    event: HTMLEvent = .click,
    _ body: @escaping @Sendable (EventData) async -> Void
) -> String {
    control(id, event: event) { data in
        await body(data)
        return NoOutcome()
    }
}

/// several updates, verbatim; pass a one-element array for a single update.
public func fragments(
    _ id: String,
    event: HTMLEvent = .click,
    _ body: @escaping @Sendable (EventData) async -> [FragmentUpdate]
) -> String {
    control(id, event: event) { data in await body(data) }
}

/// one update — the pre-DX-14 handler shape, sealed as a named entry point.
public func replaceFragment(
    _ id: String,
    event: HTMLEvent = .click,
    _ body: @escaping @Sendable (EventData) async -> FragmentUpdate
) -> String {
    control(id, event: event) { data in await body(data) }
}

/// render `Content` and replace the element carrying `#<id>`.
public func replaceView<Content: View>(
    _ id: String,
    event: HTMLEvent = .click,
    _ body: @escaping @Sendable (EventData) async -> Content
) -> String {
    control(id, event: event) { data in ViewOutcome(await body(data)) }
}

/// declare the change only: `ids` invalidate through the dispatch context.
/// static by design — ids cannot depend on the payload here; the raw seam
/// remains for a payload-dependent selection.
public func invalidate(
    _ id: String,
    event: HTMLEvent = .click,
    ids: [String]
) -> String {
    control(id, event: event) { _ in RegionInvalidations(ids) }
}

/// both, in order — one update AND an invalidation. pins the ordering the
/// live-region demos depend on (the fragment arrives before the region's push).
public func updateThenInvalidate(
    _ id: String,
    ids: [String],
    event: HTMLEvent = .click,
    _ update: @escaping @Sendable (EventData) async -> FragmentUpdate
) -> String {
    control(id, event: event) { data in
        CombinedOutcome(await update(data), RegionInvalidations(ids))
    }
}
