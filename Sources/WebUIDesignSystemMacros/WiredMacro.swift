import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - WiredMacro

/// `@Wired` is a peer marker: it expands to nothing. The only work it does is
/// validate the annotated handler (must be a func, must be `async`, must
/// return `[FragmentUpdate]` or `HandlerOutcome`). All code generation happens
/// in the enclosing `@WireGroup` member macro.
///
/// ```swift
/// @Wired("cb-file", events: [.click])
/// func handleAttachFile(_ event: EventData) async -> [FragmentUpdate] { … }
///
/// @Wired("cb-save", events: [.submit])
/// func handleSave(_ event: EventData) async -> HandlerOutcome { .refresh }
/// ```
///
/// the return type is the decision, not an argument: a fragments handler keeps
/// the fragment registration and an outcome handler registers through the
/// outcome door. there is no flag and no bool to get wrong.
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

        // the return type is compared structurally, not as text: `[FragmentUpdate]`
        // and `[WebUI.FragmentUpdate]` are the same type, and a string comparison
        // would reject the qualified spelling. the same walk accepts
        // `HandlerOutcome` / `WebUI.HandlerOutcome`: a handler's own return type
        // is the compile-time decision for what `@WireGroup` emits, so there is
        // no flag, no bool, and no second spelling to keep in sync.
        guard let returnType = funcDecl.signature.returnClause?.type else {
            throw MacroExpansionErrorMessage(
                "@Wired on '\(name)' must return '[FragmentUpdate]' or 'HandlerOutcome', got 'no return type'"
            )
        }
        guard isFragmentUpdateArray(returnType) || isHandlerOutcome(returnType) else {
            throw MacroExpansionErrorMessage(
                "@Wired on '\(name)' must return '[FragmentUpdate]' or 'HandlerOutcome', got '\(returnType.trimmedDescription)'"
            )
        }

        // the id is this attribute's own argument, so it is validated here rather
        // than only inside `@WireGroup`: a bad id is reported where it is written,
        // even when no group wraps the handler.
        guard WiredArguments.id(from: node) != nil else {
            throw MacroExpansionErrorMessage(
                "@Wired requires an id string literal (interpolation is not a compile-time id)"
            )
        }

        return []
    }

    /// whether the type is `HandlerOutcome`, qualified or not.
    static func isHandlerOutcome(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "HandlerOutcome"
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == "HandlerOutcome"
        }
        return false
    }

    /// whether the type is `[FragmentUpdate]`, qualified or not.
    static func isFragmentUpdateArray(_ type: TypeSyntax) -> Bool {
        guard let array = type.as(ArrayTypeSyntax.self) else { return false }
        return isFragmentUpdate(array.element)
    }

    private static func isFragmentUpdate(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "FragmentUpdate"
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == "FragmentUpdate"
        }
        return false
    }
}

// MARK: - shared argument parsing

/// the `@Wired` attribute's arguments, parsed once and read by both macros.
///
/// each macro owns the diagnostics for what it is responsible for: `@Wired`
/// reports a bad id (its own argument), `@WireGroup` reports duplicate ids
/// across handlers (a cross-handler fact it alone can see). neither reports
/// the other's error, so one mistake produces one diagnostic.
enum WiredArguments {
    /// the id, in its value form (for comparison) and source form (escapes intact).
    static func id(from attr: AttributeSyntax) -> (value: String, source: String)? {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
        for arg in arguments where arg.label == nil {
            return plainStringLiteral(arg.expression)
        }
        return nil
    }

    /// the events expression as written, defaulting to a click.
    static func events(from attr: AttributeSyntax) -> String {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else { return "[.click]" }
        for arg in arguments where arg.label?.text == "events" {
            return arg.expression.trimmedDescription
        }
        return "[.click]"
    }

    /// a string literal with no interpolation, in both its value form (for
    /// comparison) and its source form (for re-emission).
    static func plainStringLiteral(_ expr: ExprSyntax) -> (value: String, source: String)? {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
        var value = ""
        for segment in literal.segments {
            // an interpolation segment means the id is not a compile-time
            // constant: report it rather than silently taking the literal parts.
            guard case .stringSegment(let text) = segment else { return nil }
            value += text.content.text
        }
        return (value: value, source: literal.trimmedDescription)
    }

