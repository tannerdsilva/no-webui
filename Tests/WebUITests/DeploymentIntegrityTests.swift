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

// MARK: - WCAG contrast guardrail
//
// The design system is tuned by eye; this test makes that tuning checkable.
// It reads the actual fg/bg token values out of the embedded CSS (light, and
// the dark @media remap) and asserts every pair below clears WCAG AA (>= 4.5).
// If a future retune darkens a token and breaks legibility, this fails the build.

func wcagLuminance(_ hex: String) -> Double {
	var h = hex
	if h.hasPrefix("#") { h.removeFirst() }
	if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
	guard h.count == 6 else { return 0 }
	let chars = Array(h)
	func channel(_ i: Int) -> Double {
		let v = Double(Int(String(chars[i*2..<i*2+2]), radix: 16) ?? 0) / 255.0
		return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
	}
	let r = channel(0), g = channel(1), b = channel(2)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

func wcagRatio(_ a: String, _ b: String) -> Double {
	let la = wcagLuminance(a), lb = wcagLuminance(b)
	let hi = max(la, lb), lo = min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
}

// Read the hex value of a CSS custom property within a given CSS substring.
func cssTokenValue(_ name: String, in css: String) -> String? {
	guard let range = css.range(of: "--\(name):") else { return nil }
	let tail = css[range.upperBound...]
	let stop = tail.firstIndex(where: { $0 == ";" || $0.isNewline }) ?? tail.endIndex
	return String(tail[..<stop]).trimmingCharacters(in: .whitespaces)
}

@Test("solid action buttons meet WCAG AA in light mode")
func lightSolidButtonContrast() {
	let css = WebUIAssets.css
	#expect(wcagRatio("#ffffff", cssTokenValue("color-success-strong", in: css) ?? "000000") >= 4.5, "light success button label below AA")
	#expect(wcagRatio("#ffffff", cssTokenValue("color-warning-strong", in: css) ?? "000000") >= 4.5, "light warning button label below AA")
	#expect(wcagRatio("#ffffff", cssTokenValue("color-danger", in: css) ?? "000000") >= 4.5, "light danger button label below AA")
}

@Test("faint text and links meet WCAG AA on their surfaces (light + dark)")
func faintAndLinkContrast() {
	let css = WebUIAssets.css
	// light: faint text on the page background
	#expect(wcagRatio(cssTokenValue("color-text-faint", in: css) ?? "000000",
	                  cssTokenValue("color-bg", in: css) ?? "ffffff") >= 4.5, "light faint text below AA on page bg")
	// dark: faint text on the raised surface
	let darkStart = css.range(of: "@media (prefers-color-scheme: dark)")
	let dark = darkStart.map { String(css[$0.lowerBound...]) } ?? css
	#expect(wcagRatio(cssTokenValue("color-text-faint", in: dark) ?? "000000",
	                  cssTokenValue("color-bg-raised", in: dark) ?? "000000") >= 4.5, "dark faint text below AA on raised surface")
}

@Test("dark-mode solid buttons keep labels legible on the bright fill")
func darkSolidButtonContrast() {
	let css = WebUIAssets.css
	// The dark @media block re-tints success/warning/danger to bright fills;
	// the label must be the dark on-color ink (not white) to stay legible.
	let darkStart = css.range(of: "@media (prefers-color-scheme: dark)")
	let dark = darkStart.map { String(css[$0.lowerBound...]) } ?? css
	let ink = cssTokenValue("color-on-color", in: dark) ?? "000000"
	for token in ["color-success", "color-warning", "color-danger"] {
		let fill = cssTokenValue(token, in: dark) ?? "000000"
		#expect(wcagRatio(ink, fill) >= 4.5, "dark \(token) button label below AA on its bright fill")
	}
	// Guard: the override must actually be present, not accidentally dropped.
	#expect(dark.contains(".button.button--success"), "dark solid-button ink override missing (white-on-bright would return)")
}

