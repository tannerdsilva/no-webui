import WebUICore

// MARK: - ThemeReachability

/// Which design tokens a set of themes actually touches.
///
/// This exists to make token pruning *sound* before anyone prunes anything. The naive
/// definition — "the tokens a theme sets" — is wrong in two ways that both fail silently:
///
/// 1. **the escape hatch.** `WebUITheme.rules` is arbitrary css (d10 keeps it deliberately), so
///    a rule can reference a token the palette never sets. Prune on palette keys alone and that
///    token is dropped while the app's own rule still resolves `var(--…)` — a missing colour,
///    in one rule, only in the mode where the rule applies.
/// 2. **aliases name tokens too.** `TokenAlias("--bg", .colorBg)` emits `--bg: var(--color-bg)`,
///    so the target is used even though nothing sets it. An alias whose target is pruned is a
///    dangling `var`.
///
/// So reachability reads the css as well as the palettes. That is the conservative direction:
/// over-reporting costs bytes, under-reporting costs a colour.
public enum ThemeReachability {

	/// Every token these themes touch, across both palettes, their aliases, and any `var(--…)`
	/// named in their rules or in `extraCSS`.
	///
	/// `extraCSS` is the caller's own stylesheet — the component rules an app ships beside its
	/// themes. Pass it or pruning will drop tokens only that css resolves.
	public static func usedTokens(in themes: [WebUITheme], extraCSS: String = "") -> Set<DesignToken> {
		var used: Set<DesignToken> = []
		for theme in themes {
			used.formUnion(usedTokens(in: theme, extraCSS: ""))
		}
		used.formUnion(referencedTokens(in: extraCSS))
		return used
	}

	/// Every token one theme touches.
	public static func usedTokens(in theme: WebUITheme, extraCSS: String = "") -> Set<DesignToken> {
		var used = Set(theme.palette.tokens.keys)
		used.formUnion(theme.dark.tokens.keys)
		// an alias's target is used by definition, whether or not anything sets it.
		used.formUnion(theme.aliases.map(\.token))
		// the escape hatch: rules are css, and css references tokens.
		used.formUnion(referencedTokens(in: theme.rules))
		used.formUnion(referencedTokens(in: extraCSS))
		return used
	}

	/// The tokens named as `var(--name)` in css.
	///
	/// A name that is not a `DesignToken` is ignored rather than reported: custom properties the
	/// app invented (`var(--chat-bubble)`) are not design tokens and must not enter a token set —
	/// including them would make every pruning decision depend on the app's own vocabulary.
	/// The `var(--name, fallback)` form is read as a reference to `name`, which is correct: the
	/// fallback only applies if the token is missing, and pruning it away is exactly what would
	/// make the fallback fire.
	public static func referencedTokens(in rules: [CSSRule]) -> Set<DesignToken> {
		referencedTokens(in: CSSStylesheet(rules).render())
	}

	/// The tokens named as `var(--name)` in a css string.
	public static func referencedTokens(in css: String) -> Set<DesignToken> {
		var found: Set<DesignToken> = []
		var rest = Substring(css)
		let marker = "var(--"
		while let range = rest.range(of: marker) {
			rest = rest[range.upperBound...]
			let name = rest.prefix { $0 != ")" && $0 != "," && $0 != " " && $0 != "\n" && $0 != "\t" }
			if let token = DesignToken(rawValue: String(name)) {
				found.insert(token)
			}
		}
		return found
	}
}

extension ThemeCatalog {
	/// The tokens this catalog touches — what a pruning step must keep.
	public static func usedTokens(extraCSS: String = "") -> Set<DesignToken> {
		ThemeReachability.usedTokens(in: entries.map(\.theme), extraCSS: extraCSS)
	}
}
