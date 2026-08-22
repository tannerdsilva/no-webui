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

@Test("runtime resolves form controls whose data-component-id sits on their label")
func runtimeResolvesLabelForInputs() throws {
	let js = WebUIAssets.js
	#expect(js.contains("data-component-id"), "runtime no longer carries the component-id lookup")
	#expect(js.contains("target.labels"), "runtime lost the labels[] resolution for inputs (typing would stop round-tripping)")
	#expect(js.contains("label[for=\""), "runtime lost the label[for=id] fallback for inputs")
}

@Test("runtime sends keydown modifier keys as strings to match the wire protocol")
func runtimeStringifiesKeydownModifiers() throws {
	let js = WebUIAssets.js
	#expect(js.contains("String(event.ctrlKey)"), "runtime sends ctrlKey as a JS boolean, but WSIncoming.data is [String: String]")
	#expect(js.contains("String(event.shiftKey)"), "runtime sends shiftKey as a JS boolean; Swift decode would reject the event")
	#expect(js.contains("String(event.altKey)"), "runtime sends altKey as a JS boolean; Swift decode would reject the event")
	#expect(js.contains("String(event.metaKey)"), "runtime sends metaKey as a JS boolean; Swift decode would reject the event")
}
