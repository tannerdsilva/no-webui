import WebUICore

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

// the 1.x spellings, kept as deprecated aliases so a call site written against
// `WebUICircularProgress.Size.medium` or `WebUIKbd.Size.large` still compiles.
//
// these are static aliases rather than enum cases on purpose: `allCases` stays
// four, so the vocabulary a catalog enumerates is unchanged, and the token rule
// (`VocabularyTests`) never sees them. a per-component static would not have
// worked — the parameter *type* becomes `ControlSize`, so `.medium` has to
// resolve on `ControlSize` for `size: .medium` to keep compiling.
extension ControlSize {
    @available(*, deprecated, renamed: "sm")
    public static var small: ControlSize { .sm }
    @available(*, deprecated, renamed: "md")
    public static var medium: ControlSize { .md }
    @available(*, deprecated, renamed: "lg")
    public static var large: ControlSize { .lg }
}

/// how much visual weight a control carries.
///
/// `solid` fills, `outline` draws a border, `ghost` shows only hover/focus
/// state, `link` reads as text.
public enum Emphasis: String, Sendable, CaseIterable {
    case solid, outline, ghost, link
}

/// the semantic colour intent — which token slot a component renders in.
///
/// a tone names *meaning*, not a colour: the sheet maps it to a token, so a theme
/// can restyle `danger` without any component knowing what colour it is.
///
/// `secondary` is the one member that names a brand position rather than an
/// intent. it is here because four components (button, badge, chip, fab) have
/// carried a `secondary` case all along, as a peer of `primary` in the same enum —
/// so the sheet's own vocabulary is "which colour slot", and a six-value list
/// could not express what the sheet already ships. mapping it onto `neutral` was
/// the alternative, and it would have changed the emitted class.
public enum Tone: String, Sendable, CaseIterable {
    case neutral
    case primary
    /// the muted brand slot — a brand position, not a semantic intent.
    case secondary
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
///
/// `completed` and `done` are distinct, and the sheet says so: a wizard renders
/// `.wizard__step--completed` (a passed step, in the flow) and
/// `.wizard__step--done` (a finished one, success-coloured) as two rules. the
/// four-value list could not express what the sheet already ships.
public enum StepStatus: String, Sendable, CaseIterable {
    case pending, current, completed, done, error
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

// the 1.x spellings each component used for its own state slot, kept as
// deprecated aliases so a call site still compiles. aliases rather than cases,
// so `allCases` is unchanged (the W1.2 precedent): the parameter *type* is the
// shared enum now, so the old name has to resolve on the shared enum.
extension ValidationState {
    /// `normal` was the input's "no verdict" state.
    @available(*, deprecated, renamed: "none")
    public static var normal: ValidationState { .none }
}
extension LoadState {
    /// `active` was PullRefresh's "loading" state.
    @available(*, deprecated, renamed: "loading")
    public static var active: LoadState { .loading }
    /// `uploading` was Attachment's "loading" state.
    @available(*, deprecated, renamed: "loading")
    public static var uploading: LoadState { .loading }
    /// `error` was Attachment's "failed" state.
    @available(*, deprecated, renamed: "failed")
    public static var error: LoadState { .failed }
}
extension StepStatus {
    /// `plain` was the timeline/wizard's "no state" step.
    @available(*, deprecated, renamed: "pending")
    public static var plain: StepStatus { .pending }
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
///
/// declared in `WebUICore` (see `Markup.swift`) because `HTMLDocument` needs it
/// and the core-facing module cannot see this one. re-exported here so the
/// vocabulary still names every slot in one place, and so `Directionality`
/// keeps reading the same from either import.
public typealias Directionality = WebUICore.Directionality

// MARK: - the stringly-typed slots, typed (W1.6)

/// an avatar's presence badge — the `data-status` token, not a class.
///
/// the sheet colours the badge by this token, so the raw value *is* the
/// contract: `online`, `away`, `busy`, `offline`.
public enum AvatarStatus: String, Sendable, CaseIterable {
    case online, away, busy, offline
}

/// a gantt bar's progress state.
///
/// the sheet ships exactly three modifier classes (`.gantt__bar--active`,
/// `--done`, `--warn`), so the vocabulary carries exactly those; an unstyled
/// bar is `nil` at the call site, which is what the 1.x empty-string default
/// rendered.
public enum GanttBarState: String, Sendable, CaseIterable {
    case active, done, warn
}

/// a json leaf's type.
///
/// the sheet ships four leaf classes (`json-tree__str`, `__num`, `__bool`,
/// `__null`); containers draw no type class, which is why there is no
/// `object`/`array` case.
public enum JsonNodeType: String, Sendable, CaseIterable {
    case string, number, boolean, null
}

/// a unified diff line.
///
/// the sheet ships `.diff__line--add`, `--del`, `--hunk`, `--ctx` — one case
/// per shipped class, named for what the line is rather than for its fragment.
public enum DiffLineKind: String, Sendable, CaseIterable {
    case context, added, removed, header
}

/// a terminal output line.
///
/// `plain` is the unstyled line — the sheet defines no base modifier class,
/// which is what the 1.x `default:` branch rendered.
public enum TerminalLineKind: String, Sendable, CaseIterable {
    case plain, ok, warn, error
}

/// a chart series colour, drawn from the sheet's own palette.
///
/// the slots name `--color-chart-1` … `--color-chart-8`. a host that needs a
/// different colour defines a token; raw css never rides a call site.
public enum ChartColorSlot: String, Sendable, CaseIterable {
    case c1, c2, c3, c4, c5, c6, c7, c8
}