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
