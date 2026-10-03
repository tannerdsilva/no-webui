import Testing
import WebUI
import WebUIBlocks
import WebUIDesignSystem

// pins the p6 block set: every block is a standalone document, made only of
// classes that exist in the sheet, carrying no dead (unwired) controls.

@Suite struct BlocksTests {

	@Test func everyBlockRendersAStandaloneDocument() {
		for block in WebUIBlocks.all {
			let html = WebUIBlocks.page(for: block)
			#expect(html.contains("<!DOCTYPE html>"), "\(block.rawValue) must render a full document")
			#expect(html.contains("webui-engine.js"), "\(block.rawValue) must boot the client runtime")
			#expect(html.count > 1500, "\(block.rawValue) body looks empty (\(html.count) bytes)")
		}
	}

	@Test func blocksCarryNoDeadControls() {
		for block in WebUIBlocks.all {
			let body = WebUIBlocks.body(for: block)
			#expect(!body.contains("data-component-id"),
				"\(block.rawValue) is a scaffold: it must not ship controls nobody handles")
		}
	}

	@Test func everyClassUsedByABlockExistsInTheSheet() {
		let css = DesignSystemAssets.minifiedCss
		for block in WebUIBlocks.all {
			let body = WebUIBlocks.body(for: block)
			let classes = Set(allCaptures(#"class="([^"]+)""#, in: body)
				.flatMap { $0.split(separator: " ").map(String.init) })
			let missing = classes.filter { !css.contains("." + $0) }.sorted()
			#expect(missing.isEmpty, "\(block.rawValue) uses classes absent from the sheet: \(missing)")
		}
	}

	@Test func indexLinksEveryBlock() {
		let index = WebUIBlocks.indexPage()
		for block in WebUIBlocks.all {
			#expect(index.contains("/blocks/" + block.rawValue), "index must link \(block.rawValue)")
		}
		#expect(index.contains("Blocks"), "index needs a title")
	}
}