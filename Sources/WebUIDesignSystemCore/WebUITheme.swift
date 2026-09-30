import WebUICore

// MARK: - ThemeMode

/// The mode a theme renders in.
///
/// `.automatic` follows the system preference through a `prefers-color-scheme` media
/// pass rather than being a third palette — a theme declares at most two palettes and
/// `.automatic` decides which one the browser starts with.
///
/// Renamed from `ColorScheme` (2026-09, breaking per d15). Consumers name their own
/// scheme type `ColorScheme` in practice — arc's 27-scheme enum is called exactly that —
/// and the collision forced consumer code to avoid ever *naming* this type, relying on
/// inference (`WebUITheme(scheme: .dark)`). `ThemeMode` frees the name `ColorScheme` for
/// the thing every app actually calls that.
public enum ThemeMode: String, Sendable, Equatable, CaseIterable {
	case automatic
	case light
	case dark

	/// the css `color-scheme` value to emit, or `nil` for `.automatic` (nothing is
	/// declared and the browser follows the system).
	public var cssValue: String? {
		switch self {
		case .automatic: return nil
		case .light: return "light"
		case .dark: return "dark"
		}
	}
}

// MARK: - ThemePalette

/// One mode's worth of theme values: overrides for the framework's `DesignToken`
/// vocabulary, plus custom properties the app invents for itself.
///
/// Both live here rather than on the theme because they are *per mode* — an app's
/// `--chat-bubble-bg` differs between light and dark exactly as `colorBg` does.
public struct ThemePalette: Sendable, Equatable {
	/// overrides for the framework's `:root` tokens (the `DesignToken` vocabulary
	/// generated from `design-system.css`). a value restyles every component that
	/// references that token.
	public var tokens: [DesignToken: String]
	/// overrides for custom properties the app invented (arbitrary `--name` keys).
	public var customTokens: [String: String]

	public init(tokens: [DesignToken: String] = [:], customTokens: [String: String] = [:]) {
		self.tokens = tokens
		self.customTokens = customTokens
	}

	/// no overrides. a palette that is `.empty` contributes no css.
	public static let empty = ThemePalette()

	public var isEmpty: Bool {
		tokens.isEmpty && customTokens.isEmpty
	}

	/// Layers `overrides` on top of `self`: the override wins, per key.
	public func overlaying(_ overrides: ThemePalette) -> ThemePalette {
		var mergedTokens = tokens
		for (key, value) in overrides.tokens { mergedTokens[key] = value }
		var mergedCustom = customTokens
		for (key, value) in overrides.customTokens { mergedCustom[key] = value }
		return ThemePalette(tokens: mergedTokens, customTokens: mergedCustom)
	}

	/// The declarations this palette contributes.
	///
	/// Sorted by css name so the emitted sheet is deterministic — an unsorted
	/// dictionary iteration is exactly how the same build produces different bytes on
	/// two runs, which defeats content-addressed caching and makes diffs useless.
	func declarations() -> [CSSDeclaration] {
		var out: [CSSDeclaration] = []
		for token in tokens.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
			if let value = tokens[token] {
				out.append(CSSDeclaration("--\(token.rawValue)", value))
			}
		}
		for key in customTokens.keys.sorted() {
			if let value = customTokens[key] {
				out.append(CSSDeclaration(key, value))
			}
		}
		return out
	}
}

// MARK: - ThemeScope

/// Where a theme's css lands.
///
/// `.root` is a single-theme page: the palette on `:root`, a media pass for the dark
/// override. `.attribute` is one theme inside a catalog: the same declarations, scoped to
/// `:root[data-scheme="<id>"][data-theme="…"]` so a page can ship every scheme at once and
/// let the client switch without a round trip.
///
/// `data-theme` keeps its **existing** meaning of *mode* (`light` / `dark` / `system`) —
/// the engine already flips exactly that attribute — and `data-scheme` names the theme. The
/// two axes are orthogonal, which is what lets one stylesheet carry 27 schemes × 2 modes.
public enum ThemeScope: Sendable, Equatable {
	case root
	case attribute(id: String)
}

// MARK: - WebUITheme

/// A theme: up to two palettes, a mode, and app-specific rules that layer on top of the
/// shipped design-system sheet.
///
/// Rendering appends the theme's css after the base sheet, so a later `:root`
/// declaration wins the cascade for every token the components resolve through `var(--…)`.
///
/// There is one theme type, not two. Identity (`themeID`/`themeLabel`/swatch) belongs to
/// the *provider* — see ``WebUIThemeProvider`` and ``ThemeCatalog`` — so a named theme is
/// still a `WebUITheme`, and an unnamed one is too.
public struct WebUITheme: Sendable, Equatable {
	/// What the theme looks like: the palette on `:root`.
	///
	/// Named for its role rather than its mode on purpose. A one-palette theme is the
	/// common case, and it has no "light" or "dark" identity — a dark-only theme puts its
	/// colours here and declares `defaultMode: .dark`. Calling this `light` would invite
	/// exactly the misreading that a dark theme's own colours are the light ones.
	public var palette: ThemePalette
	/// The override applied inside the `prefers-color-scheme: dark` pass. Empty means the
	/// theme renders the same in both modes.
	public var dark: ThemePalette
	/// the mode the document declares up front. `.automatic` (the default) emits nothing
	/// and lets the browser decide; the engine may still override it per client.
	public var defaultMode: ThemeMode
	/// app-specific component css, appended after all token overrides so it can both
	/// reference `var(--…)` tokens and set scoped ones.
	public var rules: [CSSRule]

