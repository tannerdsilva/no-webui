import Foundation
import Testing
import WebUI

// MARK: - ContinuumInventoryTests
//
// the t1.3 class-inventory pin (lane B): the generated ContinuumClassInventory
// is the static half of the css-reachability machinery, and these counts are
// the contract the engine's attr apply + the orphan ratchet build on. a change
// to WebUIDesignSystemCore components (a new literal class, an @HotClass
// vocabulary) must land here deliberately — this test is the re-measure gate.
//
// warn-baseline for unclaimed: d1 keeps unclaimed as a lint warn, so the pin is
// an asserted baseline, not an error source. when a literal appears nobody
// claims, this test names it so the owning component claims it.

@Suite struct ContinuumInventoryTests {

    @Test("per-component vocabularies match the measured d0 count")
    func componentCounts() {
        #expect(ContinuumClassInventory.components.count == 2,
                "expected 2 components; if WebUIDesignSystemCore gained a component with literal classes, re-measure and re-pin deliberately")
        #expect(ContinuumClassInventory.components["WebUIEngineStatus"]?.count == 5,
                "WebUIEngineStatus claims the engine-status-* vocabulary (×5)")
        #expect(ContinuumClassInventory.components["WebUIThemeToggle"]?.count == 2,
                "WebUIThemeToggle claims the theme-toggle* vocabulary (×2)")
    }

    @Test("the union holds every claimed class, sorted")
    func union() {
        #expect(ContinuumClassInventory.union.count == 7,
                "7 classes across 2 components (measured d0 tree)")
        #expect(ContinuumClassInventory.union == [
            "engine-status-mirror",
            "engine-status-mirror__dot",
            "engine-status-mirror__state",
            "engine-status-mirror__state--connected",
            "engine-status-mirror__state--reconnecting",
            "theme-toggle",
            "theme-toggle__btn",
        ], "union is the sorted claim set")
    }

    @Test("the attr-op allowlist base is class/aria-*/data-*")
    func attributeAllowlist() {
        #expect(ContinuumClassInventory.attributeAllowlist == ["class", "aria-*", "data-*"],
                "the generated base allowlist for the attr op — component-declared names join it via @HotClass")
    }

    @Test("no unclaimed class literals (warn-baseline)")
    func unclaimedBaseline() {
        // warn-only in d1: this is a baseline pin, not the error level (the
        // orphan ratchet owns that). a growth here names the literal so its
        // owning component can claim it in the same commit.
        #expect(ContinuumClassInventory.unclaimedLiterals.isEmpty,
                "unclaimed literal(s): \(ContinuumClassInventory.unclaimedLiterals) — claim them in the owning component or an @HotClass vocabulary, then re-measure")
    }

    @Test("the served engine slice ships a WebUIShippedAsset conformance")
    func engineSliceRegistered() {
        // d2 §1.5 / lane B wave 2: the engine's allowlist slice is served,
        // content-addressed, exactly like the css — ContinuumEngineManifest is
        // the generated conformance (stamp = sha256 prefix). its presence is
        // the closing of lane E's wave-1 static-seed handoff.
        #expect(!ContinuumEngineManifest.stamp.isEmpty,
                "the engine slice has a content address")
        #expect(ContinuumEngineManifest.contentType.hasPrefix("application/json"),
                "the engine slice is served as json")
        #expect(!ContinuumEngineManifest.body.isEmpty,
                "the engine slice carries an allowlist payload")
        let text = ContinuumEngineManifest.text
        #expect(text.contains("\"attributeAllowlist\""),
                "the payload carries the attribute allowlist: \(text.prefix(120))")
    }
}
