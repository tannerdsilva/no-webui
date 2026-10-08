import Testing
import WebUIDesignSystem

// one semantic vocabulary
// (`.hermes/plans/2026-10-08_151549-GENERAL_WEB_CAPABILITY.md`, W1.1).
//
// measured at the wave start: 15 nested `Size` enums, 13 nested `Variant`, 5
// `State`, 3 `Status`, 2 `Side`, 2 `Edge`, 2 `Brand` — and their raw values are
// **css class fragments**, not semantic tokens:
//
//   WebUIStat.Size.sm       = "stat stat--sm"
//   WebUIStat.Trend.up      = "stat__trend--up"
//   WebUICircularProgress.Tone.success = "ring--success"
//   WebUICircularProgress.Tone.primary = ""            <- the empty string
//   WebUICardInput.Brand.visa = " card-input__brand-icon--visa"   <- leading space
//
// `Brand` is declared twice (`WebUIExtrasData.swift` and `WebUIExtrasForm.swift`)
// with different raw value sets, so the same word means two things.
//
// `Vocabulary.swift` declares each semantic slot once, at top level, with the
// semantic token as its raw value. the nested component enums are the migration
// tail (W1.2-W1.7) — this suite is the invariant they must converge on, stated
// once instead of as 18 hand-written suites.

/// the shape every semantic slot shares: a finite set of cases whose raw value is
/// a semantic token.
///
/// declared here rather than in the framework on purpose — the framework-side
/// bearers (`SizeBearing`/`ToneBearing`) belong to W2.1, and this is exactly the
/// property they will require. putting it in the test target first keeps the
/// implementation surface honest: nothing consumes it yet.
private protocol SemanticSlot: CaseIterable, RawRepresentable, Sendable where RawValue == String {}

extension ControlSize: SemanticSlot {}
extension Emphasis: SemanticSlot {}
extension Tone: SemanticSlot {}
extension Elevation: SemanticSlot {}
extension StepStatus: SemanticSlot {}
extension LoadState: SemanticSlot {}
extension ValidationState: SemanticSlot {}
extension EditState: SemanticSlot {}
extension Presence: SemanticSlot {}
extension Placement: SemanticSlot {}
extension Trend: SemanticSlot {}
extension Axis: SemanticSlot {}
extension PanelEdge: SemanticSlot {}
extension DrawerEdge: SemanticSlot {}
extension SlidePosition: SemanticSlot {}
extension SkeletonShape: SemanticSlot {}
extension Brand: SemanticSlot {}
extension Directionality: SemanticSlot {}

/// a semantic token: one lowercase word, optionally digit- or hyphen-joined.
///
/// this is the test that stops the old leak from returning. it rejects, by
/// construction, every shape the nested enums used — `"stat stat--sm"` (space,
/// `--`), `"stat__trend--up"` (`_`, `--`), `"ring--success"` (`--`),
/// `" card-input__brand-icon--visa"` (leading space, `_`, `--`) — and the empty
/// string, which `WebUICircularProgress.Tone.primary` used for "no modifier".
private func isSemanticToken(_ raw: String) -> Bool {
    guard let first = raw.first, first.isLowercase else { return false }
    guard !raw.hasPrefix("-"), !raw.hasSuffix("-") else { return false }
    guard !raw.contains("--"), !raw.contains(" "), !raw.contains("_") else { return false }
    return raw.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
}

@Suite("one semantic vocabulary")
struct VocabularyTests {

