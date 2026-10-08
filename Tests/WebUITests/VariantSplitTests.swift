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
}