	/// the full form: a base palette plus an optional dark override.
	public init(
		palette: ThemePalette = .empty,
		dark: ThemePalette = .empty,
		defaultMode: ThemeMode = .automatic,
		rules: [CSSRule] = []
	) {
		self.palette = palette
		self.dark = dark
		self.defaultMode = defaultMode
		self.rules = rules
	}

	/// the one-palette form, which is the common case: `tokens`/`customTokens` become
	/// the base palette and the theme renders the same in both modes unless `dark` is
	/// also supplied.
	public init(
		tokens: [DesignToken: String] = [:],
		customTokens: [String: String] = [:],
		dark: ThemePalette = .empty,
		defaultMode: ThemeMode = .automatic,
		rules: [CSSRule] = []
	) {
		self.init(
			palette: ThemePalette(tokens: tokens, customTokens: customTokens),
			dark: dark,
			defaultMode: defaultMode,
			rules: rules
		)
	}

	/// The default theme: no overrides, no mode, no rules. A document rendered with
	/// `.standard` is byte-identical to one rendered without a theme.
	public static let standard = WebUITheme()

	/// True when this theme contributes no css at all.
	public var isEmpty: Bool {
		palette.isEmpty && dark.isEmpty && rules.isEmpty
	}

	/// Layers `overrides` on top of `self`: each palette merges (the override wins), a
	/// non-`.automatic` mode replaces, and rules append.
	///
	/// Used to apply a dynamic accent or a user preference over a static `@Theme`-declared
	/// theme.
	public func overlaying(_ overrides: WebUITheme) -> WebUITheme {
		WebUITheme(
			palette: palette.overlaying(overrides.palette),
			dark: dark.overlaying(overrides.dark),
			defaultMode: overrides.defaultMode == .automatic ? defaultMode : overrides.defaultMode,
			rules: rules + overrides.rules
		)
	}

	/// The css this theme contributes.
	///
	/// Empty when the theme is `.standard`, so an unthemed document stays byte-identical.
	/// Declarations are sorted by css name, so the output is byte-stable across runs — which
	/// is what makes it safe to serve from a content-addressed url.
	public func stylesheet(scope: ThemeScope = .root) -> String {
		var parts: [String] = []

		switch scope {
		case .root:
			var rootDeclarations: [CSSDeclaration] = []
			// `color-scheme` tells the browser which way the page faces, so form controls,
			// scrollbars and the canvas follow it. `.automatic` declares nothing.
			if let schemeValue = defaultMode.cssValue {
				rootDeclarations.append(CSSDeclaration("color-scheme", schemeValue))
			}
			rootDeclarations.append(contentsOf: palette.declarations())
			if !rootDeclarations.isEmpty {
				parts.append(CSSStylesheet([CSSRule(":root", rootDeclarations)]).render())
			}
			if !dark.isEmpty {
				parts.append(CSSMediaQuery(
					"prefers-color-scheme: dark",
					rules: [CSSRule(":root", dark.declarations())]
				).render())
			}

		case .attribute(let id):
			let scoped = { (mode: String) in ":root[data-scheme=\"\(id)\"][data-theme=\"\(mode)\"]" }
			// the light and `system` selectors share the base palette: `system` is the
			// "follow the OS" choice, and this block is what the media pass below overrides.
			var base: [CSSDeclaration] = []
			if let schemeValue = defaultMode.cssValue {
				base.append(CSSDeclaration("color-scheme", schemeValue))
			}
			base.append(contentsOf: palette.declarations())
			if !base.isEmpty {
				parts.append(CSSStylesheet([
					CSSRule(scoped("light"), base),
					CSSRule(scoped("system"), base),
				]).render())
			}
			if !dark.isEmpty {
				// a client that explicitly chose dark, and a client on `system` whose OS is
				// dark. both declare `color-scheme: dark` so the browser's own chrome follows.
				let darkDeclarations = [CSSDeclaration("color-scheme", "dark")] + dark.declarations()
				parts.append(CSSStylesheet([CSSRule(scoped("dark"), darkDeclarations)]).render())
				parts.append(CSSMediaQuery(
					"prefers-color-scheme: dark",
					rules: [CSSRule(scoped("system"), darkDeclarations)]
				).render())
			}
		}

		if !rules.isEmpty {
			parts.append(CSSStylesheet(rules).render())
		}
		return parts.joined(separator: "\n\n")
	}
}

