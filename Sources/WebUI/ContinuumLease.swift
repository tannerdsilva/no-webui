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

/// the `.lease(_:)` modifier's carrier. inert at render for a bare hint (it
/// changes no bytes and re-parses nothing — it exists so the placement is
/// declared in the type, where a build pass (or a runtime bootstrap) can read
/// it). the one exception is the t3.4 echo *delivery*: `.lease(.echo, echoTo:)`
/// names a target id, and then the modifier emits the engine's echo contract
/// attribute (`data-webui-echo="<target>"`, E's t1.4) on the wrapped region's
/// root element — the delivery side of the wave-2 declaration. a hint WITHOUT
/// a target still changes no bytes (an echo source with nowhere to echo is
/// not an echo source).
public struct LeaseModifier: ViewModifier {
	public let hint: LeaseHint
	/// the t3.4 echo-delivery target: when set (with `.echo`), the engine's
	/// `data-webui-echo` contract attribute is emitted on the wrapped root.
	public let echoTarget: String?

	public init(_ hint: LeaseHint) {
		self.hint = hint
		self.echoTarget = nil
	}

	/// the echo delivery form: `.lease(.echo, echoTo: "target")` — the wrapped
	/// region reflects its value into `#target`'s text, engine-locally (E's
	/// t1.4 contract, `data-webui-echo="<target>"`).
	public init(_ hint: LeaseHint, echoTo target: String) {
		self.hint = hint
		self.echoTarget = target
	}

	private var echoAttribute: String? {
		guard hint == .echo, let echoTarget else { return nil }
		return "data-webui-echo=\"\(htmlEscape(echoTarget))\""
	}

	public func apply(to html: String) -> String {
		guard let echoAttribute else { return html }
		return injectAttributes(into: html, echoAttribute)
	}

	/// delivery through the buffer: the echo attribute joins the element that
	/// opens next; content that opens no element is span-wrapped (the same
	/// settlement the other attribute modifiers use).
	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		guard let echoAttribute else {
			content.render(into: &buffer)
			return
		}
		let mark = buffer.mark
		buffer.addAttribute(echoAttribute)
		content.render(into: &buffer)
		buffer.settlePendingAttributes(from: mark)
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

	/// the t3.4 echo delivery: declare that this region's value echoes locally
	/// into `#target`'s text, engine-side, with zero round trips (E's t1.4
	/// contract). emitting `data-webui-echo="<target>"` on the wrapped root is
	/// the delivery half of the wave-2 `.echo` hint — a `.lease(.echo)`
	/// without a target remains declaration-only (byte-identical, pinned).
	public func lease(_ hint: LeaseHint, echoTo target: String) -> ModifiedView<Self, LeaseModifier> {
		ModifiedView(content: self, modifier: LeaseModifier(hint, echoTo: target))
	}
}