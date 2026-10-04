import WebUICore

// MARK: - input parity, the delivery half (DESKTOP_GRADE §t3.4)
//
// the parent plan splits t3.4 three ways: the *types* (wasm-visible — lane C
// owns `KeyEvent`/`Selection`/`ClipboardPayload`/`UndoStack` in
// `WebUISharedCore`), the *engine* (composition forwarding — lane E), and the
// *delivery/modifiers* in `WebUI` — this file.
//
// what this file delivers:
//
// - `inputParity(_:)` — a closed subscription vocabulary (key / selection /
//   clipboard / undo / composition) emitted as an engine-readable descriptor,
//   `data-webui-input='["key","composition"]'`. the descriptor is the
//   declaration side of E's event routing (the sibling of E's existing
//   `data-webui-island-events` array spell); the engine forwards exactly the
//   subscribed kinds into the region.
// - `compositionForwarded()` — the ime rule of §t3.4 made concrete:
//   `data-webui-composition=""` on an input tells the engine to forward
//   `compositionstart/update/end` as typed `{type, key: "composition", data}`
//   events so candidate text never fights the server's value.
// - `onKeyEvent(_:)` — the author-facing typed key handler, carrying lane C's
//   REAL `KeyEvent` grammar (the wasm-visible type the island transport
//   shares). the twins (`ParityKeyEvent`/`ParityModifiers` — wave-3 delivery
//   stand-ins) were removed at polish; the surface now IS `KeyEvent`/
//   `ModifierSet`/`Key`. the transport mapping (KeyEvent → E's
//   `{type,key,data}` v1) rides `Key.identifier` / `Key(identifier:)` — see
//   `islandPayloadV1` below + the mapping table in `continuum-notes/d-docs.md`.
//
// grey line kept deliberately: `UndoStack`/`Selection`/`ClipboardPayload`
// grammars are lane C's (pure, testable natively + islands); this file only
// *subscribes* to them.

// MARK: - the subscription vocabulary

/// the closed set of input-parity surfaces a region may opt into. each
/// entry names ONE engine-forwarded channel; a region declares the channels
/// it can answer. the engine's JS twin forwards per this list and no other.
public enum InputParity {
	/// key events (`keydown`/`keyup`, typed per `KeyEvent`).
	case key
	/// selection changes (anchor/focus index paths — the `Selection` grammar).
	case selection
	/// clipboard interchange (tsv/text — the `ClipboardPayload` grammar).
	case clipboard
	/// undo/redo history (the `UndoStack` grammar).
	case undo
	/// ime composition (`compositionstart/update/end`, forwarded so candidate
	/// text never fights the server's value).
	case composition

	/// the engine-facing token — the value inside the descriptor array.
	public var wireName: String {
		switch self {
		case .key: return "key"
		case .selection: return "selection"
		case .clipboard: return "clipboard"
		case .undo: return "undo"
		case .composition: return "composition"
		}
	}
}

extension InputParity: Sendable, Hashable, CaseIterable {}

// MARK: - the descriptor modifier

/// carries a region's input-parity subscription set onto the served element.
public struct InputParityModifier: ViewModifier {
	public let subscriptions: [InputParity]

	public init(_ subscriptions: [InputParity]) {
		self.subscriptions = subscriptions
	}

	/// the descriptor — a stable-order JSON array the engine parses exactly
	/// like its other attribute arrays (`data-webui-island-events`).
	public var descriptor: String {
		let names = Self.order(subscriptions).map(\.wireName)
		return "data-webui-input='[\(names.map { "\"\($0)\"" }.joined(separator: ","))]'"
	}

	public func apply(to html: String) -> String {
		guard !subscriptions.isEmpty else { return html }
		return injectAttributes(into: html, descriptor)
	}

	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		guard !subscriptions.isEmpty else {
			content.render(into: &buffer)
			return
		}
		let mark = buffer.mark
		buffer.addAttribute(descriptor)
		content.render(into: &buffer)
		buffer.settlePendingAttributes(from: mark)
	}

	/// canonical order — the descriptor is deterministic regardless of the
	/// order the author named the subscriptions (byte-stable render).
	static func order(_ input: [InputParity]) -> [InputParity] {
		let seen = Set(input)
		return InputParity.allCases.filter { seen.contains($0) }
	}
}

extension View {
	/// declare the input-parity channels this region subscribes to. emits
	/// `data-webui-input='["key",…]'` on the wrapped root (the engine's
	/// forwarding descriptor); an empty set emits nothing.
	///
	///     editor.lease(.echo, echoTo: "preview").inputParity(.key, .composition)
	///
	/// additive: a region with no parity declaration renders today's bytes.
	public func inputParity(_ subscriptions: InputParity...) -> ModifiedView<Self, InputParityModifier> {
		ModifiedView(content: self, modifier: InputParityModifier(subscriptions))
	}

	/// the ime delivery: forward this input's composition events to the region
	/// as typed events (`{type, key: "composition", data: …}`), so the
	/// pre-commit candidate text never round-trips against the server's value
	/// (§t3.4). emits `data-webui-composition=""`.
	public func compositionForwarded() -> ModifiedView<Self, CompositionForwardModifier> {
		ModifiedView(content: self, modifier: CompositionForwardModifier())
	}
}

// MARK: - ime composition forwarding

/// the `data-webui-composition` carrier: marks an input the engine forwards
/// composition events from instead of letting candidate text fight the
/// server's authoritative value.
public struct CompositionForwardModifier: ViewModifier {
	public init() {}

	public func apply(to html: String) -> String {
		injectAttributes(into: html, "data-webui-composition=\"\"")
	}

	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		let mark = buffer.mark
		buffer.addAttribute("data-webui-composition=\"\"")
		content.render(into: &buffer)
		buffer.settlePendingAttributes(from: mark)
	}
}

// MARK: - the typed key delivery (lane C's REAL grammar)

/// the delivery carrier for a typed key-event subscription: emits the `key`
/// channel descriptor at render and carries the author's typed handler in the
/// type, where the continuum scan lifts it (the `.lease` pattern).
///
/// the handler's event is lane C's `KeyEvent` (`key: Key`,
/// `modifiers: ModifierSet`, `isRepeat: Bool`) — the SAME wasm-visible shape
/// the island transport decodes, so a handler can be forwarded verbatim.
public struct KeyEventDeliveryModifier: ViewModifier {
	public let handler: @Sendable (KeyEvent) -> Void

	public init(_ handler: @escaping @Sendable (KeyEvent) -> Void) {
		self.handler = handler
	}

	public func apply(to html: String) -> String {
		injectAttributes(into: html, "data-webui-input='[\"key\"]'")
	}

	public func decorate<C: View>(_ content: C, into buffer: inout HTMLBuffer) {
		let mark = buffer.mark
		buffer.addAttribute("data-webui-input='[\"key\"]'")
		content.render(into: &buffer)
		buffer.settlePendingAttributes(from: mark)
	}
}

extension View {
	/// subscribe this region to typed key events. the region renders with the
	/// `key` parity channel open, and the handler is carried in the type for
	/// the precompile scan.
	///
	/// the handler receives lane C's `KeyEvent`; the engine delivers it as the
	/// v1 island payload `{"type":"key","key":<Key.identifier>}` (see
	/// `islandPayloadV1`), whose `key` string the island's `Key(identifier:)`
	/// parses back to the same `Key`.
	public func onKeyEvent(_ handler: @escaping @Sendable (KeyEvent) -> Void) -> ModifiedView<Self, KeyEventDeliveryModifier> {
		ModifiedView(content: self, modifier: KeyEventDeliveryModifier(handler))
	}
}
