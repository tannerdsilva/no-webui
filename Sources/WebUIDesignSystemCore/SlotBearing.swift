import WebUICore

// the slot-bearing protocols (W1.7): the vocabulary, made checkable.
//
// the plan put this file in `WebUICore`, where `View` lives. it cannot live
// there: the slot types (`ControlSize`, `Tone`, `Elevation`) are declared here,
// in the design system, and the design system imports the core — never the
// reverse. a protocol whose requirement names `ControlSize` has to sit beside
// `ControlSize`. the file path is the one part of W1.7's spec that the module
// graph refuses; the intent — an outside test can read a component's slot
// without knowing how that component spells it — is intact.
//
// what this buys, concretely: a component that loses its slot, or retypes it to
// something else, stops conforming, so the build breaks at the conformance line
// instead of silently changing bytes. and the catalog pass in
// `SlotInvariantTests` can state "every size bearer emits at most one size
// class" once, over the whole catalog, instead of once per type.

/// a view that carries the framework's size slot.
public protocol SizeBearing: View {
    /// the size slot. components store it as `size`; this is the protocol's own
    /// name for it, so the invariant pass reads every bearer the same way.
    var controlSize: ControlSize { get }
}

/// a view that carries the framework's tone slot.
public protocol ToneBearing: View {
    /// the tone slot.
    var tone: Tone { get }
}

/// a view that carries the framework's elevation slot.
///
/// the slot is optional, and that is measured rather than sloppy: `nil` is the
/// sheet's *base surface* — the state that renders no elevation class at all —
/// and it is distinct from every `Elevation` case, each of which emits one. a
/// non-optional requirement would force `nil` to collapse into a case that
/// emits a class, which is a byte change.
public protocol ElevationBearing: View {
    /// the elevation slot; `nil` is the base surface.
    var elevation: Elevation? { get }
}

// MARK: - conformance
//
// one line per measured bearer. these sets are not a guess and not the plan's
// list: they were enumerated from the stored properties across the design
// system (`public let tone: Tone`, `public let size: ControlSize`,
// `public let elevation: Elevation?`) and are pinned by `SlotInvariantTests`.

extension WebUIAlert: ToneBearing {}
extension WebUIBadge: ToneBearing {}
extension WebUIBanner: ToneBearing {}
extension WebUIChip: ToneBearing {}
extension WebUICircularProgress: ToneBearing {}
extension WebUIFab: ToneBearing {}
extension WebUIProgress: ToneBearing {}
extension WebUIToast: ToneBearing {}

extension WebUIAvatar: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIBadge: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIButton: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUICircularProgress: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIDrawer: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIFab: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIKbd: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIOTP: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIProgress: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIRating: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUISlider: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUISpinner: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIStat: SizeBearing { public var controlSize: ControlSize { size } }
extension WebUIStepper: SizeBearing { public var controlSize: ControlSize { size } }

extension WebUICard: ElevationBearing {}