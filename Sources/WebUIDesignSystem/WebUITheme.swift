import WebUI

// MARK: - ColorScheme

/// the page's color-scheme preference. `.automatic` follows the system; a
/// fixed scheme declares `color-scheme:` on `:root` so the theme's token
/// overrides are the active palette regardless of the system setting.
/// `.dark` is the dark-first choice: the base stylesheet's `@media
/// (prefers-color-scheme: dark)` block loads in dark, and the theme's own
/// overrides win the cascade in both schemes.
public enum ColorScheme: String, Sendable, Equatable {
	case automatic
	case light
	case dark

	/// the css `color-scheme` value to emit, or `nil` for `.automatic` (nothing
	/// is declared and the browser follows the system).
	public var cssValue: String? {
		switch self {
		case .automatic: return nil
		case .light: return "light"
		case .dark: return "dark"
		}
	}
}

// MARK: - WebUITheme

/// a set of design-token overrides, a color scheme, and app-specific rules
/// that layer on top of the shipped design-system sheet. rendering appends
/// the theme's css after the base sheet, so a later `:root` declaration wins
/// the cascade for every token the components resolve through `var(--…)`.
public struct WebUITheme: Sendable, Equatable {
	/// overrides for the framework's `:root` tokens (the `DesignToken`
	/// vocabulary generated from `design-system.css`). a value restyles every
	/// component that references that token.
	public var tokens: [DesignToken: String]
	/// overrides for custom properties invented by the app (arbitrary
	/// `--name` keys). component-scoped variables that are not on `:root`
	/// belong here when they must be theme-level, or in `rules` when they only
	/// affect one rule set.
	public var customTokens: [String: String]
	/// the page color scheme; `.automatic` (the default) emits nothing.
	public var scheme: ColorScheme
	/// app-specific component css, appended after all token overrides so it
	/// can both reference `var(--…)` tokens and set scoped ones.
	public var rules: [CSSRule]

	public init(
		tokens: [DesignToken: String] = [:],
		customTokens: [String: String] = [:],
		scheme: ColorScheme = .automatic,
		rules: [CSSRule] = []
	) {
		self.tokens = tokens
		self.customTokens = customTokens
		self.scheme = scheme
		self.rules = rules
	}

	/// the default theme: no overrides, no scheme, no rules. a document
	/// rendered with `.standard` is byte-identical to one rendered without a
	/// theme.
	public static let standard = WebUITheme()

	/// true when this theme contributes no css at all.
	public var isEmpty: Bool {
		tokens.isEmpty && customTokens.isEmpty && scheme == .automatic && rules.isEmpty
	}

	/// layers `overrides` on top of `self`: token overrides merge (the
	/// override wins), a non-`.automatic` scheme replaces, and rules append.
	/// used to apply a dynamic accent or a user preference over a static
	/// `@Theme`-declared theme.
	public func overlaying(_ overrides: WebUITheme) -> WebUITheme {
		var mergedTokens = tokens
		for (key, value) in overrides.tokens { mergedTokens[key] = value }
		var mergedCustom = customTokens
		for (key, value) in overrides.customTokens { mergedCustom[key] = value }
		let mergedScheme: ColorScheme = overrides.scheme == .automatic ? scheme : overrides.scheme
		return WebUITheme(
			tokens: mergedTokens,
			customTokens: mergedCustom,
			scheme: mergedScheme,
			rules: rules + overrides.rules
		)
	}

	/// the css this theme contributes: a `:root` block (color-scheme, then
	/// token overrides sorted by css name for deterministic output) followed
	/// by the app rules. empty when the theme is `.standard`.
	public func stylesheet() -> String {
		var declarations: [CSSDeclaration] = []
		if let schemeValue = scheme.cssValue {
			declarations.append(CSSDeclaration("color-scheme", schemeValue))
		}
		for token in tokens.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
			if let value = tokens[token] {
				declarations.append(CSSDeclaration("--\(token.rawValue)", value))
			}
		}
		for key in customTokens.keys.sorted() {
			if let value = customTokens[key] {
				declarations.append(CSSDeclaration(key, value))
			}
		}
		var parts: [String] = []
		if !declarations.isEmpty {
			parts.append(CSSStylesheet([CSSRule(":root", declarations)]).render())
		}
		if !rules.isEmpty {
			parts.append(CSSStylesheet(rules).render())
		}
		return parts.joined(separator: "\n\n")
	}
}

// MARK: - WebUIThemeProvider

/// a type that provides a `WebUITheme`. `@Theme` generates the conformance
/// from the type's `static let` members; hand-written conformers can also add
/// conformance directly, and the default yields `.standard` so an unthemed
/// type conforms for free.
public protocol WebUIThemeProvider {
	/// the theme this provider contributes.
	static var theme: WebUITheme { get }
}

extension WebUIThemeProvider {
	/// the lifeline default: an empty theme. a type that conforms without
	/// providing its own `theme` renders exactly like the unthemed document.
	public static var theme: WebUITheme { .standard }
}
