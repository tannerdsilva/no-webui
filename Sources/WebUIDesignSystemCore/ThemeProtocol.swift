import WebUICore

// MARK: - TokenOverrides

/// one axis of a design theme's token set: overrides for the framework's
/// `DesignToken` vocabulary.
///
/// the four non-palette axes — spacing, radii, typography and motion — share
/// this type; the axis is *context*, declared by which requirement of
/// ``DesignTheme`` carries the value. that the override is a
/// `[DesignToken: String]` at heart is what makes
/// `.overriding([.colorPrimary500: "…"])` a single dictionary literal: the
/// compiler checks every key against the generated `DesignToken` enum, so a
/// mistyped token name is a missing-enum-case error.
public struct TokenOverrides: Sendable, Equatable {
	/// the overrides: a `DesignToken` maps to its css value.
	public var tokens: [DesignToken: String] = [:]

	public init() {}

	/// the overrides, e.g. `TokenOverrides([.space4: "1.25rem"])`.
	public init(_ tokens: [DesignToken: String]) {
		self.tokens = tokens
	}

	/// no overrides. contributes no css.
	public static let empty = TokenOverrides()

	public var isEmpty: Bool { tokens.isEmpty }

	/// layers `overrides` on top of `self`: the override wins, per token.
	public func overlaying(_ overrides: TokenOverrides) -> TokenOverrides {
		var merged = tokens
		for (key, value) in overrides.tokens { merged[key] = value }
		return TokenOverrides(merged)
	}

	/// the declarations this axis contributes, sorted by css name so the
	/// rendered sheet is deterministic across runs.
	func declarations() -> [CSSDeclaration] {
		tokens.keys.sorted(by: { $0.rawValue < $1.rawValue }).compactMap { token in
			guard let value = tokens[token] else { return nil }
			return CSSDeclaration("--\(token.rawValue)", value)
		}
	}
}

extension TokenOverrides: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (DesignToken, String)...) {
		self.init(Dictionary(uniqueKeysWithValues: elements))
	}
}

// MARK: - DesignTheme

/// a complete design-token set. conform to retokenize the framework; omit
/// nothing (the compiler enforces completeness) and override individually
/// where only a few values differ.
///
/// a theme is five axes:
///   - ``palette``   — the colour surface: the `color-*`, `scrollbar-*`,
///     `shadow-*`, `ring-*`, `z-*` and `border-*` tokens, plus the custom
///     properties an app invents for itself;
///   - ``spacing``   — the `space-*` / `spacing-*` tokens;
///   - ``radii``     — the `radius-*` tokens;
///   - ``typography``— the `font-*`, `font-size-*`, `font-weight-*`,
///     `line-height-*`, `letter-spacing-*`, `fs-hero` and `text-*` tokens;
///   - ``motion``    — the `transition-*` and `ease-*` tokens.
///
/// every requirement is mandatory, so a conformer that omits an axis does not
/// compile: the completeness is enforced by the compiler, not promised. the
/// partition is a *contract*, not a render-time distinction — all five axes
/// fold back into the single `:root` token set (``resolvedPalette``) that the
/// theme renderer understands, which is also why a conformer may not repeat a
/// token on two axes (the later axis wins, deterministically).
///
/// a host that wants a *different* complete theme writes a conformer (or lets
/// `@Theme` synthesize one); a host that only wants to move a few tokens
/// derives: `.overriding([.colorPrimary500: "…"])` returns a
/// ``DerivedTheme`` over the theme, with the untouched axes following the
/// base. complexity available, not required.
public protocol DesignTheme: Sendable {
	static var palette: ThemePalette { get }
	static var spacing: TokenOverrides { get }
	static var radii: TokenOverrides { get }
	static var typography: TokenOverrides { get }
	static var motion: TokenOverrides { get }
}

// MARK: - DefaultDesignTheme

