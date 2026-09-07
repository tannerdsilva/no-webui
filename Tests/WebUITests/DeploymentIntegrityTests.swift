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

func readDesignerAsset(_ name: String) throws -> [UInt8] {
	let path = packageRootURL().appendingPathComponent("designer/assets/\(name)")
	return [UInt8]((try String(contentsOf: path, encoding: .utf8)).utf8)
}

// MARK: - Deployment integrity

@Test("embedded css is byte-identical to designer/assets/design-system.css")
func embeddedCSSMatchesSource() throws {
	let source = try readDesignerAsset("design-system.css")
	let embedded = Array(WebUIAssets.css.utf8)
	#expect(source == embedded, "embedded WebUIAssets.css differs from designer/assets/design-system.css (\(embedded.count) vs \(source.count) bytes)")
}

@Test("embedded js is byte-identical to designer/assets/webui-runtime.js")
func embeddedJSMatchesSource() throws {
	let source = try readDesignerAsset("webui-runtime.js")
	let embedded = Array(WebUIAssets.js.utf8)
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

@Test("an empty fragment html removes the element (ElementRef.remove() contract)")
func runtimeEmptyFragmentRemovesElement() throws {
	let js = WebUIAssets.js
	// ElementRef.remove()/me.remove() emit FragmentUpdate(id:, html: "") — the
	// runtime must treat an empty fragment as "remove the element", never as a
	// no-op replace. this is the pinned contract behind the .onDismiss API.
	#expect(js.contains("if (!fragment.firstChild)"), "runtime lost the empty-fragment removal branch (ElementRef.remove() would no-op)")
	#expect(js.contains("el.remove()"), "runtime lost the element removal call")
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

// MARK: - JS runtime event-pipeline resilience
//
// These guardrails pin the debounce + liveness + focus behavior of the JS
// runtime so a regression that re-introduces per-keystroke flooding, a dead
// keepalive, or focus loss on fragment patch fails the build.

@Test("runtime debounces input with trailing + max-wait semantics")
func runtimeInputDebounceSemantics() {
	let js = WebUIAssets.js
	#expect(js.contains("setTimeout(flush, config.debounceInputMs)"), "input debounce no longer schedules a trailing flush on debounceInputMs")
	#expect(js.contains("config.debounceMaxWaitMs"), "input debounce lost its max-wait cap")
	#expect(js.contains("entry.lastSent"), "input debounce lost its last-send timestamp (max-wait would stop enforcing)")
}

@Test("runtime clears the keepalive timer when a pong arrives")
func runtimePongClearsKeepalive() {
	let js = WebUIAssets.js
	#expect(js.contains("msg.type === 'pong'"), "runtime no longer detects pong messages")
	#expect(js.contains("clearTimeout(pongTimer)"), "pong no longer cancels the pending reconnect timer (liveness detection is dead)")
}

@Test("runtime preserves focus across fragment patches")
func runtimePreservesFocusOnPatch() {
	let js = WebUIAssets.js
	#expect(js.contains("document.activeElement"), "runtime no longer records which input had focus before a patch")
	#expect(js.contains("record.focused = true"), "runtime lost the per-input focused flag")
	#expect(js.contains("focusTarget.focus()"), "runtime no longer restores focus after replacing a fragment")
}

@Test("runtime coerces multi-select form values to a string for the wire protocol")
func runtimeStringifiesMultiSelect() {
	let js = WebUIAssets.js
	#expect(js.contains("values.join(',')"), "select-multiple now sends an array, but WSIncoming.data is [String: String] (Swift decode would reject the form)")
}

@Test("runtime guards against a missing WebSocket")
func runtimeHandlesNoWebSocket() {
	let js = WebUIAssets.js
	#expect(js.contains("typeof WebSocket === 'undefined'"), "runtime lost its guard for environments without WebSocket")
}

@Test("shipped page carries a single nexus token set (no stale teal block)")
func shippedPageCarriesOnlyNexusTokens() {
	let page = WebUIDocument(title: "token pin", body: "").render()
	#expect(!page.contains("#10b89f"), "stale teal primary shipped on the wire")
	#expect(!page.contains("#16a34a"), "stale teal success shipped on the wire")
	#expect(!page.contains("#f6f8fa"), "stale teal surface shipped on the wire")
	#expect(page.contains("#6366f1"), "nexus primary missing from shipped page")
	#expect(page.components(separatedBy: "--color-primary-500:").count == 2, "more than one --color-primary-500 definition on the wire")
}

@Test("every token documented in DESIGN_SYSTEM.md exists in the shipped css")
func documentedTokensExistInCss() throws {
	let url = packageRootURL().appendingPathComponent("Documentation/DESIGN_SYSTEM.md")
	let doc = try String(contentsOf: url, encoding: .utf8)
	let css = WebUIAssets.css
	let regex = /`(--[a-z0-9-]+)`/
	var checked = 0
	var missing: [String] = []
	for m in doc.matches(of: regex) {
		let token = String(m.1)
		if css.contains(token) {
			checked += 1
		} else {
			missing.append(token)
		}
	}
	#expect(missing.isEmpty, "documented tokens missing from shipped css: \(missing)")
	#expect(checked > 20, "drift guard parsed too few backticked tokens from DESIGN_SYSTEM.md (\(checked))")
}

@Test("runtime wires the router with its logger in scope")
func runtimeRouterLoggerInScope() {
	let js = WebUIAssets.js
	#expect(js.contains("function createRouter(log)"), "router lost its logger param — redirect/navigate would reference an out-of-scope log")
	#expect(js.contains("createMessageDispatcher(log, fragmentPatcher, stateStore, router)"), "dispatcher no longer receives the router — the client redirect path is dead")
}

@Test("runtime applies optimistic predictions before sending the event")
func runtimeAppliesOptimisticPredictions() {
	let js = WebUIAssets.js
	#expect(js.contains("data-optimistic"), "runtime lost the optimistic prediction hook")
	#expect(js.contains("optimisticSettleMs"), "runtime lost the optimistic settle timeout knob")
	#expect(js.contains("patch(pred, null, true)"), "runtime no longer patches predictions with the optimistic flag before send")
}

@Test("runtime EVENT_TYPES covers every fluent event modifier")
func runtimeEventTypesCoverFluentModifiers() {
	let js = WebUIAssets.js
	#expect(js.contains("'click', 'input', 'change', 'submit', 'keydown', 'keyup', 'keypress', 'focus', 'blur', 'focusin', 'focusout', 'mouseover', 'mouseout', 'mousedown', 'mouseup'"), "EVENT_TYPES drifted from the delivered set")
}

@Test("runtime saves and restores scroll position across fragment patches")
func runtimePreservesScrollOnPatch() {
	let js = WebUIAssets.js
	#expect(js.contains("saveScroll"), "runtime lost the scroll-snapshot helper")
	#expect(js.contains("scrollTop") && js.contains("scrollLeft"), "runtime no longer reads scroll positions")
	#expect(js.contains("'scroll:'"), "runtime scroll records missing")
	#expect(js.contains("'focus:'"), "runtime non-form focus records missing")
}

@Test("every ColorToken case resolves to a token defined in the shipped css")
func colorTokensResolveInCss() {
	let css = WebUIAssets.css
	var missing: [String] = []
	for token in ColorToken.allCases where !css.contains("--\(token.rawValue):") {
		missing.append("--\(token.rawValue)")
	}
	#expect(missing.isEmpty, "color tokens missing from shipped css: \(missing)")
}

@Test("every SpaceToken case resolves to a token defined in the shipped css")
func spaceTokensResolveInCss() {
	let css = WebUIAssets.css
	var missing: [String] = []
	for token in SpaceToken.allCases where !css.contains("\(token.cssVariable):") {
		missing.append(token.cssVariable)
	}
	#expect(missing.isEmpty, "space tokens missing from shipped css: \(missing)")
}

