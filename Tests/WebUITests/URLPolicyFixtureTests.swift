import Foundation
import Testing
import WebUI
import WebUICore

// p5-t5: the url policy is single-sourced in swift (`sanitizeURL`); the js
// copy is a mechanical pre-pass. the SHARED fixture (designer/url-payloads.json)
// drives BOTH sides: this suite drives the authority, and the node probe
// `designer/url-smoke.mjs` (run as a gate) drives the js mirror — with a
// verbatim-span pin below so the two can't drift silently.
struct URLPolicyFixtureTests {
	@Test("shared fixture drives the swift url sanitizer")
	func fixtureDrivesSwift() throws {
		let text = try String(contentsOfFile: "designer/url-payloads.json", encoding: .utf8)
		let root = try JSONValue.parse(text)
		guard case .array(let entries) = root else {
			Issue.record("fixture must be an array")
			return
		}
		#expect(entries.count >= 15, "fixture should grow, not shrink")
		for entry in entries {
			guard case .object(let dict) = entry,
			      case .string(let payload)? = dict["payload"],
			      case .bool(let expectedSafe)? = dict["safe"] else {
				Issue.record("malformed fixture entry: \(entry.serialize())")
				continue
			}
			let accepted = sanitizeURL(payload) != nil
			#expect(accepted == expectedSafe, "payload \(payload.debugDescription)")
		}
	}

	@Test("every payload carries an explicit verdict")
	func fixtureIsExplicit() throws {
		let text = try String(contentsOfFile: "designer/url-payloads.json", encoding: .utf8)
		let root = try JSONValue.parse(text)
		guard case .array(let entries) = root else {
			Issue.record("fixture must be an array")
			return
		}
		for entry in entries {
			guard case .object(let dict) = entry else {
				Issue.record("non-object entry")
				continue
			}
			#expect(dict["payload"] != nil)
			#expect(dict["safe"] != nil)
		}
	}

	@Test("the js probe mirror matches the shipped runtime verbatim")
	func probeMirrorsRuntime() throws {
		let runtime = try String(contentsOfFile: "designer/assets/webui-runtime.js", encoding: .utf8)
		let probe = try String(contentsOfFile: "designer/url-smoke.mjs", encoding: .utf8)
		// the exact spans the probe must carry and the runtime must carry —
		// drift on either side breaks the pin.
		let needles = [
			"var UNSAFE_PROTOCOLS = /^(javascript|data|vbscript):/i;",
			"function stripUrlControlChars(url) {",
			"function isSafeUrl(url) {",
		]
		for needle in needles {
			#expect(runtime.contains(needle), "runtime lost \(needle)")
			#expect(probe.contains(needle), "probe lost \(needle)")
		}
	}
}