// MARK: - WebUIThemeProvider

/// A type that provides a `WebUITheme`.
///
/// `@Theme` generates the conformance from the type's `static let` members; hand-written
/// conformers can add conformance directly, and the default yields `.standard` so an
/// unthemed type conforms for free.
public protocol WebUIThemeProvider {
	/// stable identity for a named theme.
	///
	/// the engine persists this string, a picker keys on it, and a serialized catalog
	/// uses it as the lookup key — so it must be stable across builds and unique within
	/// a catalog. defaults to the type's own name, which is unique by construction.
	///
	/// Declare it explicitly only when the type name is a poor identifier (a nested or
	/// generated type, or a name chosen before the theme was).
	static var themeID: String { get }
	/// what a picker shows next to the swatch. defaults to `themeID`.
	static var themeLabel: String { get }
	/// the picker's swatch: an accent first, then up to two companion dots — the same
	/// shape a colour-scheme grid uses. empty means "no swatch, show the label only".
	static var themeSwatch: [String] { get }
	/// the theme this provider contributes.
	static var theme: WebUITheme { get }
}

extension WebUIThemeProvider {
	/// the identity default: the type's own name. unique by construction, and stable as
	/// long as the type is not renamed.
	public static var themeID: String { String(describing: Self.self) }
	public static var themeLabel: String { themeID }
	public static var themeSwatch: [String] { [] }
	/// the lifeline default: an empty theme. a type that conforms without providing its
	/// own `theme` renders exactly like the unthemed document.
	public static var theme: WebUITheme { .standard }
}

// MARK: - ThemeCatalog

/// An ordered set of themes a page offers.
///
/// The catalog is the *data* a picker renders from — id, label and swatch per entry — so
/// no consumer hand-writes the list, and `ThemeCatalogTests` can assert its integrity
/// (unique ids, a default that is actually a member) instead of trusting it.
///
/// `all` is ordered: it is the order a picker shows, and the first entry is what a page
/// falls back to when nothing is persisted.
public protocol ThemeCatalog {
	/// every theme this catalog offers, in picker order.
	static var all: [any WebUIThemeProvider.Type] { get }
	/// the theme used when no choice is stored. must be a member of ``all``.
	static var defaultTheme: any WebUIThemeProvider.Type { get }
}

/// One catalog entry as **data**: what a picker shows and what the engine ships.
///
/// The catalog is expressed as providers (types), but everything downstream wants values —
/// a picker wants (id, label, swatch), the engine wants to serialize a list, and a page
/// wants the resolved `WebUITheme`. Metatypes are the wrong currency for all three: a
/// *stored* `static let` of `[any WebUIThemeProvider.Type]` is not `Sendable`, which Swift 6
/// rejects as global mutable state. Converting once, here, keeps conformers writing the
/// ergonomic `[Foo.self, Bar.self]` list while everything else handles `Sendable` data.
public struct ThemeEntry: Sendable, Equatable {
	/// the stable id a client persists and `theme(for:)` resolves.
	public let id: String
	/// what a picker shows.
	public let label: String
	/// the swatch: an accent first, then up to two companion dots. empty = label only.
	public let swatch: [String]
	/// the resolved theme.
	public let theme: WebUITheme

	public init(id: String, label: String, swatch: [String] = [], theme: WebUITheme) {
		self.id = id
		self.label = label
		self.swatch = swatch
		self.theme = theme
	}

	/// the entry for a provider.
	public init(_ provider: any WebUIThemeProvider.Type) {
		self.init(
			id: provider.themeID,
			label: provider.themeLabel,
			swatch: provider.themeSwatch,
			theme: provider.theme
		)
	}
}

extension ThemeCatalog {
	/// The catalog as `Sendable` data, in picker order.
	///
	/// Conformers expose `all` as a **computed** property (`static var all: [...] { [...] }`)
	/// — a stored one trips Swift 6's global-mutable-state check, because an existential
	/// metatype is not `Sendable`. Computing it costs an array literal per access and keeps
	/// the declaration ergonomic.
	public static var entries: [ThemeEntry] {
		all.map(ThemeEntry.init)
	}

	/// The whole catalog as one scoped stylesheet, in catalog order.
	///
	/// This is the artefact a host serves (content-addressed — it only changes when a theme
	/// does) so a page ships every scheme once and switching costs no round trip and no
	/// re-render.
	public static func stylesheet() -> String {
		entries
			.map { $0.theme.stylesheet(scope: .attribute(id: $0.id)) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")
	}

	/// The theme for a stored id, or the default's.
	///
	/// The engine resolves a persisted choice through this, so an id from a previous build
	/// — a scheme since renamed or deleted — degrades to the default rather than to a
	/// broken page.
	public static func theme(for id: String) -> WebUITheme {
		all.first { $0.themeID == id }?.theme ?? defaultTheme.theme
	}
}