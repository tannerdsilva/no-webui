import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - WiredMacro

/// `@Wired` is a peer marker: it expands to nothing. The only work it does is
/// validate the annotated handler (must be a func, must be `async`, must
/// return `[FragmentUpdate]`). All code generation happens in the enclosing
/// `@WireGroup` member macro.
///
/// ```swift
/// @Wired("cb-file", events: [.click])
/// func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { … }
/// ```
public struct WiredMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw MacroExpansionErrorMessage("@Wired can only be applied to a func")
        }

        let name = funcDecl.name.text

        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        guard isAsync else {
            throw MacroExpansionErrorMessage(
                "@Wired on '\(name)' requires an 'async' function"
            )
        }

        let actual = funcDecl.signature.returnClause?.type.trimmedDescription ?? "no return type"
        guard actual == "[FragmentUpdate]" else {
            throw MacroExpansionErrorMessage(
                "@Wired on '\(name)' must return '[FragmentUpdate]', got '\(actual)'"
            )
        }

        return []
    }
}

// MARK: - WireGroupMacro

/// `@WireGroup` is a member macro: it reads the `@Wired`-annotated func
/// members in its host and emits one `wireGroup_<name>(_ router:)` registrar
/// per group, in declaration order.
///
/// ```swift
/// @WireGroup("chat")
/// extension Controller {
///     @Wired("cb-file", events: [.click])
///     func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { … }
/// }
/// // controller.wireGroup_chat(router)
/// ```
public struct WireGroupMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard isNominalHost(declaration) else {
            throw MacroExpansionErrorMessage(
                "@WireGroup can only be applied to a struct, class, or extension"
            )
        }

        // ── parse and validate the group name ──────────────────────────────
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let first = arguments.first,
              let groupName = stringLiteralValue(first.expression) else {
            throw MacroExpansionErrorMessage(
                "@WireGroup requires a string literal name"
            )
        }

        guard isValidGroupName(groupName) else {
            throw MacroExpansionErrorMessage(
                "@WireGroup name '\(groupName)' must match [a-z][a-z0-9_]*"
            )
        }

        // ── find @Wired members ────────────────────────────────────────────
        var handlers: [(id: String, events: String, funcName: String)] = []
        var seenIDs: [String: String] = [:]

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard let wiredAttr = findWiredAttribute(funcDecl) else { continue }

            guard let (id, eventsText) = parseWiredArguments(wiredAttr, in: context) else {
                continue
            }

            if let existing = seenIDs[id] {
                context.diagnose(
                    Diagnostic(
                        node: funcDecl,
                        message: MacroExpansionErrorMessage(
                            "wire id \"\(id)\" already declared by \(existing) in group \"\(groupName)\""
                        )
                    )
                )
                continue
            }

            seenIDs[id] = funcDecl.name.text
            handlers.append((id, eventsText, funcDecl.name.text))
        }

        if handlers.isEmpty {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: MacroExpansionWarningMessage(
                        "@WireGroup(\"\(groupName)\") is empty — no @Wired handlers found"
                    )
                )
            )
        }

        // ── generate the registrar ─────────────────────────────────────────
        return [generateRegistrar(groupName: groupName, handlers: handlers)]
    }

    // MARK: helpers

    /// whether the host declaration is a struct, class, or extension.
    private static func isNominalHost(_ declaration: some DeclGroupSyntax) -> Bool {
        declaration is StructDeclSyntax
            || declaration is ClassDeclSyntax
            || declaration is ExtensionDeclSyntax
    }

    /// find the `@Wired` attribute on a function declaration, if present.
    private static func findWiredAttribute(_ funcDecl: FunctionDeclSyntax) -> AttributeSyntax? {
        for attr in funcDecl.attributes {
            guard let attribute = attr.as(AttributeSyntax.self) else { continue }
            if attribute.attributeName.trimmedDescription == "Wired" {
                return attribute
            }
        }
        return nil
    }

    /// extract the id and events from a `@Wired` attribute.
    ///
    /// returns `nil` (and reports a diagnostic) if the id is missing.
    private static func parseWiredArguments(
        _ attr: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> (id: String, events: String)? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: attr,
                    message: MacroExpansionErrorMessage("@Wired requires an id string literal")
                )
            )
            return nil
        }

        var id: String?
        var eventsText = "[\"click\"]" // default: [.click]

        for arg in arguments {
            if arg.label == nil {
                // positional argument: the id
                id = stringLiteralValue(arg.expression)
            } else if arg.label?.text == "events" {
                eventsText = eventsArrayText(arg.expression)
            }
        }

        guard let id = id else {
            context.diagnose(
                Diagnostic(
                    node: attr,
                    message: MacroExpansionErrorMessage("@Wired requires an id string literal")
                )
            )
            return nil
        }

        return (id, eventsText)
    }

    /// convert an events array expression like `[.click, .submit]` into the
    /// raw-value spelling `["click", "submit"]`.
    private static func eventsArrayText(_ expr: ExprSyntax) -> String {
        guard let array = expr.as(ArrayExprSyntax.self) else {
            return "[]"
        }
        let elements = array.elements.map { element -> String in
            let text = element.expression.trimmedDescription
            // strip a leading dot or type prefix: ".click" -> "click",
            // "HTMLEvent.click" -> "click"
            if let lastDot = text.lastIndex(of: ".") {
                return "\"\(String(text[text.index(after: lastDot)...]))\""
            }
            return "\"\(text)\""
        }
        return "[\(elements.joined(separator: ", "))]"
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

    /// whether a group name matches `[a-z][a-z0-9_]*`.
    private static func isValidGroupName(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase else { return false }
        return name.dropFirst().allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    /// generate the `wireGroup_<name>(_ router:)` registrar method.
    private static func generateRegistrar(
        groupName: String,
        handlers: [(id: String, events: String, funcName: String)]
    ) -> DeclSyntax {
        let methodName = "wireGroup_\(groupName)"
        var bodyLines: [String] = []
        for handler in handlers {
            bodyLines.append("    router.register({ event in")
            bodyLines.append(
                "        guard \(handler.events).contains(event.event) else { return [] }"
            )
            bodyLines.append("        return await self.\(handler.funcName)(event)")
            bodyLines.append("    }, for: ComponentID(\"\(handler.id)\"))")
        }
        let body = bodyLines.joined(separator: "\n")

        return DeclSyntax("""
        func \(raw: methodName)(_ router: EventRouter) {
        \(raw: body)
        }
        """)
    }
}
