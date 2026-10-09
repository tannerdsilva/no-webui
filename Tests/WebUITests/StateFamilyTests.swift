import Testing
import WebUI
import WebUIDesignSystem

// W1.4: the state families. five `State`, three `Status`, one `Trend`, one
// `Direction`, one `Kind` and one `Orientation` were declared per component;
// each becomes the matching shared type in `Vocabulary.swift`.
//
// the assertion shape is the plan's: every 1.x case must still RESOLVE (via a
// deprecated alias on the shared enum) and must still render the SAME BYTES.
// the class maps are built from each component's original raw values, so an
// alias whose target differs from its 1.x meaning (`normal` -> `none`,
// `active` -> `loading`, `uploading` -> `loading`, `error` -> `failed`,
// `plain` -> `pending`) cannot silently change a class.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.renderThroughBuffer() }
}

@Suite("the state vocabulary is one set of shared types")
struct StateFamilyTests {

    // MARK: inputs and forms

    @Test("Input's four 1.x states keep their exact classes")
    func inputStates() {
        #expect(render(WebUIInput(state: .normal)).contains("class=\"input \""))
        #expect(render(WebUIInput(state: .error)).contains("class=\"input input--error\""))
        #expect(render(WebUIInput(state: .success)).contains("class=\"input input--success\""))
        #expect(render(WebUIInput(state: .warning)).contains("class=\"input input--warning\""))
        // the slot's TYPE is the shared one, so a generic bearer can name it.
        let slot: ValidationState = WebUIInput(state: .error).state
        #expect(slot == .error)
    }

    @Test("Validation's three states keep their classes and glyphs")
    func validationStates() {
        #expect(render(WebUIValidation("m", state: .success)).contains("class=\"validation validation--success\""))
        #expect(render(WebUIValidation("m", state: .warning)).contains("class=\"validation validation--warning\""))
        #expect(render(WebUIValidation("m", state: .error)).contains("class=\"validation validation--error\""))
        #expect(render(WebUIValidation("m", state: .success)).contains(">✓</span>"))
        #expect(render(WebUIValidation("m", state: .warning)).contains(">!</span>"))
        #expect(render(WebUIValidation("m", state: .error)).contains(">✗</span>"))
        let slot: ValidationState = WebUIValidation("m").state
        #expect(slot == .error)
    }

    @Test("InlineEdit's three states keep their classes")
    func inlineEditStates() {
        #expect(render(WebUIInlineEdit("v", state: .idle)).contains("class=\"inline-edit inline-edit--idle\""))
        #expect(render(WebUIInlineEdit("v", state: .editing)).contains("class=\"inline-edit inline-edit--editing\""))
        #expect(render(WebUIInlineEdit("v", state: .saved)).contains("class=\"inline-edit inline-edit--saved\""))
        let slot: EditState = WebUIInlineEdit("v").state
        #expect(slot == .idle)
    }

    // MARK: loads

    @Test("PullRefresh's idle/active keep their bytes; active is loading")
    func pullRefreshStates() {
        #expect(render(WebUIPullRefresh(state: .idle)).contains("class=\"pull-refresh pull-refresh--idle\" role=\"status\""))
        #expect(render(WebUIPullRefresh(state: .active)).contains("class=\"pull-refresh pull-refresh--active\" role=\"status\""))
        let slot: LoadState = WebUIPullRefresh(state: .active).state
        #expect(slot == .loading)
    }

    @Test("Attachment's ready/uploading/error keep their bytes")
    func attachmentStates() {
        #expect(render(WebUIAttachment(name: "a", state: .ready)).contains("class=\"attachment\""))
        #expect(render(WebUIAttachment(name: "a", state: .uploading)).contains("class=\"attachment attachment--uploading\""))
        #expect(render(WebUIAttachment(name: "a", state: .error)).contains("class=\"attachment attachment--error\""))
        let slot: LoadState = WebUIAttachment(name: "a").state
        #expect(slot == .ready)
    }

    // MARK: statuses

    @Test("BadgeStatus is an exact match onto Presence, byte for byte")
    func badgeStatuses() {
        #expect(render(WebUIBadgeStatus("x", status: .online)).contains("badge-status__dot--online"))
        #expect(render(WebUIBadgeStatus("x", status: .away)).contains("badge-status__dot--away"))
        #expect(render(WebUIBadgeStatus("x", status: .busy)).contains("badge-status__dot--busy"))
        #expect(render(WebUIBadgeStatus("x", status: .offline)).contains("badge-status__dot--offline"))
        #expect(render(WebUIBadgeStatus("x", status: .live)).contains("badge-status__dot--live"))
        let slot: Presence = WebUIBadgeStatus("x").status
        #expect(slot == .online)
    }

    @Test("the timeline's four statuses keep their bytes; plain is pending")
    func timelineStatuses() {
        func event(_ s: StepStatus) -> String {
            render(WebUITimeline(events: [.init(time: "t", title: "x", status: s)]))
        }
        #expect(event(.plain).contains("<div class=\"timeline__event\">"))
        #expect(event(.completed).contains("<div class=\"timeline__event timeline__event--completed\">"))
        #expect(event(.current).contains("<div class=\"timeline__event timeline__event--current\">"))
        #expect(event(.error).contains("<div class=\"timeline__event timeline__event--error\">"))
    }

