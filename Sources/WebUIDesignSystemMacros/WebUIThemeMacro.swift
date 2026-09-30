import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - WebUIThemeMacro

/// the `@Theme` attached macro: collects a struct's `static let` members into a
/// `WebUITheme` and emits the `WebUIThemeProvider` conformance.
///
/// member contract (documented on the `@Theme` declaration):
///
/// - reserved names map to the axes of `WebUITheme`:
///   - `base`        — a `WebUIThemeProvider` type to start from; overrides layer on top;
///   - `palette`     — a `ThemePalette` for the base palette (escapes the flat form);
///   - `dark`        — a `ThemePalette` for the dark palette;
///   - `defaultMode` — a `ThemeMode`;
///   - `rules`       — `[CSSRule]`, appended after the token overrides;
///   - `customTokens`— `[String: String]`, app-invented custom properties (light palette).
/// - every other `static let <name>` is a light-palette token override — the generated
///   code references `.<name>` in a `[DesignToken: String]` literal, so the token name is
///   validated by the compiler against the generated `DesignToken` enum (a typo is a
///   missing-enum-case error at the expansion site).
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
        var hasBase = false

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
                case "customTokens": hasCustomTokens = true
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
        return [parsed]
    }
}