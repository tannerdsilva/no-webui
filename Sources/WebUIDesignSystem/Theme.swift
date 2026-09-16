import WebUIDesignSystemCore

// MARK: - @Theme macro

/// turns a struct into a `WebUIThemeProvider` whose `theme` is built from the
/// struct's `static let` members.
///
/// three reserved member names map to the non-token axes of `WebUITheme`:
///   - `static let scheme: ColorScheme` — the page color scheme;
///   - `static let rules: [CSSRule]` — app component css, appended after the
///     token overrides;
///   - `static let customTokens: [String: String]` — overrides for app
///     invented custom properties (`"--chat-bubble-bg": "…"`).
///
/// every other `static let <name> = <value>` is a design-token override: the
/// member name must be a case on the generated `DesignToken` enum
/// (camelCased from the css name — `colorPrimarySolid` → `--color-primary-solid`),
/// and the compiler enforces that at the expansion site, so a mistyped token
/// name is a compile error.
///
/// ```swift
/// @Theme
/// struct NexusDark {
///    static let scheme = ColorScheme.dark
///    static let colorPrimarySolid = "#6c8cff"
///    static let colorBackground = "#101014"
/// }
///
/// WebUIDocument(body: …, theme: NexusDark.theme)   // .standard → byte-identical
/// ```
@attached(extension, conformances: WebUIThemeProvider, names: named(theme))
public macro Theme() = #externalMacro(module: "WebUIDesignSystemMacros", type: "WebUIThemeMacro")
