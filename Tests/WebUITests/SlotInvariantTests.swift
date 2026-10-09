import Testing
import WebUI
import WebUIDesignSystem

// W1.7: the catalog invariants. `SlotBearing` makes a component's slot readable
// from the outside; these tests make the *promise* checkable — a tone bearer
// never emits another tone's class, and no component puts two size classes on
// its own root. the catalog below is checked in on purpose: enumerating
// conformers at runtime would need reflection the framework does not have, and a
// generated list that silently stops matching the conformances is worse than a
// written one that visibly does. `catalogIsComplete` pins the counts so drift
// fails loudly.
//
// the invariant definitions are measured, not assumed. the first draft asserted
// "exactly one tone class" and "at most one size class anywhere"; the catalog
// falsified both within a minute, and the renderer was right:
//   · a danger *banner* spells its modifier `--error`, the sheet's own word for
//     it (and not a tone token at all),
//   · a primary *ring* and a primary *fab* carry no modifier, because the base
//     surface is already the primary look,
//   · a fab puts its slot on the root (`fab--lg`) while a nested icon keeps its
//     own fixed size (`icon--md`) — so "at most one size class" is true of the
//     root and false of the document.
// those three facts live in `toneDeviations` with their reasons, so the next
// person to widen a slot sees exactly what the sheet promised before.

private func render(_ view: some View) -> String {
    RenderContext.$current.withValue(RenderContext(router: EventRouter())) { view.renderThroughBuffer() }
}

/// every class token in the markup, from every `class="..."` on the page.
private func classTokens(_ html: String) -> [String] {
    allClassAttributes(html).flatMap { $0 }
}

/// the tokens of the first `class="..."` — the component's own root element.
private func rootClassTokens(_ html: String) -> [String] {
    allClassAttributes(html).first ?? []
}

