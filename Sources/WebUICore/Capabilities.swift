// the capability protocols (W2.1).
//
// the framework's rule is "complexity available, never required", and this file
// is where that stops being a slogan. a capability must never add a requirement
// to `View`: a view that wants events, streaming or a fallback opts in with one
// word, and a view that does not keeps rendering with `render(into:)` alone.
// `View` carries only what every view must meet.
//
// the rule is enforced where it cannot be argued with — at compile time — by
// `CapabilityProtocolTests`, which declares a view conforming to `View` with
// rendering and nothing else, plus one bare conformance per capability here. the
// day a capability requirement lands on `View`, that test target stops compiling
// instead of quietly obliging every view in every host to implement it.
//
// the first real conformers arrive with the capabilities themselves (W3.5
// streaming, W4.1 the event deck, W4.2 error boundaries). until then these are
// the promise, and the tests hold it.

/// a view that declares DOM events.
///
/// conformance is what makes the event surface (`.onClick` and the rest of the
/// W4.1 deck) available; a plain `View` never sees it.
public protocol Interactive: View {}

/// a view whose DOM id is stable across renders.
///
/// the default is `nil` — "this view makes no stability promise" — so a type
/// opts in by overriding `stableID` rather than by satisfying a requirement.
public protocol Identified: View {
    /// the id this view keeps across renders, or `nil` when it keeps none.
    var stableID: String? { get }
}

extension Identified {
    /// the default: no stability promise.
    public var stableID: String? { nil }
}

/// content that streams (W3.5): the server may flush it in pieces.
public protocol StreamingContent: View {}

/// content that awaits its data before rendering.
public protocol AsyncContent: View {}

/// a view that can supply a fallback when a descendant handler fails (W4.2).
///
/// the default fallback is `EmptyView` — "render nothing in place of the
/// content" — so conformance stays a one-word change, and a type that has
/// something better to offer overrides `fallback`.
public protocol Recoverable: View {
    associatedtype Fallback: View
    var fallback: Fallback { get }
}

extension Recoverable {
    /// the default: replace failing content with nothing.
    public var fallback: EmptyView { EmptyView() }
}