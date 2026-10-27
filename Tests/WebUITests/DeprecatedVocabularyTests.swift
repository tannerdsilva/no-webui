import Testing
import WebUI
import WebUIDesignSystem

// W1.8's deprecation gate. the wave-1 waves renamed or retyped every slot in the
// design system; each 1.x spelling survives as a `@available(*, deprecated)`
// alias so a host's code keeps compiling while the warning tells it where to go.
// this file calls *every one of them* — 56 spellings — because "we kept the
// aliases" is a claim that only a compile proves. the deprecation warnings this
// file emits are the point, not a problem: they are the migration instructions
// the 2.0 release ships.
//
// each test asserts the alias resolves to the same type the new spelling names,
// so an alias that silently pointed somewhere else would fail here rather than
// at a host's call site.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.markup.html }
}

@Suite("every 1.x slot spelling still compiles")
struct DeprecatedVocabularyTests {

    // MARK: value-carrying aliases on the shared enums

    @Test("ControlSize's 1.x names resolve to their cases")
    func controlSizeNames() {
        #expect(ControlSize.small == .sm)
        #expect(ControlSize.medium == .md)
        #expect(ControlSize.large == .lg)
    }

    @Test("the 1.x state case names resolve to their cases")
    func stateCaseNames() {
        #expect(ValidationState.normal == .none)
        #expect(LoadState.active == .loading)
        #expect(LoadState.uploading == .loading)
        #expect(LoadState.error == .failed)
        #expect(StepStatus.plain == .pending)
    }

    // MARK: typealiases, component by component

    @Test("the tone components' Variant resolves to Tone")
    func toneVariants() {
        #expect(WebUIBadge.Variant.self == Tone.self)
        #expect(WebUIAlert.Variant.self == Tone.self)
        #expect(WebUIProgress.Variant.self == Tone.self)
        #expect(WebUIToast.Variant.self == Tone.self)
        #expect(WebUIChip.Variant.self == Tone.self)
        #expect(WebUIBanner.Variant.self == Tone.self)
        #expect(WebUIFab.Variant.self == Tone.self)
        #expect(WebUINotification.Kind.self == Tone.self)
        #expect(WebUICircularProgress.Tone.self == Tone.self)
    }

    @Test("the size components' Size resolves to ControlSize")
    func sizeAliases() {
        #expect(WebUIButton.Size.self == ControlSize.self)
        #expect(WebUIBadge.Size.self == ControlSize.self)
        #expect(WebUIAvatar.Size.self == ControlSize.self)
        #expect(WebUIProgress.Size.self == ControlSize.self)
        #expect(WebUISpinner.Size.self == ControlSize.self)
        #expect(WebUIStat.Size.self == ControlSize.self)
        #expect(WebUICircularProgress.Size.self == ControlSize.self)
        #expect(WebUISlider.Size.self == ControlSize.self)
        #expect(WebUIToggle.Size.self == ControlSize.self)
        #expect(WebUIStepper.Size.self == ControlSize.self)
        #expect(WebUIOTP.Size.self == ControlSize.self)
        #expect(WebUIRating.Size.self == ControlSize.self)
        #expect(WebUIFab.Size.self == ControlSize.self)
        #expect(WebUIDrawer<EmptyView, EmptyView>.Size.self == ControlSize.self)
        #expect(WebUIKbd.Size.self == ControlSize.self)
    }

    @Test("the renamed axes resolve to their shared types")
    func renamedAxes() {
        #expect(WebUIInput.State.self == ValidationState.self)
        #expect(WebUIPullRefresh.State.self == LoadState.self)
        #expect(WebUIAttachment.State.self == LoadState.self)
        #expect(WebUIValidation.State.self == ValidationState.self)
        #expect(WebUIInlineEdit.State.self == EditState.self)
        #expect(WebUIWizard.Status.self == StepStatus.self)
        #expect(WebUIStat.Trend.self == Trend.self)
        #expect(WebUIDelta.Direction.self == Trend.self)
        #expect(WebUIBadgeStatus.Status.self == Presence.self)
        #expect(WebUISkeleton.Variant.self == SkeletonShape.self)
        #expect(WebUISeparator.Orientation.self == Axis.self)
        #expect(WebUITimeline.Orientation.self == Axis.self)
        #expect(WebUITimeline.Status.self == StepStatus.self)
        #expect(WebUIChatBubble.Side.self == WebUIChatBubble.BubbleSide.self)
        #expect(WebUIAccordion.Variant.self == WebUIAccordion.Appearance.self)
        #expect(WebUITag.Variant.self == WebUITag.Appearance.self)
        #expect(WebUIButton.Variant.self == WebUIButton.Appearance.self)
        #expect(WebUIBottomSheet<EmptyView, EmptyView>.Variant.self == SlidePosition.self)
        #expect(WebUIDrawer<EmptyView, EmptyView>.Edge.self == DrawerEdge.self)
        #expect(WebUIPopover<EmptyView>.Side.self == Placement.self)
        #expect(WebUIPanel<EmptyView>.Edge.self == PanelEdge.self)
        #expect(WebUIPayCard.Brand.self == Brand.self)
        #expect(WebUICardInput.Brand.self == Brand.self)
    }

    // MARK: the 1.x spellings still render the same bytes

    @Test("an alias and its replacement are the same value at the call site")
    func aliasesRenderIdentically() {
        #expect(render(WebUIButton("b", size: .small)) == render(WebUIButton("b", size: .sm)))
        #expect(render(WebUIInput(state: .normal, id: "i")) == render(WebUIInput(state: .none, id: "i")))
        #expect(render(WebUIPullRefresh(state: .active)) == render(WebUIPullRefresh(state: .loading)))
        #expect(render(WebUITimeline(events: [])) == render(WebUITimeline(events: [], orientation: .vertical)))
        #expect(render(WebUIChatBubble("t", side: .sent)) == render(WebUIChatBubble("t", side: .sent)))
    }

    @Test("Card's 1.x Variant enum forwards to elevation plus flags, byte for byte")
    func cardLegacyVariant() {
        // the fused enum survives as a deprecated case list plus a forwarding
        // init. each case must produce exactly the markup its new spelling does,
        // which is the whole reason the enum was kept rather than deleted.
        #expect(render(WebUICard(variant: .elevated) { Text("x") })
                == render(WebUICard(elevation: .elevated) { Text("x") }))
        #expect(render(WebUICard(variant: .outlined) { Text("x") })
                == render(WebUICard(elevation: .outlined) { Text("x") }))
        #expect(render(WebUICard(variant: .flat) { Text("x") })
                == render(WebUICard(elevation: .flat) { Text("x") }))
        // the flags were never an elevation; their 1.x spelling must still map to
        // the base surface plus the flag, not to a fabricated elevation case.
        #expect(render(WebUICard(variant: .interactive) { Text("x") })
                == render(WebUICard(elevation: nil, interactive: true) { Text("x") }))
    }
}