    /// every slot, with its own display name so a failure names the type.
    ///
    /// the `allCases` call is the mechanical part: a case added to any type is
    /// checked by every test below without touching this list.
    private static var slots: [(name: String, raws: [String])] {
        [
            ("ControlSize", ControlSize.allCases.map(\.rawValue)),
            ("Emphasis", Emphasis.allCases.map(\.rawValue)),
            ("Tone", Tone.allCases.map(\.rawValue)),
            ("Elevation", Elevation.allCases.map(\.rawValue)),
            ("StepStatus", StepStatus.allCases.map(\.rawValue)),
            ("LoadState", LoadState.allCases.map(\.rawValue)),
            ("ValidationState", ValidationState.allCases.map(\.rawValue)),
            ("EditState", EditState.allCases.map(\.rawValue)),
            ("Presence", Presence.allCases.map(\.rawValue)),
            ("Placement", Placement.allCases.map(\.rawValue)),
            ("Trend", Trend.allCases.map(\.rawValue)),
            ("Axis", Axis.allCases.map(\.rawValue)),
            ("PanelEdge", PanelEdge.allCases.map(\.rawValue)),
            ("DrawerEdge", DrawerEdge.allCases.map(\.rawValue)),
            ("SlidePosition", SlidePosition.allCases.map(\.rawValue)),
            ("SkeletonShape", SkeletonShape.allCases.map(\.rawValue)),
            ("Brand", Brand.allCases.map(\.rawValue)),
            ("Directionality", Directionality.allCases.map(\.rawValue)),
        ]
    }

    @Test("every slot is a raw-value string enum with a non-empty case set")
    func slotsAreNonEmpty() {
        for slot in Self.slots {
            #expect(!slot.raws.isEmpty, "\(slot.name) has no cases")
        }
        #expect(Self.slots.count == 18, "the vocabulary changed size — update this list")
    }

    @Test("no raw value is a css class fragment")
    func noClassFragments() {
        for slot in Self.slots {
            for raw in slot.raws {
                #expect(
                    isSemanticToken(raw),
                    "\(slot.name).\(raw.isEmpty ? "<empty>" : raw) is not a semantic token"
                )
            }
        }
    }

    @Test("raw values are unique within a type")
    func rawValuesAreUnique() {
        // two cases sharing a raw value makes `init(rawValue:)` silently lossy —
        // the second case is unreachable from a string.
        for slot in Self.slots {
            #expect(
                Set(slot.raws).count == slot.raws.count,
                "\(slot.name) has duplicate raw values: \(slot.raws)"
            )
        }
    }

    @Test("init(rawValue:) round-trips for every case")
    func rawValueRoundTrips() {
        // the enum is the contract's vocabulary: a case that cannot be recovered
        // from its own raw value is not addressable from a string (a config file,
        // a data attribute, a test).
        func roundTrip<T: SemanticSlot & Equatable>(_ type: T.Type) {
            for c in T.allCases {
                #expect(T(rawValue: c.rawValue) == c, "\(T.self).\(c.rawValue) does not round-trip")
            }
        }
        roundTrip(ControlSize.self); roundTrip(Emphasis.self); roundTrip(Tone.self)
        roundTrip(Elevation.self); roundTrip(StepStatus.self); roundTrip(LoadState.self)
        roundTrip(ValidationState.self); roundTrip(EditState.self); roundTrip(Presence.self)
        roundTrip(Placement.self); roundTrip(Trend.self); roundTrip(Axis.self)
        roundTrip(PanelEdge.self); roundTrip(DrawerEdge.self); roundTrip(SlidePosition.self)
        roundTrip(SkeletonShape.self); roundTrip(Brand.self); roundTrip(Directionality.self)
    }

    @Test("the shapes the nested enums used are rejected by the token rule")
    func tokenRuleRejectsTheOldShapes() {
        // the rule is only worth having if it fails on the real values it is meant
        // to exclude — so it is tested against them directly, with the empty
        // string, the class fragment, the prefixed variant, and a clean control.
        #expect(!isSemanticToken(""))
        #expect(!isSemanticToken("stat stat--sm"))
        #expect(!isSemanticToken("stat__trend--up"))
        #expect(!isSemanticToken("ring--success"))
        #expect(!isSemanticToken(" card-input__brand-icon--visa"))
        #expect(!isSemanticToken("-leading"))
        #expect(!isSemanticToken("trailing-"))
        #expect(isSemanticToken("sm"), "a clean token must pass")
        #expect(isSemanticToken("xxl"))
        #expect(isSemanticToken("primary"))
    }
}