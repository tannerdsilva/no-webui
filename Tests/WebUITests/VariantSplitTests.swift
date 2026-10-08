import Testing
import WebUI
import WebUIDesignSystem

// the fused Variant vocabulary splits along its real axes
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W1.3; defects T2/T3).
//
// measured at the wave start: **13** components each declared their own nested
// `Variant`, and the case sets do not describe one thing:
//
//   WebUIAlert.Variant    = info | success | warning | danger          -> one axis (tone)
//   WebUIButton.Variant   = primary | secondary | outline | ghost |
//                           danger | success | warning                 -> TWO axes (emphasis x tone)
//   WebUICard.Variant     = elevated | outlined | flat | interactive |
//                           horizontal | hover | compact | disabled    -> elevation + four FLAGS
//   WebUISkeleton.Variant = text | title | avatar | card | custom      -> shape (exact match)
//   WebUIBanner.Variant   = ... danger -> "banner--error"              -> the name lies
//
// a `Variant` that can be `.disabled`, or `+ .compact`, was never a variant —
// those are orthogonal properties wearing one name. this suite covers the
// components migrated so far and grows with the migration, so every commit is
// green.
//
// the assertion shape is the plan's: for every case, the 1.x spelling and the
// new spelling must emit the SAME BYTES. a mapping table keyed by case *name*
// would pass review and fail here — `WebUIBanner.danger` emits `banner--error`,
// so the mapping is built from each enum's own raw values, never from its names.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.render() }
}

@Suite("the fused Variant vocabulary splits")
struct VariantSplitTests {

    @Test("Skeleton's five shapes still emit their original classes")
    func skeletonClassesUnchanged() {
        #expect(render(WebUISkeleton(shape: .text)).contains("skeleton skeleton--text"))
        #expect(render(WebUISkeleton(shape: .title)).contains("skeleton skeleton--title"))
        #expect(render(WebUISkeleton(shape: .avatar)).contains("skeleton skeleton--avatar"))
        #expect(render(WebUISkeleton(shape: .card)).contains("skeleton skeleton--card"))
        // `custom` is the empty string, so the emitted class keeps its trailing
        // space — "skeleton " and nothing else. byte-for-byte the 1.x output.
        #expect(render(WebUISkeleton(shape: .custom)).contains("class=\"skeleton \""))
    }

    @Test("Skeleton's 1.x spelling is byte-identical to the new one, for every case")
    func skeletonOldEqualsNew() {
        // the table-driven equivalence the plan asks for: old -> new -> bytes.
        // `variant:` is the deprecated initializer; `shape:` is the vocabulary.
        for shape in SkeletonShape.allCases {
            let old = render(WebUISkeleton(variant: shape))
            let new = render(WebUISkeleton(shape: shape))
            #expect(old == new, "\(shape.rawValue): legacy \(old) != \(new)")
        }
    }

    @Test("BottomSheet's three positions still emit their original classes")
    func bottomSheetClassesUnchanged() {
        #expect(render(WebUIBottomSheet(position: .peek) { Text("b") }).contains(" bottom-sheet--peek"))
        #expect(render(WebUIBottomSheet(position: .half) { Text("b") }).contains(" bottom-sheet--half"))
        #expect(render(WebUIBottomSheet(position: .full) { Text("b") }).contains(" bottom-sheet--full"))
    }

    @Test("BottomSheet's 1.x spelling is byte-identical to the new one, for every case")
    func bottomSheetOldEqualsNew() {
        for position in SlidePosition.allCases {
            let old = render(WebUIBottomSheet(variant: position) { Text("b") })
            let new = render(WebUIBottomSheet(position: position) { Text("b") })
            #expect(old == new, "\(position.rawValue): legacy \(old) != \(new)")
        }
    }

    @Test("the nested Variant name still resolves to the shared type")
    func deprecatedTypealiasResolves() {
        // a 1.x call site that spelled the type keeps compiling.
        let a: WebUISkeleton.Variant = .card
        let b: WebUIBottomSheet.Variant = .full
        #expect(a == .card)
        #expect(b == .full)
        #expect(render(WebUISkeleton(variant: a)).contains("skeleton--card"))
        #expect(render(WebUIBottomSheet(variant: b) { Text("b") }).contains(" bottom-sheet--full"))
    }

