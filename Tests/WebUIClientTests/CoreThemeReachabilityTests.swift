import Foundation
import Testing
import WebUICore
import WebUIDesignSystemCore

// MARK: - package root

func corePackageRootURL() -> URL {
	var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	while true {
		if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
			return url
		}
		let parent = url.deletingLastPathComponent()
		if parent == url {
			return url
		}
		url = parent
	}
}

// MARK: - theme-layer reachability (p5-t7)
//
// the p5-t7 split moved the theme layer — `DesignToken` (generated) plus the
// `WebUITheme`/`ColorScheme`/`WebUIThemeProvider` value types — into the
// wasm-clean `WebUIDesignSystemCore` target so the client build can reference
// it without rawdog. this suite imports Core directly (no `WebUI`, no
// `WebUIDesignSystem`) and pins the reachability: a regression back into the
// server-bound target fails right here.

@Suite("core theme layer reachability")
struct CoreThemeReachabilityTests {

	@Test("DesignToken is generated into the wasm-clean core")
	func tokenVocabularyPresent() throws {
		let css = try String(contentsOfFile: corePackageRootURL().appendingPathComponent("designer/assets/design-system.css").path, encoding: .utf8)
		for token in DesignToken.allCases {
			#expect(css.contains("--\(token.rawValue):"), "missing declaration for --\(token.rawValue)")
		}
		#expect(DesignToken.allCases.count == DesignToken.tokenCount, "tokenCount (\(DesignToken.tokenCount)) diverges from allCases (\(DesignToken.allCases.count))")
		#expect(DesignToken.colorPrimarySolid.cssVariable == "--color-primary-solid")
	}

	@Test("WebUITheme composes and renders a stylesheet from core types")
	func themeComposes() {
		let theme = WebUITheme(
			tokens: [.colorPrimarySolid: "#6c8cff", .colorBg: "#0b0b0f"],
			scheme: .dark,
			rules: [CSSRule(".app-shell", [CSSDeclaration("display", "grid")])]
		)
		let css = theme.stylesheet()
		#expect(css.contains(":root {"))
		#expect(css.contains("color-scheme: dark;"))
		#expect(css.contains("--color-primary-solid: #6c8cff;"))
		#expect(css.contains(".app-shell {"))
		#expect(!theme.isEmpty)
	}

	@Test("ColorScheme values map to the css color-scheme surface")
	func colorSchemeRenders() {
		#expect(ColorScheme.light.cssValue == "light")
		#expect(ColorScheme.dark.cssValue == "dark")
		#expect(ColorScheme.automatic.cssValue == nil)
		#expect(WebUITheme(scheme: .automatic).stylesheet() == "")
	}

	@Test("WebUIThemeProvider default yields the standard empty theme")
	func providerDefaultYieldsStandard() {
		struct Plain: WebUIThemeProvider {}
		#expect(Plain.theme == .standard)
		#expect(Plain.theme.isEmpty)
	}
}
