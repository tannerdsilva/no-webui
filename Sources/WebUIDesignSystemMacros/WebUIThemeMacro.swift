import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - WebUIThemeMacro

/// the `@Theme` attached macro: collects a struct's `static let` members into
/// a `WebUITheme` and emits the `WebUIThemeProvider` conformance.
///
/// member contract (documented on the `@Theme` declaration):
/// - `scheme`, `rules`, `customTokens` (reserved names) map to the three
///   non-token axes of `WebUITheme`;
/// - every other `static let <name>` is a token override — the generated code
///   references `.<name>` in a `[DesignToken: String]` literal, so the token
///   name is validated by the compiler against the generated `DesignToken`
///   enum (a typo is a missing-enum-case error at the expansion site).
public struct WebUIThemeMacro: ExtensionMacro {

    static let reservedMembers: Set<String> = ["scheme", "rules", "customTokens"]

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

        var tokenMembers: [String] = []
        var hasCustomTokens = false
        var hasScheme = false
        var hasRules = false

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
                case "scheme": hasScheme = true
                case "rules": hasRules = true
                case "customTokens": hasCustomTokens = true
                default: tokenMembers.append(name)
                }
            }
        }

        let isPublic = structDecl.modifiers.contains { $0.name.text == "public" }
        let access = isPublic ? "public " : ""

        var args: [String] = []
        let entries = tokenMembers.map { ".\($0): \($0)" }.joined(separator: ", ")
        args.append("tokens: [\(entries)]")
        if hasCustomTokens { args.append("customTokens: customTokens") }
        if hasScheme { args.append("scheme: scheme") }
        if hasRules { args.append("rules: rules") }
        let argList = args.joined(separator: ",\n\t\t\t")

        let extensionDecl: DeclSyntax =
            """
            extension \(raw: type.trimmedDescription): WebUIThemeProvider {
            \t\(raw: access)static var theme: WebUITheme {
            \t\tWebUITheme(
            \t\t\t\(raw: argList)
            \t\t)
            \t}
            }
            """

        guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Theme could not synthesize the theme conformance")
        }
        return [parsed]
    }
}
