import Foundation
import Testing
import WebUI
import WebUIDesignSystem

// MARK: - catalog serialization
//
// The catalog has to travel: d9 ships it to the client so switching needs no round trip, and
// P2e serves it as an asset. That makes the wire shape part of the contract, not an
// implementation detail — hence the shape assertions below, not just a round trip.

private let lightPalette = ThemePalette(
	tokens: [.colorBg: "#FFFFFF", .colorText: "#111111"],
	customTokens: ["--chat-bubble": "#EAEAEA"]
)
private let darkPalette = ThemePalette(tokens: [.colorBg: "#101014"])

@Suite("theme serialization")
struct ThemeCodableTests {

	@Test("a theme round-trips, losing nothing")
	func roundTrip() throws {
		let theme = WebUITheme(
			palette: lightPalette,
			dark: darkPalette,
			defaultMode: .dark,
			rules: [CSSRule(".x", [CSSDeclaration("color", "red")])]
		)
		let data = try JSONEncoder().encode(theme)
		let back = try JSONDecoder().decode(WebUITheme.self, from: data)
		#expect(back == theme, "a theme that does not survive a round trip cannot ship")
		#expect(back.palette.customTokens["--chat-bubble"] == "#EAEAEA")
		#expect(back.rules.count == 1)
	}

	@Test("palettes encode as objects keyed by token NAME, not as arrays of pairs")
	func wireShape() throws {
		let data = try JSONEncoder().encode(lightPalette)
		let text = String(decoding: data, as: UTF8.self)
		#expect(text.contains("\"color-bg\""), "the token's css name is the json key: \(text)")
		#expect(!text.contains("colorBg"), "the Swift case name must not leak onto the wire")
		// JSONSerialization proves the shape rather than a substring: it IS an object.
		let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		#expect(object?["tokens"] is [String: Any])
	}

	@Test("a whole catalog round-trips as one payload")
	func catalogPayload() throws {
		let entries = [
			ThemeEntry(id: "alpha", label: "Alpha", swatch: ["#111"], theme: WebUITheme(palette: lightPalette)),
			ThemeEntry(id: "beta", label: "Beta", theme: WebUITheme(palette: lightPalette, dark: darkPalette)),
		]
		let data = try JSONEncoder().encode(entries)
		let back = try JSONDecoder().decode([ThemeEntry].self, from: data)
		#expect(back.map(\.id) == ["alpha", "beta"])
		#expect(back[0].swatch == ["#111"])
		#expect(back[1].theme.dark.tokens[.colorBg] == "#101014")
	}

	@Test("the standard theme survives an empty round trip")
	func standardRoundTrips() throws {
		let data = try JSONEncoder().encode(WebUITheme.standard)
		#expect(try JSONDecoder().decode(WebUITheme.self, from: data) == .standard)
	}
}