    @Test("the timeline's orientation is Axis, same bytes")
    func timelineOrientation() {
        #expect(render(WebUITimeline(events: [])).contains("class=\"timeline\""))
        #expect(render(WebUITimeline(events: [], orientation: .horizontal)).contains("class=\"timeline timeline--horizontal\""))
        let slot: Axis = WebUITimeline(events: []).orientation
        #expect(slot == .vertical)
    }

    @Test("the wizard keeps `completed` AND `done` — the sheet ships both")
    func wizardStatuses() {
        func step(_ s: StepStatus) -> String {
            render(WebUIWizard(steps: [.init("s", status: s)]))
        }
        #expect(step(.plain).contains("<li class=\"wizard__step\">"))
        #expect(step(.completed).contains("<li class=\"wizard__step wizard__step--completed\">"))
        #expect(step(.current).contains("<li class=\"wizard__step wizard__step--current\">"))
        #expect(step(.done).contains("<li class=\"wizard__step wizard__step--done\">"))
        #expect(step(.error).contains("<li class=\"wizard__step wizard__step--error\">"))
        // the distinction is the reason `StepStatus` carries five values, not four.
        #expect(StepStatus.allCases.count == 5)
    }

    // MARK: trends

    @Test("Delta's up/down keep their bytes; flat forwards the pattern")
    func deltaTrends() {
        #expect(render(WebUIDelta("d", direction: .up)) == "<span class=\"delta delta--up\">▲ d</span>")
        #expect(render(WebUIDelta("d", direction: .down)) == "<span class=\"delta delta--down\">▼ d</span>")
        #expect(render(WebUIDelta("d", direction: .flat)).contains("delta delta--flat"))
        let slot: Trend = WebUIDelta("d").direction
        #expect(slot == .up)
    }

    @Test("Stat's up/down keep their bytes; flat forwards the pattern")
    func statTrends() {
        #expect(render(WebUIStat(label: "l", value: "v", trend: "+1", trendDirection: .up)).contains("stat__trend--up"))
        #expect(render(WebUIStat(label: "l", value: "v", trend: "-1", trendDirection: .down)).contains("stat__trend--down"))
        #expect(render(WebUIStat(label: "l", value: "v", trend: "0", trendDirection: .flat)).contains("stat__trend--flat"))
        let slot: Trend? = WebUIStat(label: "l", value: "v", trendDirection: .down).trendDirection
        #expect(slot == .down)
    }

    // MARK: the two type-level consolidations

    @Test("Notification's unused Kind resolves to Tone")
    func notificationKind() {
        // measured: `Kind` had no reader anywhere in the tree — no property, no
        // init parameter, no render use. it resolves to the shared vocabulary
        // rather than carrying a case set nothing consumed.
        let k: WebUINotification.Kind = .info
        #expect(k == Tone.info)
    }

    @Test("Separator's orientation is Axis, same bytes")
    func separatorOrientation() {
        #expect(render(WebUISeparator(orientation: .vertical)).contains("divider divider--vertical"))
        #expect(render(WebUISeparator(orientation: .horizontal)).contains("divider\""))
        let slot: Axis = WebUISeparator().orientation
        #expect(slot == .horizontal)
    }

    @Test("no component still declares a private state vocabulary")
    func sharedTypesAreTheSlots() {
        // the 1.x spellings resolve to the shared types, which is what makes a
        // generic bearer (and the W1.7 catalog invariants) possible at all.
        #expect(WebUIInput.State.self == ValidationState.self)
        #expect(WebUIValidation.State.self == ValidationState.self)
        #expect(WebUIInlineEdit.State.self == EditState.self)
        #expect(WebUIPullRefresh.State.self == LoadState.self)
        #expect(WebUIAttachment.State.self == LoadState.self)
        #expect(WebUIBadgeStatus.Status.self == Presence.self)
        #expect(WebUITimeline.Status.self == StepStatus.self)
        #expect(WebUIWizard.Status.self == StepStatus.self)
        #expect(WebUITimeline.Orientation.self == Axis.self)
        #expect(WebUISeparator.Orientation.self == Axis.self)
        #expect(WebUIDelta.Direction.self == Trend.self)
        #expect(WebUIStat.Trend.self == Trend.self)
        #expect(WebUINotification.Kind.self == Tone.self)
    }

    @Test("InputGroup's error state is a class, not a raw token")
    func inputGroupState() {
        // the cross-reference a full-suite run caught: `WebUIInputGroup` declared
        // `state: WebUIInput.State` and read `.rawValue` as a class fragment. once
        // the slot became `ValidationState` the raw value is the semantic token
        // ("none"/"error"), so the emitted class silently became `input error`.
        // this pins the bytes and the composed class string.
        #expect(render(WebUIInputGroup(placeholder: "x")).contains("class=\"input input--with-affix\""))
        #expect(render(WebUIInputGroup(placeholder: "x", state: .normal)).contains("class=\"input input--with-affix\""))
        #expect(render(WebUIInputGroup(placeholder: "x", state: .error)).contains("class=\"input input--with-affix input--error\""))
        #expect(render(WebUIInputGroup(placeholder: "x", state: .success)).contains("input--success"))
        #expect(render(WebUIInputGroup(placeholder: "x", state: .warning)).contains("input--warning"))
        #expect(!render(WebUIInputGroup(placeholder: "x", state: .error)).contains("\"input input--with-affix error\""))
    }
}