    // MARK: - the seven single-axis tone components

    /// each pair renders the same component through the 1.x `variant:` spelling and
    /// the new `tone:` one, so the two must produce identical bytes.
    private static let toneComponents: [(name: String, legacy: @Sendable (Tone) -> String, current: @Sendable (Tone) -> String)] = [
        ("WebUIBadge", { render(WebUIBadge("n", variant: $0)) }, { render(WebUIBadge("n", tone: $0)) }),
        ("WebUIAlert", { render(WebUIAlert(variant: $0, message: "m")) }, { render(WebUIAlert(tone: $0, message: "m")) }),
        ("WebUIProgress", { render(WebUIProgress(value: 0.5, variant: $0)) }, { render(WebUIProgress(value: 0.5, tone: $0)) }),
        ("WebUIToast", { render(WebUIToast(variant: $0, message: "m")) }, { render(WebUIToast(tone: $0, message: "m")) }),
        ("WebUIChip", { render(WebUIChip("c", variant: $0)) }, { render(WebUIChip("c", tone: $0)) }),
        ("WebUIBanner", { render(WebUIBanner(variant: $0, message: "m")) }, { render(WebUIBanner(tone: $0, message: "m")) }),
        ("WebUIFab", { render(WebUIFab(icon: .check, variant: $0)) }, { render(WebUIFab(icon: .check, tone: $0)) }),
    ]

    @Test("the 1.x variant: spelling is byte-identical to tone:, for every tone")
    func toneOldEqualsNew() {
        #expect(Self.toneComponents.count == 7, "this list must track the migration")
        for c in Self.toneComponents {
            for tone in Tone.allCases {
                #expect(c.legacy(tone) == c.current(tone), "\(c.name) / \(tone.rawValue)")
            }
        }
    }

    @Test("every offered tone keeps its original class — including the one whose name lies")
    func toneClassesUnchanged() {
        #expect(render(WebUIBadge("n", tone: .danger)).contains("badge--danger"))
        #expect(render(WebUIAlert(tone: .success, message: "m")).contains("alert--success"))
        #expect(render(WebUIProgress(value: 0.5, tone: .warning)).contains("progress--warning"))
        #expect(render(WebUIToast(tone: .info, message: "m")).contains("toast--info"))
        #expect(render(WebUIChip("c", tone: .neutral)).contains("chip--neutral"))

        // the trap: Banner's `danger` case has always emitted `banner--error`. any
        // mapping written from the case NAMES would emit `banner--danger` here and
        // ship a class the sheet does not define.
        #expect(render(WebUIBanner(tone: .danger, message: "m")).contains("banner--error"))
        #expect(!render(WebUIBanner(tone: .danger, message: "m")).contains("banner--danger"))

        // Fab's `primary` is the bare base class — no modifier at all.
        #expect(render(WebUIFab(icon: .check, tone: .primary)).contains("class=\"fab\""))
        #expect(render(WebUIFab(icon: .check, tone: .secondary)).contains(" fab--secondary"))
    }

    @Test("a tone the component never offered forwards the pattern, not the default")
    func unofferedTonesForward() {
        // Alert/Toast/Banner/Progress ship four tones; the other three forward the
        // component's own pattern rather than silently rendering their default.
        #expect(render(WebUIAlert(tone: .secondary, message: "m")).contains("alert--secondary"))
        #expect(render(WebUIToast(tone: .neutral, message: "m")).contains("toast--neutral"))
        #expect(render(WebUIProgress(value: 0.5, tone: .primary)).contains("progress--primary"))
        // and where the class is undefined, the element still carries the base class
        #expect(render(WebUIAlert(tone: .neutral, message: "m")).contains("alert alert--neutral"))
    }

    @Test("Tone carries the brand slot the sheet already shipped")
    func toneCarriesSecondary() {
        // four components had a `secondary` case as a peer of `primary`; the sheet's
        // vocabulary is "which colour slot", so the six-value list was incomplete.
        // mapping it onto `neutral` would have changed the emitted class.
        #expect(Tone.secondary.rawValue == "secondary")
        #expect(Tone.allCases.count == 7)
        #expect(Tone.allCases.contains(.secondary))
    }
}