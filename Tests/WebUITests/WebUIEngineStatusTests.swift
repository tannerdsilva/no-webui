import Testing
import WebUI
import WebUIDesignSystem

// MARK: - WebUIEngineStatus

@Suite("WebUIEngineStatus")
struct WebUIEngineStatusTests {
	@Test("renders the mirror contract with both states and an honest default")
	func rendersContract() {
		let html = WebUIEngineStatus().render()
		#expect(html.contains("data-webui-status"))
		#expect(html.contains("data-webui-state=\"reconnecting\""))
		#expect(html.contains("__state--connected"))
		#expect(html.contains("__state--reconnecting"))
		#expect(html.contains("role=\"status\""))
	}
}

// MARK: - WebUIThemeToggle

@Suite("WebUIThemeToggle")
struct WebUIThemeToggleTests {
	@Test("renders the three choices with the engine contract")
	func rendersContract() {
		let html = WebUIThemeToggle().render()
		#expect(html.contains("data-theme-choice=\"system\""))
		#expect(html.contains("data-theme-choice=\"light\""))
		#expect(html.contains("data-theme-choice=\"dark\""))
		#expect(html.contains("role=\"group\""))
		#expect(html.contains("aria-label=\"Theme\""))
	}

	@Test("the toggle classes are real sheet classes (validator-known)")
	func toggleClassesKnown() {
		let known = HTMLClassValidator.definedClasses()
		#expect(known.contains("theme-toggle"))
		#expect(known.contains("theme-toggle__btn"))
	}
}
