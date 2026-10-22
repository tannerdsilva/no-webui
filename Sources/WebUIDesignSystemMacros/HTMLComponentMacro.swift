import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - ComponentMacro

/// `@HTMLComponent` is a member macro that replaces the three-initializer +
/// private `Content`-enum ceremony with a single attribute declaration.
///
/// one init is generated per content case; every stored property of the host
/// struct becomes a shared parameter (declaration order and default expressions
/// preserved verbatim); computed properties are skipped.
///
/// ```swift
/// @HTMLComponent(.text("label", unlabeled: true), .builder("views"))
/// struct ArcButton: WebUI.View {
///     var id: String? = nil
///     var body: some View { … }
/// }
/// ```
public struct ComponentMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@HTMLComponent can only be applied to a struct")
        }

        // ── parse the content cases from the attribute arguments ──────────
        let cases = try parseCases(node, in: context)

        // ── scan stored properties ───────────────────────────────────────
        let properties = scanStoredProperties(structDecl, in: context)

        // ── generate members ─────────────────────────────────────────────
        return generateMembers(structDecl, cases: cases, properties: properties)
    }

    // MARK: - parsed representations

    private struct ParsedCase {
        let name: String      // the init parameter label AND the enum case name
        let isBuilder: Bool   // true for .builder, false for .text
        let unlabeled: Bool   // text only: `_ label:` vs `label:`
    }

    private struct ParsedProperty {
        let name: String
        let type: String      // the type annotation text, verbatim
        let `default`: String? // the default expression text, verbatim (without `=`)
    }

    // MARK: - parsing

    /// parse `.text("name", unlabeled: true)` / `.builder("name")` from the
    /// attribute's variadic arguments.
    private static func parseCases(
        _ node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) throws -> [ParsedCase] {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw MacroExpansionErrorMessage("@HTMLComponent requires at least one content case")
        }

        var cases: [ParsedCase] = []
        var seenNames: [String: Bool] = [:]

        for arg in arguments {
            guard let call = arg.expression.as(FunctionCallExprSyntax.self) else {
                context.diagnose(
                    Diagnostic(
                        node: arg.expression,
                        message: MacroExpansionErrorMessage(
                            "expected a content-case factory call (.text(...) or .builder(...))"
                        )
                    )
                )
                continue
            }

            guard let (isBuilder, _) = styleOf(call.calledExpression) else {
                context.diagnose(
                    Diagnostic(
                        node: call.calledExpression,
                        message: MacroExpansionErrorMessage(
                            "expected '.text(...)' or '.builder(...)', got '\(call.calledExpression.trimmedDescription)'"
                        )
                    )
                )
                continue
            }

            // the first positional argument is the case name (a string literal)
            guard let nameExpr = call.arguments.first(where: { $0.label == nil }),
                  let name = stringLiteralValue(nameExpr.expression) else {
                context.diagnose(
                    Diagnostic(
                        node: call,
                        message: MacroExpansionErrorMessage(
                            "content-case factory requires a string-literal name"
                        )
                    )
                )
                continue
            }

            // duplicate name check
            if seenNames[name] != nil {
                context.diagnose(
                    Diagnostic(
                        node: nameExpr.expression,
                        message: MacroExpansionErrorMessage(
                            "content case '\(name)' is declared more than once"
                        )
                    )
                )
                continue
            }
            seenNames[name] = true

            // `unlabeled:` is only valid on `.text`
            var unlabeled = false
            if isBuilder {
                if call.arguments.contains(where: { $0.label?.text == "unlabeled" }) {
                    context.diagnose(
                        Diagnostic(
                            node: call,
                            message: MacroExpansionErrorMessage(
                                "unlabeled: is only valid on .text cases, not .builder"
                            )
                        )
                    )
                }
            } else {
                if let unlabeledArg = call.arguments.first(where: { $0.label?.text == "unlabeled" }) {
                    unlabeled = boolLiteralValue(unlabeledArg.expression)
                }
            }

            cases.append(ParsedCase(name: name, isBuilder: isBuilder, unlabeled: unlabeled))
        }

        guard !cases.isEmpty else {
            throw MacroExpansionErrorMessage("@HTMLComponent requires at least one content case")
        }

        let builders = cases.filter { $0.isBuilder }
        guard builders.count <= 1 else {
            throw MacroExpansionErrorMessage(
                "@HTMLComponent declares \(builders.count) builder cases; at most one is allowed"
            )
        }

        return cases
    }

    /// determine whether a called expression is `.text` or `.builder`.
    private static func styleOf(_ called: ExprSyntax) -> (isBuilder: Bool, name: String)? {
        if let memberAccess = called.as(MemberAccessExprSyntax.self) {
            let name = memberAccess.declName.baseName.text
            if name == "text" { return (false, name) }
            if name == "builder" { return (true, name) }
            return nil
        }
        if let declRef = called.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            if name == "text" { return (false, name) }
            if name == "builder" { return (true, name) }
            return nil
        }
        return nil
    }

    /// extract the text content of a string literal expression.
    private static func stringLiteralValue(_ expr: ExprSyntax) -> String? {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
        return literal.segments.compactMap { segment in
            if case .stringSegment(let seg) = segment {
                return seg.content.text
            }
            return nil
        }.joined()
    }

    /// extract a boolean literal value (true/false).
    private static func boolLiteralValue(_ expr: ExprSyntax) -> Bool {
        if let boolLit = expr.as(BooleanLiteralExprSyntax.self) {
            return boolLit.literal.text == "true"
        }
        return false
    }

    // MARK: - property scanning

    /// scan the struct's stored properties, in declaration order.
    /// computed properties (those with an accessor block) are skipped.
    private static func scanStoredProperties(
        _ structDecl: StructDeclSyntax,
        in context: some MacroExpansionContext
    ) -> [ParsedProperty] {
        var properties: [ParsedProperty] = []
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                // skip computed properties (those with an accessor block)
                if binding.accessorBlock != nil { continue }
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                guard let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription else {
                    context.diagnose(
                        Diagnostic(
                            node: binding,
                            message: MacroExpansionErrorMessage(
                                "stored property '\(name)' has no type annotation — @HTMLComponent requires an explicit type"
                            )
                        )
                    )
                    continue
                }
                let defaultExpr = binding.initializer?.value.trimmedDescription
                properties.append(ParsedProperty(name: name, type: typeAnnotation, default: defaultExpr))
            }
        }
        return properties
    }

    // MARK: - generation

    private static func generateMembers(
        _ structDecl: StructDeclSyntax,
        cases: [ParsedCase],
        properties: [ParsedProperty]
    ) -> [DeclSyntax] {
        let isPublic = structDecl.modifiers.contains { $0.name.text == "public" }
        let access = isPublic ? "public " : ""

        var members: [DeclSyntax] = []

        // the private Content enum, one case per content case
        let enumCases = cases.map { case_ in
            let associatedType = case_.isBuilder ? "[any WebUI.View]" : "String"
            return "    case \(case_.name)(\(associatedType))"
        }.joined(separator: "\n")
        members.append(DeclSyntax("""
        private enum Content {
        \(raw: enumCases)
        }
        """))

        // the private content storage (no blank line between the enum and storage)
        members.append(DeclSyntax("private let content: Content"))

        // one init per content case, in canonical order:
        // unlabeled text cases first, then labeled text cases, then the builder.
        let ordered = cases.sorted {
            if $0.isBuilder != $1.isBuilder { return !$0.isBuilder }
            if $0.unlabeled != $1.unlabeled { return $0.unlabeled }
            return false
        }
        for case_ in ordered {
            if case_.isBuilder {
                members.append(generateBuilderInit(case_: case_, properties: properties, access: access))
            } else {
                members.append(generateTextInit(case_: case_, properties: properties, access: access))
            }
        }

        return members
    }

    /// generate the init for a single `.text` content case.
    private static func generateTextInit(
        case_: ParsedCase,
        properties: [ParsedProperty],
        access: String
    ) -> DeclSyntax {
        let externalLabel = case_.unlabeled ? "_" : ""
        let param = externalLabel.isEmpty
            ? "\(case_.name): String"
            : "_ \(case_.name): String"

        var params = [param]
        for prop in properties {
            if let default_ = prop.default {
                params.append("\(prop.name): \(prop.type) = \(default_)")
            } else {
                params.append("\(prop.name): \(prop.type)")
            }
        }

        let paramText = params.joined(separator: ", ")
        let assignments = properties.map { "    self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        let body = assignments.isEmpty
            ? "    self.content = .\(case_.name)(\(case_.name))"
            : "\(assignments)\n    self.content = .\(case_.name)(\(case_.name))"

        return DeclSyntax("""
        \(raw: access)init(\(raw: paramText)) {
        \(raw: body)
        }
        """)
    }

    /// generate the init for the single `.builder` content case.
    private static func generateBuilderInit(
        case_: ParsedCase,
        properties: [ParsedProperty],
        access: String
    ) -> DeclSyntax {
        var params: [String] = []
        for prop in properties {
            if let default_ = prop.default {
                params.append("\(prop.name): \(prop.type) = \(default_)")
            } else {
                params.append("\(prop.name): \(prop.type)")
            }
        }
        params.append("@ViewBuilder \(case_.name): () -> [any WebUI.View]")

        let paramText = params.joined(separator: ", ")
        let assignments = properties.map { "    self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        let body = assignments.isEmpty
            ? "    self.content = .\(case_.name)(\(case_.name)())"
            : "\(assignments)\n    self.content = .\(case_.name)(\(case_.name)())"

        return DeclSyntax("""
        \(raw: access)init(\(raw: paramText)) {
        \(raw: body)
        }
        """)
    }
}
