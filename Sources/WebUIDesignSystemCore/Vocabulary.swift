// Vocabulary.swift — the framework's semantic slots, declared once.
//
// before this file every component carried its own nested enums for the same
// ideas, and their raw values were **css class fragments**:
//
//   WebUIStat.Size.sm                  = "stat stat--sm"
//   WebUIStat.Trend.up                 = "stat__trend--up"
//   WebUICircularProgress.Tone.success = "ring--success"
//   WebUICircularProgress.Tone.primary = ""                       <- empty string
//   WebUICardInput.Brand.visa          = " card-input__brand-icon--visa"
//
// measured at the wave start: 15 nested `Size`, 13 nested `Variant`, 5 `State`,
// 3 `Status`, 2 `Side`, 2 `Edge`, and `Brand` declared twice with different raw
// value sets. the cost was not cosmetic. three things were impossible:
//
//   * a generic bearer — `SizeBearing`/`ToneBearing` cannot name a type that has
//     15 spellings, so no code could restyle or validate across components;
//   * a catalog-wide invariant — `CaseIterable` over "the sizes" had no subject;
//   * a raw value that means something on its own — `"stat stat--sm"` is only
//     meaningful to `WebUIStat`, so nothing outside it could read or produce one.
//
// the rule this file establishes: **the raw value is the semantic token** — one
// lowercase word, stable across components, with no component prefix and no class
// syntax. a component builds its own class name from the token when it renders
// (`"stat stat--\(size.rawValue)"`), so the vocabulary is shared while the css
// stays per-component.
//
// the nested enums are the migration tail (W1.2-W1.7): each is replaced by the
// matching type here, keeping an `@available(*, deprecated, renamed:)` shim so a
// 1.x call site still compiles. the generated css classes must not change — the
// byte-identity gate is the guard.

// MARK: - appearance

/// a control's size, on the sheet's scale.
public enum ControlSize: String, Sendable, CaseIterable {
    case sm, md, lg, xl
}

/// how much visual weight a control carries.
///
/// `solid` fills, `outline` draws a border, `ghost` shows only hover/focus
/// state, `link` reads as text.
public enum Emphasis: String, Sendable, CaseIterable {
    case solid, outline, ghost, link
}

/// the semantic colour intent.
///
/// a tone names *meaning*, not a colour: the sheet maps it to a token, so a
/// theme can restyle `danger` without any component knowing what colour it is.
public enum Tone: String, Sendable, CaseIterable {
    case neutral
    case primary
    case info
    case success
    case warning
    case danger
}

/// how far a surface sits above the page.
public enum Elevation: String, Sendable, CaseIterable {
    case flat, outlined, elevated
}

// MARK: - state families

/// where a step sits in a multi-step flow.
public enum StepStatus: String, Sendable, CaseIterable {
    case pending, current, done, error
}

/// where an async load sits.
public enum LoadState: String, Sendable, CaseIterable {
    case idle, loading, ready, failed
}

/// a field's validation outcome.
///
/// `none` is a real state, distinct from `success`: untouched is not the same as
/// verified, and a form that conflates them shows a green tick on an empty field.
public enum ValidationState: String, Sendable, CaseIterable {
    case none, success, warning, error
}

/// where an editable value sits.
public enum EditState: String, Sendable, CaseIterable {
    case idle, editing, saved
}

/// a person's availability.
///
/// `live` is distinct from `online`: it means actively broadcasting now, not
/// merely reachable.
public enum Presence: String, Sendable, CaseIterable {
    case online, away, busy, offline, live
}

// MARK: - placement

/// which side of a host an attached surface opens on.
///
/// `leading`/`trailing` are logical, so they mirror under rtl where `left`/`right`
/// do not — which is why both are offered rather than one pair.
public enum Placement: String, Sendable, CaseIterable {
    case top, bottom, left, right, leading, trailing
}

/// a direction along the page's flow.
public enum Axis: String, Sendable, CaseIterable {
    case horizontal, vertical
}

/// which edge a panel is docked to. `none` means not docked.
public enum PanelEdge: String, Sendable, CaseIterable {
    case none, leading, trailing
}

/// which edge a drawer slides from.
public enum DrawerEdge: String, Sendable, CaseIterable {
    case left, right, top, bottom
}

/// how far a sheet is presented.
public enum SlidePosition: String, Sendable, CaseIterable {
    case peek, half, full
}

// MARK: - content

/// which way a series is moving.
public enum Trend: String, Sendable, CaseIterable {
    case up, down, flat
}

/// the placeholder geometry a skeleton mimics.
///
/// `custom` is what a caller reaches for when the shape is neither of the four:
/// it takes its geometry from the caller instead of from this token.
public enum SkeletonShape: String, Sendable, CaseIterable {
    case text, title, avatar, card, custom
}

/// a card network, for the input's brand affordance.
public enum Brand: String, Sendable, CaseIterable {
    case visa, mc, amex, discover
}

/// the document's writing direction.
public enum Directionality: String, Sendable, CaseIterable {
    case ltr, rtl
}