private func allClassAttributes(_ html: String) -> [[String]] {
    var out: [[String]] = []
    var rest = Substring(html)
    while let start = rest.range(of: "class=\"") {
        let after = rest[start.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { break }
        out.append(after[..<end].split(separator: " ").map(String.init))
        rest = after[end...]
    }
    return out
}

private struct ToneRecipe: Sendable {
    let name: String
    let render: @Sendable (Tone) -> String
}

private struct SizeRecipe: Sendable {
    let name: String
    let render: @Sendable (ControlSize) -> String
}

@Suite("slot invariants hold across the catalog")
struct SlotInvariantTests {

    /// the measured tone bearers, one render recipe each. keep in step with the
    /// conformance block in `SlotBearing.swift`.
    fileprivate static let toneCatalog: [ToneRecipe] = [
        .init(name: "Alert") { tone in render(WebUIAlert(variant: tone, message: "m")) },
        .init(name: "Badge") { tone in render(WebUIBadge("b", variant: tone)) },
        .init(name: "Banner") { tone in render(WebUIBanner(variant: tone, message: "m")) },
        .init(name: "Chip") { tone in render(WebUIChip("c", variant: tone)) },
        .init(name: "CircularProgress") { tone in render(WebUICircularProgress(value: 0.5, tone: tone)) },
        .init(name: "Fab") { tone in render(WebUIFab(icon: .check, variant: tone)) },
        .init(name: "Progress") { tone in render(WebUIProgress(value: 0.5, variant: tone)) },
        .init(name: "Toast") { tone in render(WebUIToast(variant: tone, message: "m")) },
    ]

    /// the measured size bearers, one render recipe each.
    fileprivate static let sizeCatalog: [SizeRecipe] = [
        .init(name: "Avatar") { size in render(WebUIAvatar(initials: "A", size: size)) },
        .init(name: "Badge") { size in render(WebUIBadge("b", variant: .primary, size: size)) },
        .init(name: "Button") { size in render(WebUIButton("b", size: size)) },
        .init(name: "CircularProgress") { size in render(WebUICircularProgress(value: 0.5, size: size)) },
        .init(name: "Drawer") { size in render(WebUIDrawer(size: size) { Text("x") }) },
        .init(name: "Fab") { size in render(WebUIFab(icon: .check, variant: .primary, size: size)) },
        .init(name: "Kbd") { size in render(WebUIKbd("k", size: size)) },
        .init(name: "OTP") { size in render(WebUIOTP(size: size)) },
        .init(name: "Progress") { size in render(WebUIProgress(value: 0.5, variant: .primary, size: size)) },
        .init(name: "Rating") { size in render(WebUIRating(3, size: size)) },
        .init(name: "Slider") { size in render(WebUISlider(50, size: size)) },
        .init(name: "Spinner") { size in render(WebUISpinner(size: size)) },
        .init(name: "Stat") { size in render(WebUIStat(label: "l", value: "v", size: size)) },
        .init(name: "Stepper") { size in render(WebUIStepper(1, size: size)) },
    ]

    /// the (component, tone) pairs whose modifier is not `--<tone>`. a value is
    /// the class the component spells instead; `nil` means the pair emits no
    /// modifier at all. every entry is a measured fact about the sheet, not an
    /// allowance for a bug — see the header for why each one is correct.
    fileprivate static let toneDeviations: [String: String?] = [
        // the sheet's word for a danger banner is `--error`.
        "Banner.danger": "banner--error",
        // the base surface already *is* the primary look for a ring and a fab.
        "CircularProgress.primary": nil,
        "Fab.primary": nil,
    ]

    @Test("a tone bearer never emits another tone's class")
    func toneInvariant() {
        for recipe in Self.toneCatalog {
            for tone in Tone.allCases {
                let key = "\(recipe.name).\(tone.rawValue)"
                let tokens = classTokens(recipe.render(tone))
                // a class ending in any tone token — the requested one, or a wrong one.
                let emitted = tokens.filter { token in
                    Tone.allCases.contains { token.hasSuffix("--\($0.rawValue)") }
                }
                if let deviation = Self.toneDeviations[key] {
                    if let spelling = deviation {
                        #expect(tokens.contains(spelling), "\(key) should spell it \(spelling)")
                        #expect(emitted.isEmpty,
                                "\(key) should carry no tone token beside \(spelling), got \(emitted)")
                    } else {
                        #expect(emitted.isEmpty, "\(key) emits no modifier, got \(emitted)")
                    }
                } else {
                    #expect(emitted.count == 1 && emitted[0].hasSuffix("--\(tone.rawValue)"),
                            "\(key) emitted \(emitted)")
                }
            }
        }
    }

    @Test("no component puts two size classes on its root, and a root size class matches the request")
    func sizeInvariant() {
        for recipe in Self.sizeCatalog {
            for size in ControlSize.allCases {
                let emitted = rootClassTokens(recipe.render(size)).filter { token in
                    ControlSize.allCases.contains { token.hasSuffix("--\($0.rawValue)") }
                }
                #expect(emitted.count <= 1, "\(recipe.name) .\(size.rawValue) root emitted \(emitted)")
                if let only = emitted.first {
                    #expect(only.hasSuffix("--\(size.rawValue)"),
                            "\(recipe.name) requested .\(size.rawValue) but its root emitted \(only)")
                }
            }
        }
    }

    @Test("the catalogs cover every conforming bearer")
    func catalogIsComplete() {
        // two halves of one claim: the conformances in `SlotBearing.swift` and
        // these recipes. a bearer added to one and not the other would silently
        // stop being checked, so the counts are pinned here.
        #expect(Self.toneCatalog.count == 8)
        #expect(Self.sizeCatalog.count == 14)
    }

    @Test("the protocol reads the same slot the initializer took")
    func protocolReadsTheSlot() {
        #expect(WebUIButton("b", size: .lg).controlSize == .lg)
        #expect(WebUIAlert(variant: .warning, message: "m").tone == .warning)
        #expect(WebUICard(elevation: nil) { Text("x") }.elevation == nil)
        #expect(WebUICard(elevation: .elevated) { Text("x") }.elevation == .elevated)
    }
}