/// the theme that changes nothing: every axis empty.
///
/// renders exactly like the unthemed document — the bytes a host that never
/// touches theming has always received.
public enum DefaultDesignTheme: DesignTheme {
	public static var palette: ThemePalette { .empty }
	public static var spacing: TokenOverrides { .empty }
	public static var radii: TokenOverrides { .empty }
	public static var typography: TokenOverrides { .empty }
	public static var motion: TokenOverrides { .empty }
}

// MARK: - DerivedTheme

/// one axis overridden, the rest inherited.
///
/// the runtime derivation: a dynamic accent or a user preference layered over a
/// static ``DesignTheme``. `Base` supplies every axis; the override moves
/// individual tokens on top of `Base`'s whole resolved token set, and `mode`
/// chooses the `color-scheme` the rendered theme declares.
///
/// the value you render is ``webUITheme()``. ``DerivedTheme`` is itself a
/// ``DesignTheme`` — inheriting every axis of `Base` — so a derived theme can
/// serve as the base of a further derivation, and the type can be passed
/// wherever a theme type is expected.
public struct DerivedTheme<Base: DesignTheme>: DesignTheme {
	/// the mode the rendered theme declares. `.automatic` declares nothing and
	/// lets the browser follow the system.
	public let mode: ThemeMode
	/// the palette-axis override: the individual tokens to move.
	public let overrides: TokenOverrides

	public init(mode: ThemeMode, overrides: TokenOverrides) {
		self.mode = mode
		self.overrides = overrides
	}

	/// the type-level theme: every axis inherited from the base. the override is
	/// a property of the *value* (``webUITheme()``), applied at render time.
	public static var palette: ThemePalette { Base.palette }
	public static var spacing: TokenOverrides { Base.spacing }
	public static var radii: TokenOverrides { Base.radii }
	public static var typography: TokenOverrides { Base.typography }
	public static var motion: TokenOverrides { Base.motion }

	/// base's whole token set with the override's tokens on top, at `mode`.
	///
	/// the rendered output is the `:root` declarations for every overridden
	/// token — later in source order than the base sheet, so each one wins the
	/// cascade — plus a `color-scheme` when `mode` is `.light` or `.dark`. an
	/// empty override on `.automatic` renders nothing, byte-identical to the
	/// unthemed document.
	public func webUITheme() -> WebUITheme {
		WebUITheme(
			palette: Base.resolvedPalette.overlaying(ThemePalette(tokens: overrides.tokens)),
			defaultMode: mode
		)
	}
}

// MARK: - DesignTheme extension

extension DesignTheme {
	/// all five axes, folded into the one `:root` token set the renderer uses.
	///
	/// a token repeated across axes resolves to the later axis (motion last),
	/// deterministically.
	public static var resolvedPalette: ThemePalette {
		var merged = palette.tokens
		merged.merge(spacing.tokens, uniquingKeysWith: { _, new in new })
		merged.merge(radii.tokens, uniquingKeysWith: { _, new in new })
		merged.merge(typography.tokens, uniquingKeysWith: { _, new in new })
		merged.merge(motion.tokens, uniquingKeysWith: { _, new in new })
		return ThemePalette(tokens: merged, customTokens: palette.customTokens)
	}

	/// this theme, rendered as a `WebUITheme` in the given mode.
	public static func webUITheme(mode: ThemeMode = .automatic) -> WebUITheme {
		WebUITheme(mode: mode, theme: Self.self)
	}

	/// the derived theme that moves individual tokens on this theme's palette.
	///
	/// the untouched axes (spacing, radii, typography, motion) follow the base:
	/// `.overriding([.colorPrimary500: "#6c8cff"])` changes exactly one token.
	public static func overriding(
		_ tokens: [DesignToken: String],
		mode: ThemeMode = .automatic
	) -> DerivedTheme<Self> {
		DerivedTheme(mode: mode, overrides: TokenOverrides(tokens))
	}
}
