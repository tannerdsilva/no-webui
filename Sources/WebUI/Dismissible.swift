import Foundation
import Logging

// MARK: - ElementRef

/// a type-safe handle to a rendered element, minted by the framework during a
/// render pass. capture it in an event handler and the handler can address the
/// element it was attached to without knowing its id.
///
/// the wrapped id is never caller-supplied: it is either the conforming
/// component's own stable `dismissRootIdentifier` or a framework-minted element
/// id (`e0`, `e1`, ...). construction is module-internal so refs can only come
/// from the framework.
public struct ElementRef: Sendable, Hashable {
    internal let id: String

    internal init(id: String) {
        self.id = id
    }

    /// a ref to an element with a caller-chosen stable id. framework-facing:
    /// components mint this for their own root when handing `me` to typed
    /// handlers (table sort/select/expand, chart mark selection, pagination).
    /// callers composing fragment updates should keep receiving refs from the
    /// framework rather than fabricating them.
    public static func stable(_ id: String) -> ElementRef {
        ElementRef(id: id)
    }

    /// a fragment update that removes the referenced element from the DOM.
    /// the runtime replaces the element with an empty fragment.
    public func remove() -> FragmentUpdate {
        FragmentUpdate(id: id, html: "")
    }

    /// a fragment update that replaces the referenced element's outerHTML.
    public func replace(with html: String) -> FragmentUpdate {
        FragmentUpdate(id: id, html: html)
    }

    /// a fragment update that replaces the referenced element with a freshly
    /// rendered view.
    public func update<V: View>(_ view: V) -> FragmentUpdate {
        FragmentUpdate(id: id, html: view.render())
    }
}

// MARK: - DismissHandler

/// the handler type attached via `.onDismiss(_:)`. receives the referenced
/// element (`me`) and the originating event; returns the fragments to send.
public typealias DismissHandler = @Sendable (ElementRef, EventData) async -> [FragmentUpdate]

// MARK: - Dismissible

/// a view that renders a dismiss/remove affordance. when `onDismiss` is set and
/// a `RenderContext` is present during render, the close button becomes a routed
/// component: the framework allocates a component id for the button, registers
/// the handler, and the handler receives an `ElementRef` to this component's own
/// root element. no container handler, no class-string matching.
///
/// when no handler is set, `makeDismissal()` produces the legacy static marker
/// (`data-dismiss`/`data-remove`, no component id) — byte-identical to the
/// un-wired output the container-handler pattern already consumes.
public protocol Dismissible: View {
    /// the css class the close/remove button carries (e.g. `toast__close`).
    var dismissButtonClass: String { get }

    /// the static marker emitted when no handler is wired
    /// (`data-dismiss` or `data-remove`).
    var dismissMarker: String { get }

    /// the caller-supplied stable id of this component's root element, if any.
    /// the `ElementRef` handed to the handler references this id when present;
    /// otherwise the framework mints one for the render pass.
    var dismissRootIdentifier: String? { get }

    /// the handler wired onto the close button. `nil` renders the static marker
    /// only (the legacy container-handler pattern still works unchanged).
    var onDismiss: DismissHandler? { get set }
}

/// the result of `makeDismissal()`: the id the root element must carry plus the
/// close-button html to emit.
public struct Dismissal: Sendable {
    /// the id the root element must carry (`nil` when nothing was wired).
    public let elementID: String?

    /// the close-button html to emit.
    public let buttonHTML: String

    internal init(elementID: String?, buttonHTML: String) {
        self.elementID = elementID
        self.buttonHTML = buttonHTML
    }
}

private enum DismissibleLog {
    static let log = Logger(label: "webui.dismissible")
}

public extension Dismissible {
    /// attach the dismiss handler. the close button becomes a routed component
    /// and the handler receives an `ElementRef` to this component's own root
    /// element — `me.remove()` removes it from the DOM.
    func onDismiss(_ handler: @escaping DismissHandler) -> Self {
        var copy = self
        copy.onDismiss = handler
        return copy
    }

    /// build the root-element id and close-button html for this render pass.
    /// call at the top of `render()`, emit `elementID` on the root tag, and
    /// `buttonHTML` where the close button goes.
    ///
    /// - no handler → legacy static marker, no element id minted (byte-identical
    ///   to the un-wired output the container-handler pattern consumes)
    /// - handler + context → component id allocated for the button, handler
    ///   registered, element id derived from `dismissRootIdentifier` or minted
    /// - handler without context → static-marker fallback plus a warning
    ///   (mirrors `EventHandlerModifier`)
    func makeDismissal(ariaLabel: String) -> Dismissal {
        let cls = dismissButtonClass
        guard let onDismiss, var context = RenderContext.current else {
            if onDismiss != nil {
                DismissibleLog.log.warning("Dismissible used without RenderContext. Wrap your render call in RenderContext.$current.withValue(...). The onDismiss handler will not fire.")
            }
            return Dismissal(
                elementID: nil,
                buttonHTML: "<button class=\"\(cls)\" \(dismissMarker) aria-label=\"\(ariaLabel)\">&times;</button>"
            )
        }
        let buttonID = context.nextComponentID()
        let elementID = dismissRootIdentifier ?? context.nextElementID().value
        let me = ElementRef(id: elementID)
        context.register(handler: { event in
            await onDismiss(me, event)
        }, for: buttonID)
        return Dismissal(
            elementID: elementID,
            buttonHTML: "<button class=\"\(cls)\" \(dismissMarker) data-component-id=\"\(buttonID.value)\" data-event=\"click\" aria-label=\"\(ariaLabel)\">&times;</button>"
        )
    }
}
