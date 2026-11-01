import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StyledElementMacro

/// `@StyledElement(.div, class: .setRow)` — the element and its base classes are
/// stated once, at the type. a stored property marked `@Axis` is a class axis,
/// and its enum is the only set of classes that component will accept; an
/// unmarked stored property is payload the initializer requires.
///
/// two roles: **member** emits the content storage, both initializers (one
/// pinned to `EmptyView` so `Dot(severity: .err)` resolves), and the `tag` /
/// `base` statics the shared renderer reads; **extension** attaches the
/// `StyledElement` conformance, whose protocol extension supplies the one
/// `render(into:)` every element shares — the host writes neither.
///
/// the attribute's own parameter types — `Tag` and `ClassName?` — are what
/// type-check `.div` and `.setRow` at the declaration. inside `render` the same
/// two expressions are bound to **locals with explicit types**, which supply the
/// contextual type the leading dots need. that is deliberately the whole
/// mechanism: a generic type cannot hold `static let`
/// (`static stored properties not supported in generic types`), and a nested
/// enum does not escape that rule either — but a local does, and it leaves
/// nothing behind. no generated type, no generated static, nothing at file
/// scope and nothing on the type's surface.
///
/// the host declares exactly one generic `: View` parameter — a member macro
/// cannot widen the host's generic parameter list, the same constraint
/// `@HTMLComponent` documents.
///
/// ```swift
/// @StyledElement(.div, class: .setRow)
/// struct SetRow<Content: View>: View {
///     enum Stack: String, ClassAxis {
///         case regular = "set-row-stack"
///         case large   = "set-row-stack-lg"
///     }
///     @Axis var stack: Stack? = nil
/// }
///
/// SetRow { … }                    // <div class="set-row">
/// SetRow(stack: .large) { … }     // <div class="set-row set-row-stack-lg">
/// ```
public struct StyledElementMacro: MemberMacro, ExtensionMacro {

    // MARK: - extension: the conformance

