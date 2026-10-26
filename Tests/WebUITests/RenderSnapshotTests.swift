import Foundation
import Testing
import WebUI
import WebUIShowcaseContent

// a render snapshot with the per-render varying values normalized away.
//
// `c<n>` ids are minted in render order by `RenderContext` and are opaque; a
// document nonce is fresh per render. every other byte is contract. this is what
// makes a modifier migration reviewable: a diff is a defect, an id renumbering
// is not — auto ids are deliberately unstable across renders, which is exactly
// what `StableIDEventHandlerModifier` exists to avoid relying on.
//
// read from the source path rather than the bundle so record mode and compare
// mode see the same bytes in one build; the target's `resources:` declaration
// exists to keep swiftpm from warning about a non-Swift file in the directory.

@Suite("render snapshot")
struct RenderSnapshotTests {
	/// `\b` keeps base64 payloads and svg path data intact: an id is always a
	/// whole token, and a `c12` inside a longer word is not one. the csrf token
	/// is normalized because a fresh random nonce per render is its contract.
	static func normalize(_ html: String) -> String {
		html
			.replacing(/\bc[0-9]+\b/, with: "c#")
			.replacing(/nonce="[^"]*"/, with: "nonce=\"#\"")
			.replacing(/name="_csrf" value="[^"]*"/, with: "name=\"_csrf\" value=\"#\"")
	}

	/// the fixture's location relative to this file, which is stable in every
	/// checkout and needs no bundle lookup.
	static var sourceFixtureURL: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.appendingPathComponent("Fixtures/showcase.normalized.html")
	}

	/// the recorded bytes, or `nil` on a first run.
	static func recorded() -> String? {
		if let text = try? String(contentsOf: sourceFixtureURL, encoding: .utf8) {
			return text
		}
		guard let url = Bundle.module.url(
			forResource: "showcase.normalized",
			withExtension: "html",
			subdirectory: "Fixtures"
		) else { return nil }
		return try? String(contentsOf: url, encoding: .utf8)
	}

	/// the showcase as the server renders it, minus the values that vary.
	static func rendered() -> String {
		let state = ShowcaseState()
		let router = EventRouter()
		let context = RenderContext(router: router)
		return normalize(
			RenderContext.$current.withValue(context) {
				ShowcasePage(state: state).markup.html
			}
		)
	}

	@Test("the showcase renders byte-identically to the recorded snapshot")
	func showcaseMatchesSnapshot() throws {
		let actual = Self.rendered()
		if ProcessInfo.processInfo.environment["WEBUI_SNAPSHOT_RECORD"] == "1" {
			try actual.write(to: Self.sourceFixtureURL, atomically: true, encoding: .utf8)
			return
		}
		let expected = try #require(Self.recorded())
		#expect(actual == expected)
		#expect(!actual.isEmpty)
	}
}