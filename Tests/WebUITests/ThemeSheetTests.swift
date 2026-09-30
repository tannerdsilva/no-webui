import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - content-addressed theme sheets
//
// The theme used to be inlined into every page, so it rode every navigation and grew with the
// scheme count (the plan's B7). Serving it from a content-addressed url is what makes it
// cacheable — and the address is computed from the bytes, so the url a page links and the url a
// server serves cannot disagree.

private let palette = ThemePalette(tokens: [.colorBg: "#FFFFFF"])
private let aTheme = WebUITheme(palette: palette)
private let otherTheme = WebUITheme(palette: ThemePalette(tokens: [.colorBg: "#000000"]))

private enum SheetCatalog: ThemeCatalog {
	static var all: [any WebUIThemeProvider.Type] { [One.self] }
	static var defaultTheme: any WebUIThemeProvider.Type { One.self }
	struct One: WebUIThemeProvider {
		static let themeID = "one"
		static var theme: WebUITheme { aTheme }
	}
}

@Suite("ThemeSheet")
struct ThemeSheetTests {

	@Test("the url is content-addressed: stable for the same bytes, new for new bytes")
	func contentAddress() {
		let a = ThemeSheet(css: aTheme.stylesheet(scope: .attribute(id: "x")))
		let b = ThemeSheet(css: aTheme.stylesheet(scope: .attribute(id: "x")))
		let c = ThemeSheet(css: otherTheme.stylesheet(scope: .attribute(id: "x")))
		#expect(a.url == b.url, "identical bytes must address identically")
		#expect(a.url != c.url, "a rebuilt sheet must be a NEW url, or a cache can never be invalidated")
		#expect(a.url.hasPrefix("/__assets/theme."))
	}

	@Test("renders a catalog, and reports emptiness")
	func rendersCatalog() {
		let sheet = ThemeSheet(catalog: SheetCatalog.self)
		#expect(!sheet.isEmpty)
		#expect(sheet.css.contains(#"[data-scheme="one"]"#))
		#expect(ThemeSheet(css: "").isEmpty)
	}

	@Test("the document LINKS the sheet instead of inlining it")
	func documentLinks() {
		let sheet = ThemeSheet(css: "/*x*/")
		let html = WebUIDocument(
			title: "t", body: "<p>x</p>", theme: aTheme, themeStylesheetURL: sheet.url
		).render()
		#expect(html.contains("href=\"\(sheet.url)\"") || html.contains(sheet.url))
		// nothing from the theme is inlined: that is the whole point of linking it.
		#expect(!html.contains("--color-bg: #FFFFFF;"),
			"a linked theme sheet must not also be inlined")
	}

	@Test("without a url the theme is still inlined — unchanged behaviour")
	func inlineRemains() {
		let html = WebUIDocument(title: "t", body: "<p>x</p>", theme: aTheme).render()
		#expect(html.contains("--color-bg: #FFFFFF;"))
	}

	@Test("the theme link comes AFTER the base sheet link, or the base would win")
	func linkOrder() {
		let sheet = ThemeSheet(css: "/*x*/")
		let html = WebUIDocument(
			title: "t", body: "<p>x</p>", theme: aTheme, themeStylesheetURL: sheet.url
		).render()
		guard let base = html.range(of: "href=\"\(DesignSystemAssets.stylesheetURL)\""),
			  let theme = html.range(of: sheet.url) else {
			Issue.record("both links must be present"); return
		}
		#expect(base.lowerBound < theme.lowerBound)
	}
}
