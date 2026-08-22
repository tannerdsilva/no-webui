import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - Package root

func packageRootURL() -> URL {
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

func readDesignerAsset(_ name: String) throws -> Data {
	let path = packageRootURL().appendingPathComponent("designer/assets/\(name)")
	return try Data(contentsOf: path)
}

// MARK: - Deployment integrity

@Test("embedded css is byte-identical to designer/assets/design-system.css")
func embeddedCSSMatchesSource() throws {
	let source = try readDesignerAsset("design-system.css")
	let embedded = Data(WebUIAssets.css.utf8)
	#expect(source == embedded, "embedded WebUIAssets.css differs from designer/assets/design-system.css (\(embedded.count) vs \(source.count) bytes)")
}

@Test("embedded js is byte-identical to designer/assets/webui-runtime.js")
func embeddedJSMatchesSource() throws {
	let source = try readDesignerAsset("webui-runtime.js")
	let embedded = Data(WebUIAssets.js.utf8)
	#expect(source == embedded, "embedded WebUIAssets.js differs from designer/assets/webui-runtime.js (\(embedded.count) vs \(source.count) bytes)")
}

@Test("embedded css pins the progress groove and left-anchor fixes")
func embeddedCSPinsVisualFixes() {
	let css = WebUIAssets.css
	#expect(css.contains("color-mix(in srgb, var(--color-neutral-200) 45%, var(--color-bg))"), "progress groove color missing from embedded css")
	#expect(css.contains("box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.12)"), "progress groove inset shadow missing from embedded css")
	#expect(css.contains("flex-direction: row"), "progress left-anchor fix missing from embedded css")
	#expect(css.contains("grid-area: 1 / 1"), "zstack overlap fix missing from embedded css")
}
