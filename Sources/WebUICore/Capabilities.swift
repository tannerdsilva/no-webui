// the capability protocols (W2.1).
//
// the framework's rule is "complexity available, never required", and this file
// is where that stops being a slogan. a capability must never add a requirement
// to `View`: a view that wants a stable id or a fallback opts in with one word,
// and a view that does not keeps rendering with `render(into:)` alone.
// `View` carries only what every view must meet.
//
// the rule is enforced where it cannot be argued with — at compile time — by
// `CapabilityProtocolTests`, which declares a view conforming to `View` with
// rendering and nothing else, plus one bare conformance per capability here. the
// day a capability requirement lands on `View`, that test target stops compiling
// instead of quietly obliging every view in every host to implement it.
//
// events are `extension View` and streaming/async rendering never shipped, so
// nothing replaced the three protocols this file used to declare.

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
