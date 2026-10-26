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

        // ── reject the declarations this macro emits ─────────────────────
        checkReservedMembers(structDecl, in: context)

        // ── names shared between a content case and a stored property ────
        checkCasePropertyCollisions(cases: cases, properties: properties, in: context)

        // ── generate members ─────────────────────────────────────────────
        return generateMembers(structDecl, cases: cases, properties: properties)
    }

    // MARK: - parsed representations

    private struct ParsedCase {
        let name: String      // the init parameter label AND the enum case name
        let isBuilder: Bool   // true for .builder, false for .text
        let unlabeled: Bool   // text only: `_ label:` vs `label:`
        let nameNode: ExprSyntax // the name literal, for diagnostics
    }

    private struct ParsedProperty {
        let name: String
        let type: TypeSyntax   // structural, so a function type can be detected
        let `default`: String? // the default expression text, verbatim (without `=`)

        /// the parameter spelling of the type. a stored closure property is
        /// assigned in the init, so its parameter must be `@escaping` — without
        /// it the generated init does not compile ("assigning non-escaping
        /// parameter … to an '@escaping' closure").
        var parameterType: String {
            let text = type.trimmedDescription
            return Self.isFunctionType(type) ? "@escaping \(text)" : text
        }

        /// whether the type is a function type, looking through attributes
        /// (`@Sendable () -> Void` is an attributed function type).
        private static func isFunctionType(_ type: TypeSyntax) -> Bool {
            if type.is(FunctionTypeSyntax.self) { return true }
            if let attributed = type.as(AttributedTypeSyntax.self) {
                return isFunctionType(attributed.baseType)
            }
            return false
        }
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

            // the name becomes an enum case AND an init parameter label, so it has
            // to be an identifier — "a b" or "1st" would emit `case a b(String)`.
            guard isValidIdentifier(name) else {
                context.diagnose(
                    Diagnostic(
                        node: nameExpr.expression,
                        message: MacroExpansionErrorMessage(
                            "content case '\(name)' is not a valid Swift identifier"
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
            } else if let unlabeledArg = call.arguments.first(where: { $0.label?.text == "unlabeled" }) {
                if let literal = unlabeledArg.expression.as(BooleanLiteralExprSyntax.self) {
                    unlabeled = literal.literal.text == "true"
                } else {
                    // a non-literal would silently read as `false`
                    context.diagnose(
                        Diagnostic(
                            node: unlabeledArg.expression,
                            message: MacroExpansionErrorMessage(
                                "unlabeled: requires a boolean literal (true or false)"
                            )
                        )
                    )
                }
            }

            cases.append(
                ParsedCase(
                    name: name,
                    isBuilder: isBuilder,
                    unlabeled: unlabeled,
                    nameNode: nameExpr.expression
                )
            )
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
        var value = ""
        for segment in literal.segments {
            // interpolation would make the case name non-constant; the caller
            // gets "requires a string-literal name" rather than a truncated one.
            guard case .stringSegment(let text) = segment else { return nil }
            value += text.content.text
        }
        return value
    }

    /// whether a name can be emitted as an identifier.
    private static func isValidIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.dropFirst().allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
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

            // a property wrapper (or any other attribute) cannot be re-emitted on a
            // generated init parameter, so the property is reported rather than
            // silently producing an init that assigns through the wrapper.
            if let attribute = variable.attributes.first {
                let name = variable.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? "<property>"
                context.diagnose(
                    Diagnostic(
                        node: attribute,
                        message: MacroExpansionErrorMessage(
                            "stored property '\(name)' carries an attribute that @HTMLComponent cannot re-emit on a generated parameter"
                        )
                    )
                )
                continue
            }

            for binding in variable.bindings {
                // skip computed properties (those with an accessor block)
                if binding.accessorBlock != nil { continue }
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                guard let type = binding.typeAnnotation?.type else {
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
                properties.append(ParsedProperty(name: name, type: type, default: defaultExpr))
            }
        }
        return properties
    }

    // MARK: - reserved names

    /// the macro emits `private enum Content` and `private let content`. a host that
    /// already declares either one would produce a redeclaration error far from the
    /// cause, so both are reported at the declaration that collides.
    private static func checkReservedMembers(
        _ structDecl: StructDeclSyntax,
        in context: some MacroExpansionContext
    ) {
        for member in structDecl.memberBlock.members {
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    if name == "content" {
                        context.diagnose(
                            Diagnostic(
                                node: binding,
                                message: MacroExpansionErrorMessage(
                                    "'content' is @HTMLComponent's storage — rename the property"
                                )
                            )
                        )
                    }
                }
            }
            if let typeDecl = member.decl.as(StructDeclSyntax.self), typeDecl.name.text == "Content" {
                context.diagnose(
                    Diagnostic(
                        node: typeDecl.name,
                        message: MacroExpansionErrorMessage(
                            "'Content' is @HTMLComponent's enum — rename the nested type"
                        )
                    )
                )
            }
            if let typeDecl = member.decl.as(EnumDeclSyntax.self), typeDecl.name.text == "Content" {
                context.diagnose(
                    Diagnostic(
                        node: typeDecl.name,
                        message: MacroExpansionErrorMessage(
                            "'Content' is @HTMLComponent's enum — rename the nested type"
                        )
                    )
                )
            }
        }
    }

    /// a content case and a stored property share the init's parameter list, so
    /// the same name in both places emits `init(x: String, x: Bool)`.
    private static func checkCasePropertyCollisions(
        cases: [ParsedCase],
        properties: [ParsedProperty],
        in context: some MacroExpansionContext
    ) {
        let propertyNames = Set(properties.map(\.name))
        for case_ in cases where propertyNames.contains(case_.name) {
            context.diagnose(
                Diagnostic(
                    node: case_.nameNode,
                    message: MacroExpansionErrorMessage(
                        "content case '\(case_.name)' collides with the stored property of the same name — one of them needs a different name"
                    )
                )
            )
        }
    }

    // MARK: - generation

    private static func generateMembers(
        _ structDecl: StructDeclSyntax,
        cases: [ParsedCase],
        properties: [ParsedProperty]
    ) -> [DeclSyntax] {
        let access = accessPrefix(structDecl)

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

    /// the access level the generated members must carry.
    ///
    /// only `public` and `package` widen access above the default; a `package`
    /// struct with an `internal` init would be unconstructible from a sibling
    /// module in the same package, which is the whole point of `package`.
    private static func accessPrefix(_ structDecl: StructDeclSyntax) -> String {
        if structDecl.modifiers.contains(where: { $0.name.text == "public" }) { return "public " }
        if structDecl.modifiers.contains(where: { $0.name.text == "package" }) { return "package " }
        return ""
    }

    /// the shared parameter list, in declaration order.
    private static func parameters(
        _ properties: [ParsedProperty],
        appending trailing: [String] = []
    ) -> String {
        var params = properties.map { prop in
            if let default_ = prop.default {
                return "\(prop.name): \(prop.parameterType) = \(default_)"
            }
            return "\(prop.name): \(prop.parameterType)"
        }
        params.append(contentsOf: trailing)
        return params.joined(separator: ", ")
    }

    /// the shared assignments, in declaration order.
    private static func assignments(_ properties: [ParsedProperty]) -> String {
        properties.map { "    self.\($0.name) = \($0.name)" }.joined(separator: "\n")
    }

    /// generate the init for a single `.text` content case.
    private static func generateTextInit(
        case_: ParsedCase,
        properties: [ParsedProperty],
        access: String
    ) -> DeclSyntax {
        // the content parameter comes first, then the shared properties
        let caseParameter = case_.unlabeled
            ? "_ \(case_.name): String"
            : "\(case_.name): String"
        let shared = parameters(properties)
        let paramText = shared.isEmpty ? caseParameter : "\(caseParameter), \(shared)"

        let assignmentsText = assignments(properties)
        let contentLine = "    self.content = .\(case_.name)(\(case_.name))"
        let body = assignmentsText.isEmpty ? contentLine : "\(assignmentsText)\n\(contentLine)"

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
        let paramText = parameters(
            properties,
            appending: ["@ViewBuilder \(case_.name): () -> [any WebUI.View]"]
        )

        let assignmentsText = assignments(properties)
        let contentLine = "    self.content = .\(case_.name)(\(case_.name)())"
        let body = assignmentsText.isEmpty ? contentLine : "\(assignmentsText)\n\(contentLine)"

        return DeclSyntax("""
        \(raw: access)init(\(raw: paramText)) {
        \(raw: body)
        }
        """)
    }
}