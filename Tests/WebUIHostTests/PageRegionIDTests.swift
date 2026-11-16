import Testing
import WebUIServer

@Suite("page region id")
struct PageRegionIDTests {
	// the page region's id is a wire contract: `navigate` patches the element
	// carrying it, and a consumer that needs to target the region must not
	// re-spell the literal.
	@Test("the page region id is public and matches the marker")
	func pageRegionIDIsPublic() {
		#expect(WebUIServer.pageRegionID == "webui-page")
	}
}
