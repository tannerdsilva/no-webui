import WebUIDesignSystemCore

// MARK: - @Theme macro

/// turns a struct into a `WebUIThemeProvider` whose `theme` is built from the
/// struct's `static let` members.
///
/// reserved member names map to the axes of `WebUITheme`:
///   - `static let palette: ThemePalette` — the base palette (escapes the flat form);
///   - `static let dark: ThemePalette` — the `prefers-color-scheme: dark` override;
///   - `static let defaultMode: ThemeMode` — the `color-scheme` the page declares;
///   - `static let rules: [CSSRule]` — app component css, appended after the
///     token overrides;
///   - `static let customTokens: [String: String]` — overrides for app
///     invented custom properties (`"--chat-bubble-bg": "…"`), in the base palette.
///
/// `@Theme(base: SomeTheme.self)` starts from another provider's theme and layers these
/// overrides on top — the shape a 27-scheme app wants, where every scheme after the first
/// overrides a handful of tokens. a theme may not name itself as its base.
///
/// every other `static let <name> = <value>` is a design-token override: the
/// member name must be a case on the generated `DesignToken` enum
/// (camelCased from the css name — `colorPrimarySolid` → `--color-primary-solid`),
/// and the compiler enforces that at the expansion site, so a mistyped token
/// name is a compile error. the same flat members feed the synthesized
/// `DesignTheme` conformance, partitioned by name: `space*`/`spacing*` →
/// spacing, `radius*` → radii, the font/line/letter/fs/text families →
/// typography, `transition*`/`ease*` → motion, everything else → palette —
/// so a `@Theme` struct is a complete five-axis theme without writing axes.
///
/// the four axis names (`spacing`, `radii`, `typography`, `motion`) are
/// reserved: a member of that name is diagnosed, because the axes are
/// synthesized from flat members. write a hand-rolled `DesignTheme`
/// conformance to declare a typed axis.
///
/// ```swift
/// @Theme
/// struct NexusDark {
///    static let defaultMode = ThemeMode.dark
///    static let colorPrimarySolid = "#6c8cff"
///    static let colorBackground = "#101014"
/// }
///
/// WebUIDocument(body: …, theme: NexusDark.theme)   // .standard → byte-identical
/// NexusDark.overriding([.colorPrimary500: "#6c8cff"])   // a DerivedTheme
/// ```
/// - Parameter base: another theme provider to start from. the declared overrides layer
///   on top of it per palette, which is the shape a many-scheme app wants — every scheme
///   after the first overrides a handful of tokens instead of restating a palette. a theme
///   may not name itself.
@attached(extension, conformances: WebUIThemeProvider, DesignTheme, names: named(theme), named(palette), named(spacing), named(radii), named(typography), named(motion))
public macro Theme(base: (any WebUIThemeProvider.Type)? = nil) =
    #externalMacro(module: "WebUIDesignSystemMacros", type: "WebUIThemeMacro")
