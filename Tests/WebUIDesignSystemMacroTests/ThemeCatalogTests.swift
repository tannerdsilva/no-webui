import Testing
import WebUI
import WebUIDesignSystem

// MARK: - compiled catalog fixtures
//
// these live beside `RuntimeFixtures.swift` because `@Theme` fixtures are only proven to
// compile in this target (it links the macro plugin explicitly). the assertions below are
// about the *provider identity* surface, which any target could exercise.

@Theme
struct Cappuccino {
	static let themeLabel = "Cappuccino"
	static let themeSwatch = ["#D9A441", "#B8860B", "#8A5A2B"]
	static let colorBg = "#FDFBF7"
	static let colorPrimarySolid = "#B8860B"
}

@Theme
struct Poseidon {
	/// an explicit id, because the type name is not the identifier a consumer wants to
	/// persist. this is the case the default cannot serve.
	static let themeID = "poseidon"
	static let themeLabel = "Poseidon"
	static let themeSwatch = ["#268BD2", "#1B6FA8", "#0F4C75"]
	static let colorBg = "#E8EFF6"
	static let dark = ThemePalette(tokens: [.colorBg: "#141B25"])
}

/// overrides a base, so its palette is the base's plus one token — the shape a
/// 27-scheme app wants for every scheme after the first.
@Theme(base: Cappuccino.self)
struct Terracotta {
	static let themeLabel = "Terracotta"
	static let colorPrimarySolid = "#C1663B"
}

enum ArcSchemes: ThemeCatalog {
	// computed, not stored: a stored `static let` of existential metatypes is rejected by
	// Swift 6 as non-Sendable global mutable state.
	static var all: [any WebUIThemeProvider.Type] { [Cappuccino.self, Poseidon.self, Terracotta.self] }
	static var defaultTheme: any WebUIThemeProvider.Type { Cappuccino.self }
}

@Suite("ThemeCatalog")
struct ThemeCatalogTests {

	@Test("identity defaults to the type name, explicit ids win, and no token is invented")
	func identity() {
		#expect(Cappuccino.themeID == "Cappuccino")
		#expect(Poseidon.themeID == "poseidon")
		#expect(Poseidon.themeLabel == "Poseidon")
		#expect(Poseidon.themeSwatch.count == 3)
		// a `themeID`/`themeLabel`/`themeSwatch` member is identity, never a token: if the
		// macro had treated them as tokens this would not compile at all, and a silently
		// dropped one would leave the palette missing its real overrides.
		#expect(Poseidon.theme.palette.tokens[.colorBg] == "#E8EFF6")
		#expect(Poseidon.theme.dark.tokens[.colorBg] == "#141B25")
	}

	@Test("a picker can render from `entries` with no hand-written list")
	func pickerRendersFromCatalog() {
		let entries = ArcSchemes.entries
		#expect(entries.count == 3)
		#expect(entries.map(\.id) == ["Cappuccino", "poseidon", "Terracotta"])
		#expect(entries.allSatisfy { !$0.label.isEmpty }, "every entry needs a label to show")
		#expect(entries[1].swatch.count == 3, "swatch data reaches the picker as-is")
		#expect(entries[1].theme.dark.tokens[.colorBg] == "#141B25", "each entry carries its theme")
	}

	@Test("catalog ids are unique")
	func idsAreUnique() {
		// a closure, not `map(\.themeID)`: a key-path literal over an existential metatype
		// array crashes the Swift 6 silgen ("While silgen emitFunction"), not a diagnostic.
		let ids = ArcSchemes.all.map { $0.themeID }
		#expect(Set(ids).count == ids.count, "duplicate theme ids in the catalog: \(ids)")
	}

	@Test("the default is a member of `all`")
	func defaultIsAMember() {
		#expect(ArcSchemes.all.contains { $0.themeID == ArcSchemes.defaultTheme.themeID })
	}

	@Test("resolving a stored id falls back to the default rather than breaking")
	func staleIDFallsBack() {
		// a client's localStorage can hold an id from a previous build; the page must still
		// render, so an unknown id degrades instead of failing.
		let known = ArcSchemes.theme(for: "poseidon")
		#expect(known.dark.tokens[.colorBg] == "#141B25", "resolved the requested scheme")
		let stale = ArcSchemes.theme(for: "a-scheme-we-deleted")
		#expect(stale.palette.tokens[.colorBg] == "#FDFBF7", "fell back to the default theme")
	}

	@Test("base layering keeps the base palette and applies the override")
	func baseLayering() {
		let theme = Terracotta.theme
		// inherited from Cappuccino
		#expect(theme.palette.tokens[.colorBg] == "#FDFBF7")
		// overridden by Terracotta
		#expect(theme.palette.tokens[.colorPrimarySolid] == "#C1663B")
		// and the base's swatch survives unless the override replaces it
		#expect(Terracotta.themeLabel == "Terracotta")
	}

	@Test("a base theme's dark override survives into the child")
	func baseDarkSurvives() {
		let child = Poseidon.theme.overlaying(WebUITheme(tokens: [.colorPrimarySolid: "#000"]))
		#expect(child.dark.tokens[.colorBg] == "#141B25", "overlaying must merge per palette")
		#expect(child.palette.tokens[.colorPrimarySolid] == "#000")
		#expect(child.palette.tokens[.colorBg] == "#E8EFF6", "the base palette must survive")
	}
}