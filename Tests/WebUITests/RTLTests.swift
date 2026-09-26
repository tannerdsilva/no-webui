import Testing
import WebUI
import WebUIDesignSystem

// p7-t5: base direction. the document can declare a direction (and omits it by
// default, so existing output is unchanged), and the sheet speaks logical
// properties so flipping the document actually mirrors the layout.

@Suite struct RTLTests {

	@Test func dirIsEmittedWhenSet() {
		let rtl = HTMLDocument(body: "<p>x</p>", dir: "rtl").render()
		#expect(rtl.contains("<html lang=\"en\" dir=\"rtl\">"), "dir must land on <html>")
		#expect(HTMLDocument(body: "<p>x</p>", dir: "ltr").render().contains("dir=\"ltr\""))
	}

	@Test func dirIsOmittedByDefault() {
		#expect(!HTMLDocument(body: "<p>x</p>").render().contains(" dir="),
			"no dir attribute unless asked for")
	}

	@Test func onlyRealDirectionsAreEmitted() {
		let html = HTMLDocument(body: "<p>x</p>", dir: "rtl; onload=alert(1)").render()
		#expect(!html.contains("onload"), "an invalid dir value is dropped, not written")
		#expect(!html.contains(" dir="))
	}

	@Test func theDesignSystemDocumentPassesDirThrough() {
		#expect(WebUIDocument(title: "t", body: "<p>x</p>", dir: "rtl").render()
			.contains("<html lang=\"en\" dir=\"rtl\">"))
	}
}

// the direction ratchet: what is left physical in the sheet must be exactly the
// geometry allowlist (widgets that place themselves physically by API, or draw a
// rotated border shape), so a new physical property fails the suite instead of
// quietly not mirroring. counts are pinned; lowering them is the goal.
@Suite struct SheetDirectionTests {

	static let allowed: [String: Int] = [
		"margin-left": 4,
		"margin-right": 0,
		"padding-left": 0,
		"padding-right": 0,
		"border-left": 2,
		"border-right": 5,
		"text-align: left": 0,
		"text-align: right": 0,
	]

	@Test func onlyTheGeometryAllowlistStaysPhysical() {
		let css = DesignSystemAssets.minifiedCss
		for (prop, expected) in Self.allowed.sorted(by: { $0.key < $1.key }) {
			let found = occ(css, prop)
			#expect(found == expected,
				"physical '\(prop)': found \(found), pinned \(expected) - convert new uses to logical properties, or justify them in this allowlist")
		}
	}

	@Test func theSheetUsesLogicalProperties() {
		let css = DesignSystemAssets.minifiedCss
		#expect(occ(css, "margin-inline-start") > 10)
		#expect(occ(css, "border-inline-end") > 5)
		#expect(occ(css, "text-align: start") >= 1)
	}
}
