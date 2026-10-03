import WebUICore

// MARK: - placement hints (t3.2, additive)
//
// the only consumer-visible placement additions: `.lease(.viewport)` and
// `.lease(.echo)` for engine-local behaviors. a hint is metadata, not markup —
// placement is decided at precompile time (§1.1) — so the rendered bytes are
// identical with or without a hint (pinned in `APISurfaceTests`), and a page
// with no hints behaves exactly as today. the engine *behaviors* behind the
// hints are lane E's to implement (viewport windowing is t3.3; echo rides the
// landed `data-webui-echo` contract); how the hint reaches the engine (build
// scan → served manifest, vs a served attribute) is a wave-3 wiring decision,
// recorded in `continuum-notes/d-to-e.md`.

/// where the engine may lease a region's behavior, engine-locally.
public enum LeaseHint: Sendable, Hashable, CaseIterable {
	/// windowed rendering for long lists/grids (t3.3's `Viewport`).
	case viewport
	/// same-turn local echo for input, reconciled at the debounce edge (t1.4).
	case echo
}

/// the `.lease(_:)` modifier's carrier. inert at render: it changes no bytes
/// and re-parses nothing — it exists so the placement is declared in the type,
/// where a build pass (or a runtime bootstrap) can read it.
public struct LeaseModifier: ViewModifier {
	public let hint: LeaseHint

	public init(_ hint: LeaseHint) {
		self.hint = hint
	}

	public func apply(to html: String) -> String {
		html
	}

	/// pass-through through the buffer: no string round trip, no bytes added.
	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		content.render(into: &buffer)
	}
}

extension View {
	/// declare that this region's behavior may be leased to the engine.
	///
	///     FeedList(items: items).lease(.viewport)
	///
	/// additive and byte-identical: no hint = today's behavior, and the hint
	/// itself adds no markup — it is read by the precompile pass, never by the
	/// browser. the behaviors are the engine lane's (t3.3 windowing, t1.4 echo).
	public func lease(_ hint: LeaseHint) -> ModifiedView<Self, LeaseModifier> {
		ModifiedView(content: self, modifier: LeaseModifier(hint))
	}
}