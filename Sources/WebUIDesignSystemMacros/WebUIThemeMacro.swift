import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - WebUIThemeMacro

/// the `@Theme` attached macro: collects a struct's `static let` members into a
/// `WebUITheme`, emits the `WebUIThemeProvider` conformance, and synthesizes the
/// five-axis `DesignTheme` conformance so the typed theme path stays declarative.
///
/// member contract (documented on the `@Theme` declaration):
///
/// - reserved names map to the axes of `WebUITheme`/`DesignTheme`:
///   - `base`        — a `WebUIThemeProvider` type to start from; overrides layer on top;
///   - `palette`     — a `ThemePalette` for the base palette (escapes the flat form);
///   - `dark`        — a `ThemePalette` for the dark palette;
///   - `defaultMode` — a `ThemeMode`;
///   - `rules`       — `[CSSRule]`, appended after the token overrides;
///   - `customTokens`— `[String: String]`, app-invented custom properties (base palette);
///   - `aliases`     — `[TokenAlias]`, the app's own property names declared against the
///     framework's tokens (emitted as indirections, so they follow the token per mode).
/// - every other `static let <name>` is a light-palette token override — the generated
///   code references `.<name>` in a `[DesignToken: String]` literal, so the token name is
///   validated by the compiler against the generated `DesignToken` enum (a typo is a
///   missing-enum-case error at the expansion site).
///
/// the synthesized `DesignTheme` conformance partitions the flat token members by name
/// (see ``themeAxis(forMember:)``): `space*`/`spacing*` → spacing, `radius*` → radii, the
/// font/line/letter/fs/text families → typography, `transition*`/`ease*` → motion, and
/// everything else → palette. a struct that names one of the four `DesignTheme` axes as a
/// member (`static let spacing: TokenOverrides = …`) is diagnosed: the axes are
/// *synthesized* from flat members, so a hand-typed axis is a pattern the macro does not
/// mix — write a hand-rolled `DesignTheme` conformance for that shape.
///
/// declaring both `light` and flat token members is ambiguous and is diagnosed rather
/// than silently resolved.
public struct WebUIThemeMacro: ExtensionMacro {

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Theme can only be applied to a struct")
        }

        let typeName = type.trimmedDescription

        var tokenMembers: [String] = []
        var hasCustomTokens = false
        var hasPalette = false
        var hasDark = false
        var hasDefaultMode = false
        var hasRules = false
        var hasAliases = false
        var hasBase = false
        var hasTypedAxis = false

        // `base:` is a macro argument (a type), not a member — parse it off the attribute.
        var baseType: String?
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments where argument.label?.text == "base" {
                let text = argument.expression.trimmedDescription
                let bare = text.hasSuffix(".self") ? String(text.dropLast(5)) : text
                if bare == typeName || bare == "Self" {
                    throw MacroExpansionErrorMessage(
                        "@Theme(base:) on '\(typeName)' names itself — a theme cannot extend itself"
                    )
                }
                baseType = bare
            }
        }

        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = variable.modifiers.contains { $0.name.text == "static" }
            let isLet = variable.bindingSpecifier.text == "let"
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                if !isStatic || !isLet {
                    throw MacroExpansionErrorMessage("@Theme member '\(name)' must be a 'static let' declaration")
                }
                switch name {
                case "base": hasBase = true
                case "palette": hasPalette = true
                case "dark": hasDark = true
                case "defaultMode": hasDefaultMode = true
                case "rules": hasRules = true
                case "aliases": hasAliases = true
                case "customTokens": hasCustomTokens = true
                // the four DesignTheme axes are synthesized from flat members, so a
                // hand-typed one is a pattern the macro does not mix — diagnose it rather
                // than read it as a token name and emit a message that points nowhere.
                case "spacing", "radii", "typography", "motion": hasTypedAxis = true
                // identity members. satisfied by the struct's own declaration (a `static let`
                // meets a `{ get }` requirement), so there is nothing to emit — but they MUST
                // be reserved here or they are read as `DesignToken` names and fail to compile
                // with a message about a missing enum case, which points nowhere useful.
                case "themeID", "themeLabel", "themeSwatch": break
                default: tokenMembers.append(name)
                }
            }
        }

        // a `base:` argument and a `static let base` would both claim the axis.
        if hasBase, baseType != nil {
            throw MacroExpansionErrorMessage(
                "@Theme on '\(typeName)' declares 'base' twice — pass it as `@Theme(base:)` or as a member, not both"
            )
        }
        if hasPalette, !tokenMembers.isEmpty {
            throw MacroExpansionErrorMessage(
                "@Theme on '\(typeName)' declares a 'palette' AND flat token members — "
                + "use one form: flat members define the light palette, so a 'palette' member makes them ambiguous"
            )
        }
        if hasPalette, hasCustomTokens {
            throw MacroExpansionErrorMessage(
                "@Theme on '\(typeName)' declares both 'palette' and 'customTokens' — "
                + "custom tokens belong inside the 'light' palette"
            )
        }
        if hasTypedAxis {
            throw MacroExpansionErrorMessage(
                "@Theme on '\(typeName)' declares a typed DesignTheme axis — "
                + "the axes are synthesized from flat token members (space4, radiusLg, ...); "
                + "write a hand-rolled DesignTheme conformance to declare a typed axis"
            )
        }

        let isPublic = structDecl.modifiers.contains { $0.name.text == "public" }
        let access = isPublic ? "public " : ""

        // the light palette: a `light` member wins, else the flat token members (+ customTokens)
        var lightArgs: [String] = []
        if hasPalette {
            lightArgs.append("palette: palette")
        } else if !tokenMembers.isEmpty || hasCustomTokens {
            let entries = tokenMembers.map { ".\($0): \($0)" }.joined(separator: ", ")
            var paletteArgs: [String] = []
            if !tokenMembers.isEmpty { paletteArgs.append("tokens: [\(entries)]") }
            if hasCustomTokens { paletteArgs.append("customTokens: customTokens") }
            lightArgs.append("palette: ThemePalette(\(paletteArgs.joined(separator: ", ")))")
        }

        var themeArgs = lightArgs
        if hasDark { themeArgs.append("dark: dark") }
        if hasDefaultMode { themeArgs.append("defaultMode: defaultMode") }
        if hasRules { themeArgs.append("rules: rules") }
        if hasAliases { themeArgs.append("aliases: aliases") }

        let overrides = themeArgs.isEmpty
            ? "WebUITheme()"
            : "WebUITheme(\n\t\t\t\(themeArgs.joined(separator: ",\n\t\t\t"))\n\t\t)"

        // with a base, layer the overrides on top; without one, the theme is the overrides.
        let body: String
        if let baseType {
            body = "\(baseType).theme.overlaying(\(overrides))"
        } else {
            body = overrides
        }

        let extensionDecl: DeclSyntax =
            """
            extension \(raw: typeName): WebUIThemeProvider {
            \t\(raw: access)static var theme: WebUITheme {
            \t\t\(raw: body)
            \t}
            }
            """

        guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Theme could not synthesize the theme conformance")
        }

        // ── DesignTheme synthesis ──────────────────────────────────────────────
        // partition the flat token members into the five axes by name.
        var paletteMembers: [String] = []
        var spacingMembers: [String] = []
        var radiiMembers: [String] = []
        var typographyMembers: [String] = []
        var motionMembers: [String] = []
        for name in tokenMembers {
            switch themeAxis(forMember: name) {
            case .palette: paletteMembers.append(name)
            case .spacing: spacingMembers.append(name)
            case .radii: radiiMembers.append(name)
            case .typography: typographyMembers.append(name)
            case .motion: motionMembers.append(name)
            }
        }

        let paletteExpr: String
        if hasPalette {
            // the struct's own `static let palette` satisfies the requirement
            // directly; re-declaring it here would be a conflicting member.
            paletteExpr = "palette"
        } else {
            let entries = paletteMembers.map { ".\($0): \($0)" }.joined(separator: ", ")
            var args: [String] = []
            if !paletteMembers.isEmpty { args.append("tokens: [\(entries)]") }
            if hasCustomTokens { args.append("customTokens: customTokens") }
            paletteExpr = args.isEmpty ? "ThemePalette()" : "ThemePalette(\(args.joined(separator: ", ")))"
        }

        func axisExpr(_ names: [String]) -> String {
            guard !names.isEmpty else { return "TokenOverrides()" }
            let entries = names.map { ".\($0): \($0)" }.joined(separator: ", ")
            return "TokenOverrides([\(entries)])"
        }

        var axes: [(String, String, String)] = [
            ("palette", "ThemePalette", paletteExpr),
            ("spacing", "TokenOverrides", axisExpr(spacingMembers)),
            ("radii", "TokenOverrides", axisExpr(radiiMembers)),
            ("typography", "TokenOverrides", axisExpr(typographyMembers)),
            ("motion", "TokenOverrides", axisExpr(motionMembers)),
        ]
        if hasPalette { axes.removeFirst() }

        var designLines: [String] = ["extension \(typeName): DesignTheme {"]
        for (name, type, expr) in axes {
            designLines.append("\t\(access)static var \(name): \(type) {")
            designLines.append("\t\t\(expr)")
            designLines.append("\t}")
        }
        designLines.append("}")
        let designText = designLines.joined(separator: "\n")

        let designDecl: DeclSyntax = "\(raw: designText)"
        guard let designParsed = designDecl.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Theme could not synthesize the DesignTheme conformance")
        }

        return [parsed, designParsed]
    }
}

// MARK: - axis partition

/// the five axes of ``DesignTheme``.
private enum ThemeAxis {
    case palette, spacing, radii, typography, motion
}

/// the axis a flat `@Theme` member belongs to, by its camelCase name.
///
/// the partition is a *name contract* shared with the `DesignTheme` docs:
/// `space*`/`spacing*` → spacing, `radius*` → radii, the font/line/letter/fs/text
/// families → typography, `transition*`/`ease*` → motion, and everything else →
/// palette. it must stay prefix-stable: a token whose name starts with a family
/// prefix is always read into that axis regardless of future renames, so the
/// synthesized conformance agrees with how a hand-written one would group the
/// generated `DesignToken` enum.
private func themeAxis(forMember name: String) -> ThemeAxis {
    if name.hasPrefix("space") || name.hasPrefix("spacing") { return .spacing }
    if name.hasPrefix("radius") { return .radii }
    if name.hasPrefix("font") || name.hasPrefix("fs")
        || name.hasPrefix("lineHeight") || name.hasPrefix("letterSpacing")
        || name.hasPrefix("text") { return .typography }
    if name.hasPrefix("transition") || name.hasPrefix("ease") { return .motion }
    return .palette
}