    /// the value of a string-literal expression, or `nil`.
    static func stringLiteralValue(_ expr: ExprSyntax) -> String? {
        plainStringLiteral(expr)?.value
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
              let groupName = WiredArguments.stringLiteralValue(first.expression) else {
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
        var handlers: [WiredHandler] = []
        var seenIDs: [String: String] = [:]

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard let wiredAttr = findWiredAttribute(funcDecl) else { continue }
            guard let wired = parseWiredArguments(wiredAttr) else { continue }

            if let existing = seenIDs[wired.id] {
                context.diagnose(
                    Diagnostic(
                        node: funcDecl,
                        message: MacroExpansionErrorMessage(
                            "wire id \"\(wired.id)\" already declared by \(existing) in group \"\(groupName)\""
                        )
                    )
                )
                continue
            }

            seenIDs[wired.id] = funcDecl.name.text
            handlers.append(
                WiredHandler(
                    id: wired.id,
                    idLiteral: wired.idLiteral,
                    eventsExpr: wired.eventsExpr,
                    funcName: funcDecl.name.text,
                    // the handler's own return type is the decision, read the same
                    // structural way `@Wired` validates it. a type that is neither
                    // stays on the fragment path here: `@Wired` owns that
                    // diagnostic and reports it once, at the attribute — this
                    // macro must not emit a second error for one mistake.
                    returnsOutcome: funcDecl.signature.returnClause.map {
                        WiredMacro.isHandlerOutcome($0.type)
                    } ?? false
                )
            )
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

    // MARK: parsed representation

    /// one `@Wired` handler, as the registrar needs it.
    ///
    /// the id and the events list are kept in their **source spelling** so the
    /// generated code reproduces the caller's own expression. that is what keeps
    /// the event filter type-checked: `[.custom("x")]` reaches the compiler as an
    /// `[HTMLEvent]` instead of being flattened to a hand-quoted string.
    private struct WiredHandler {
        /// the id's value, for duplicate detection and diagnostics.
        let id: String
        /// the id literal as written (`"cb-file"`), for emission — escapes intact.
        let idLiteral: String
        /// the events expression as written (`[.click]`), for emission.
        let eventsExpr: String
        let funcName: String
        /// whether the handler answers `HandlerOutcome` rather than
        /// `[FragmentUpdate]` — the one thing that changes what is emitted.
        let returnsOutcome: Bool
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

    /// read the id and events from a `@Wired` attribute.
    ///
    /// returns `nil` when the id is missing or is not a single string literal.
    /// no diagnostic is reported here: `@Wired` owns that error and reports it at
    /// the attribute, so one mistake never produces two messages. a handler whose
    /// id cannot be read is simply not registered.
    private static func parseWiredArguments(
        _ attr: AttributeSyntax
    ) -> (id: String, idLiteral: String, eventsExpr: String)? {
        guard let literal = WiredArguments.id(from: attr) else { return nil }
        return (
            id: literal.value,
            idLiteral: literal.source,
            eventsExpr: WiredArguments.events(from: attr)
        )
    }

    /// whether a group name matches `[a-z][a-z0-9_]*`.
    private static func isValidGroupName(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercase else { return false }
        return name.dropFirst().allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    /// generate the `wireGroup_<name>(_ router:)` registrar method.
    ///
    /// the event filter is built from the caller's own expression, cast to
    /// `[HTMLEvent]` and mapped through `rawValue`, so the compiler checks it and
    /// `.custom(_:)` carries its payload — no case name is recovered from source
    /// text.
    private static func generateRegistrar(
        groupName: String,
        handlers: [WiredHandler]
    ) -> DeclSyntax {
        let methodName = "wireGroup_\(groupName)"
        var bodyLines: [String] = []

        for handler in handlers {
            let eventsName = "\(handler.funcName)Events"
            // the events list is emitted as the caller's own expression, cast to
            // `[HTMLEvent]` and mapped through `rawValue` — the compiler checks the
            // event spellings, `.custom(_:)` carries its payload, and the filter is a
            // plain array lookup (no closure, so the emitted code does not get
            // reflowed across lines by the printer).
            bodyLines.append(
                "    let \(eventsName): [String] = (\(handler.eventsExpr) as [HTMLEvent]).map(\\.rawValue)"
            )
            // two return types, two registrations — both into the HOST table (no
            // session argument), which is the single-page host's shape and the
            // table `WebUIServer.start()` seals before the listener accepts a
            // frame. a `@Wired` handler wired in a host's own init therefore has
            // to register here, not in a session it does not have.
            if handler.returnsOutcome {
                // the outcome door: the same event filter, the handler's own
                // `HandlerOutcome` passed through untouched. a filtered event
                // answers `.fragments([])` — the same wire shape as the fragment
                // path's `[]`, and the only spelling that type-checks, because
                // `HandlerOutcome` has no ExpressibleByArrayLiteral conformance.
                bodyLines.append("    router.register(outcome: { event in")
                bodyLines.append("        guard \(eventsName).contains(event.event.rawValue) else {")
                bodyLines.append("            return .fragments([])")
                bodyLines.append("        }")
                bodyLines.append("        return await self.\(handler.funcName)(event)")
                bodyLines.append("    }, for: ComponentID(\(handler.idLiteral)))")
            } else {
                bodyLines.append("    router.register({ event in")
                bodyLines.append("        guard \(eventsName).contains(event.event.rawValue) else {")
                bodyLines.append("            return []")
                bodyLines.append("        }")
                bodyLines.append("        return await self.\(handler.funcName)(event)")
                bodyLines.append("    }, for: ComponentID(\(handler.idLiteral)))")
            }
        }

        let body = bodyLines.joined(separator: "\n")

        return DeclSyntax("""
        func \(raw: methodName)(_ router: EventRouter) {
        \(raw: body)
        }
        """)
    }
}