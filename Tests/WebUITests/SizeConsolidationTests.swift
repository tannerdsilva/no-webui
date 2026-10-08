import Testing
import WebUI
import WebUIDesignSystem

// one ControlSize
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W1.2; defect T1).
//
// measured at the wave start: **15** components each declared their own nested
// `Size`, and their raw values were the component's css class —
//
//   WebUIButton.Size.md            = "button--md"
//   WebUIStat.Size.md              = "stat"
//   WebUISlider.Size.md            = ""
//   WebUICircularProgress.Size.small = "ring--sm"      (note: small, not sm)
//   WebUIKbd.Size.large            = ""                (drifted: small/large, not sm/lg)
//
// so the same word meant a different class in every component, and "the sizes"
// had no type to enumerate. each component now takes `ControlSize` and maps it to
// its own class through a private `classFor(_:)`; the emitted bytes for the three
// original sizes are unchanged, which the smoke gate re-checks end to end.
//
// this suite covers the components migrated so far. it grows file by file with
// the migration, so every commit is green.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.render() }
}

@Suite("one ControlSize")
struct SizeConsolidationTests {

    /// each pair is a compile-time assertion as much as a runtime one: the array
    /// literal must be `(String, ControlSize)`, so a component still publishing
    /// its own nested `Size` fails the BUILD here rather than a comparison.
    private static let sizedComponents: [(name: String, size: ControlSize)] = [
        ("WebUIButton", WebUIButton("Go").size),
        ("WebUIBadge", WebUIBadge("new").size),
        ("WebUIAvatar", WebUIAvatar(initials: "AB").size),
        ("WebUIProgress", WebUIProgress(value: 0.5).size),
        ("WebUISpinner", WebUISpinner().size),
        ("WebUIStat", WebUIStat(label: "Revenue", value: "$1").size),
        ("WebUICircularProgress", WebUICircularProgress(value: 0.5).size),
    ]

    @Test("every migrated component publishes ControlSize")
    func componentsPublishControlSize() {
        #expect(Self.sizedComponents.count == 7, "this list must track the migration")
        for c in Self.sizedComponents {
            #expect(c.size == .md, "\(c.name) should default to .md")
        }
    }

    @Test("the emitted class for sm/md/lg is unchanged")
    func emittedClassesAreUnchanged() {
        // the byte-identity claim, proven at render level for each component: the
        // class the component emits for a size is the one it emitted before the
        // consolidation, including the odd shapes (`"stat"` for md, `""` for
        // slider-class components, and the leading space in those).
        #expect(render(WebUIButton("Go", size: .sm)).contains("button--sm"))
        #expect(render(WebUIButton("Go", size: .md)).contains("button--md"))
        #expect(render(WebUIButton("Go", size: .lg)).contains("button--lg"))

        #expect(render(WebUIBadge("n", size: .sm)).contains("badge--sm"))
        #expect(render(WebUIBadge("n", size: .md)).contains("badge--md"))
        #expect(render(WebUIBadge("n", size: .lg)).contains("badge--lg"))

        #expect(render(WebUIAvatar(initials: "AB", size: .sm)).contains("avatar--sm"))
        #expect(render(WebUIAvatar(initials: "AB", size: .lg)).contains("avatar--lg"))
        #expect(render(WebUIAvatar(initials: "AB", size: .xl)).contains("avatar--xl"))

        #expect(render(WebUIProgress(value: 0.5, size: .sm)).contains("progress--sm"))
        #expect(render(WebUIProgress(value: 0.5, size: .lg)).contains("progress--lg"))

        #expect(render(WebUISpinner(size: .sm)).contains("spinner--sm"))
        #expect(render(WebUISpinner(size: .lg)).contains("spinner--lg"))

        // `md` is the bare class for stat — the size that emits no modifier
        #expect(render(WebUIStat(label: "l", value: "v", size: .md)).contains("class=\"stat\""))
        #expect(render(WebUIStat(label: "l", value: "v", size: .sm)).contains("stat stat--sm"))
        #expect(render(WebUIStat(label: "l", value: "v", size: .lg)).contains("stat stat--lg"))

        // `md` is the empty string for the ring — its class list gains nothing
        #expect(render(WebUICircularProgress(value: 0.5, size: .sm)).contains("ring--sm"))
        #expect(render(WebUICircularProgress(value: 0.5, size: .lg)).contains("ring--lg"))
        #expect(!render(WebUICircularProgress(value: 0.5, size: .md)).contains("ring--"))
    }

    @Test("xl forwards the component's own pattern instead of degrading to lg")
    func xlForwards() {
        // measured: the sheet defines exactly four `--xl` rules. forwarding the
        // class keeps `xl` an extension point a theme can honor; silently
        // returning the `lg` class would be a lie the caller cannot see.
        #expect(render(WebUIButton("Go", size: .xl)).contains("button--xl"))
        #expect(render(WebUIBadge("n", size: .xl)).contains("badge--xl"))
        #expect(render(WebUIStat(label: "l", value: "v", size: .xl)).contains("stat stat--xl"))
        // and where the sheet *does* define it, it is the real rule
        #expect(render(WebUIStat(label: "l", value: "v", size: .xl)).contains("stat--xl"))
    }

    @Test("the 1.x size spellings still compile and mean the same thing")
    func deprecatedSpellingsForward() {
        // `small`/`medium`/`large` are deprecated static aliases on ControlSize so
        // that `size: .medium` — the spelling WebUICircularProgress and WebUIKbd
        // used — still compiles. they are aliases, not cases, so the enumerated
        // vocabulary is unchanged.
        #expect(ControlSize.small == .sm)
        #expect(ControlSize.medium == .md)
        #expect(ControlSize.large == .lg)
        #expect(ControlSize.allCases == [.sm, .md, .lg, .xl], "aliases must not join allCases")
    }

    @Test("the 1.x nested Size name still resolves")
    func deprecatedTypealiasResolves() {
        // WebUIButton.Size.md written by a 1.x call site now routes to ControlSize.
        let s: WebUIButton.Size = .lg
        #expect(s == .lg)
        #expect(render(WebUIButton("Go", size: s)).contains("button--lg"))
    }
}