    /// the host writes `struct SetRow<Content: View> { }`; the conformance is
    /// added here, so no declaration repeats `: StyledElement`.
    ///
    /// the members this conformance needs are emitted by the member role into
    /// the primary declaration — an extension cannot carry stored properties —
    /// and Swift expands members before it checks the extension.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        [try ExtensionDeclSyntax("extension \(type.trimmed): StyledElement {}")]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: MacroExpansionErrorMessage("@StyledElement can only be applied to a struct")
                )
            )
            return []
        }

        let generics = structDecl.genericParameterClause?.parameters ?? []
        guard generics.count == 1, let contentParam = generics.first else {
            context.diagnose(
                Diagnostic(
                    node: structDecl.name,
                    message: MacroExpansionErrorMessage(
                        "@StyledElement needs exactly one generic `: View` parameter for the element's children, e.g. `struct SetRow<Content: View>`"
                    )
                )
            )
            return []
        }

        guard let spec = parseSpec(node, in: context) else {
            return []
        }

        let access = accessPrefix(structDecl)
        let contentName = contentParam.name.text
        let stored = scanStored(structDecl)
        let axes = stored.filter { $0.isAxis }
        let payload = stored.filter { !$0.isAxis }

        // one parameter per axis, in declaration order, then id, then the call
        // site's extra classes. the axis defaults come from the host verbatim.
        // payload first: a call site reads its own data before the axes.
        let head = (payload.map { prop in
            prop.defaultText.map { "    \(prop.name): \(prop.type) = \($0)" }
                ?? "    \(prop.name): \(prop.type)"
        }
            + axes.map { "    \($0.name): \($0.type) = \($0.defaultText ?? "nil")" }
            + ["    id: String? = nil", "    class extra: ClassName? = nil"])
            .joined(separator: ",\n")
        let ordered = payload.map(\.name) + axes.map(\.name)
        let delegate = (ordered.map { "        \($0): \($0)" }
            + ["        id: id", "        class: extra"])
            .joined(separator: ",\n")
        let assign = ordered.map { "    self.\($0) = \($0)" }.joined(separator: "\n")

        // an optional axis contributes its token when present and non-empty, so
        // a `.normal` case can mean "no class at all". a non-optional axis is
        // always present.
        let axisJoins = axes.map { axis -> String in
            if axis.isOptional {
                return "    if let \(axis.name) = \(axis.name), !\(axis.name).token.isEmpty {\n        tokens.add(token: \(axis.name).token)\n    }"
            }
            return "    if !\(axis.name).token.isEmpty {\n        tokens.add(token: \(axis.name).token)\n    }"
        }.joined(separator: "\n")

        var members: [DeclSyntax] = [
            DeclSyntax("\(raw: access)let content: \(raw: contentName)"),
            DeclSyntax("\(raw: access)let id: String?"),
            DeclSyntax("\(raw: access)let extra: ClassName?"),

            DeclSyntax("""
            \(raw: access)init(
            \(raw: head),
                @ElementBuilder content: () -> \(raw: contentName)
            ) {
            \(raw: assign)
                self.id = id
                self.extra = extra
                self.content = content()
            }
            """),

            // the no-closure spelling, e.g. `Dot(severity: .err)`. pinned rather
            // than a default argument: `= { EmptyView() }` cannot type against
            // an arbitrary `Content` inside a generic body.
            DeclSyntax("""
            \(raw: access)init(
            \(raw: head)
            ) where \(raw: contentName) == EmptyView {
                self.init(
            \(raw: delegate)
                ) { EmptyView() }
            }
            """),

            DeclSyntax("""
            \(raw: access)static var tag: Tag { \(raw: spec.tag) }
            """),

            DeclSyntax("""
            \(raw: access)static var base: ClassName { \(raw: spec.base ?? ".init(\"\(kebab(structDecl.name.text))\")") }
            """),
        ]

        // only a component that declares axes writes this; the protocol
        // extension already supplies the empty contribution.
        if !axes.isEmpty {
            members.append(DeclSyntax("""
            \(raw: access)func contribute(to tokens: inout ClassTokens) {
            \(raw: axisJoins)
            }
            """))
        }

        return members
    }

    // MARK: - the host's axes

    private struct StoredProperty {
        let name: String
        /// the declared type, verbatim, so `Stack?` keeps its optionality.
        let type: String
        /// the declared default expression, verbatim; nil means the initializer
        /// requires it at every call site.
        let defaultText: String?
        /// true when the property carries `@Axis` — a class axis, not data.
        let isAxis: Bool
        var isOptional: Bool { type.hasSuffix("?") }
    }

    /// split the host's stored properties into **axes** and **payload**.
    ///
    /// `@Axis` is the discriminator, and it lives in the body beside the
    /// property it marks — the same shape rawdog uses, where a member macro is
    /// woven into the body of an enclosing attached macro. a macro cannot ask
    /// the type checker whether a property's type conforms to `ClassAxis`, so
    /// the marker is the honest way to say which is which.
    ///
    /// a computed property is skipped: it is not stored, so it is neither.
    private static func scanStored(_ structDecl: StructDeclSyntax) -> [StoredProperty] {
        var out: [StoredProperty] = []
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            guard variable.bindingSpecifier.text == "var" || variable.bindingSpecifier.text == "let" else {
                continue
            }

            let isAxis = variable.attributes.contains { attribute in
                guard let attr = attribute.as(AttributeSyntax.self) else {
                    return false
                }
                return attr.attributeName.trimmedDescription == "Axis"
            }

            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation
                else { continue }

                out.append(
                    StoredProperty(
                        name: pattern.identifier.text,
                        type: typeAnnotation.type.trimmedDescription,
                        defaultText: binding.initializer?.value.trimmedDescription,
                        isAxis: isAxis
                    )
                )
            }
        }
        return out
    }

    // MARK: - parsing

    private struct Spec {
        /// the tag expression, verbatim, so `.div` keeps its leading dot and
        /// resolves against the emitted `let tag: Tag`.
        let tag: String
        /// the base class expression, verbatim, resolved against the emitted
        /// `let base: ClassName?`. nil when the attribute names none.
        let base: String?
    }

    /// `DetailCard` -> `detail-card`, `CardH3` -> `card-h3`, `McRow` -> `mc-row`.
    ///
    /// this is the inverse of the camel-casing the vocabulary generator applies
    /// to a token, and it is what lets a component name its class by being named:
    /// no static, no marker type, and therefore nothing to collide with.
    static func kebab(_ name: String) -> String {
        var out = ""
        for character in name {
            if character.isUppercase {
                if !out.isEmpty { out.append("-") }
                out.append(Character(character.lowercased()))
            } else {
                out.append(character)
            }
        }
        return out
    }

    private static func parseSpec(
        _ node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Spec? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let tagArgument = arguments.first(where: { $0.label == nil })
        else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: MacroExpansionErrorMessage(
                        "@StyledElement requires a tag: `@StyledElement(.div, class: .setRow)`"
                    )
                )
            )
            return nil
        }

        let base = arguments
            .first(where: { $0.label?.text == "class" })?
            .expression.trimmedDescription

        return Spec(tag: tagArgument.expression.trimmedDescription, base: base)
    }

    private static func accessPrefix(_ structDecl: StructDeclSyntax) -> String {
        if structDecl.modifiers.contains(where: { $0.name.text == "public" }) { return "public " }
        if structDecl.modifiers.contains(where: { $0.name.text == "package" }) { return "package " }
        return ""
    }
}

// MARK: - AxisMacro

/// `@Axis` — marks a stored property as a **class axis** rather than payload.
///
/// peer role, empty expansion: the marker contributes nothing to the host. all
/// of the work happens in the enclosing `@StyledElement`, which reads the marker
/// off the property and emits that property into `contribute(to:)` instead of
/// into the initializer alone.
///
/// this is the rawdog shape: a small macro woven into the body, read by the
/// body macro above it. a macro cannot ask the type checker whether a type
/// conforms to `ClassAxis`, so the marker is how the author says it.
public struct AxisMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}
