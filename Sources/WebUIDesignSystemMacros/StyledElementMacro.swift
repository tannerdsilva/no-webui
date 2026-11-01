import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - StyledElementMacro

/// `@StyledElement(.div, class: .setRow)` — the element and its base classes are
/// stated once, at the type. a stored property marked `@Axis` is a class axis,
/// and its enum is the only set of classes that component will accept; a stored
/// property marked `@Part` is a declared child, rendered before `content`; an
/// unmarked stored property is payload the initializer requires.
///
/// two roles: **member** emits the content storage, both initializers (one
/// pinned to `EmptyView` so `Dot(severity: .err)` resolves), the `tag` /
/// `base` statics the shared renderer reads, and — only when the host declares
/// parts — `renderParts(into:)`; **extension** attaches the
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
        let parts = stored.filter { $0.part != nil }
        let axes = stored.filter { $0.isAxis }
        // a part is stored data too: the initializer offers it among the
        // payload, in declaration order, and `renderParts` renders it. a
        // computed property has no storage, so the initializer neither offers
        // nor assigns it.
        let payload = stored.filter { !$0.isAxis && $0.isStored }
        let offeredAxes = axes.filter(\.isStored)

        // one parameter per axis, in declaration order, then id, then the call
        // site's extra classes. the axis defaults come from the host verbatim.
        // payload first: a call site reads its own data before the axes.
        let head = (payload.map { prop in
            prop.defaultText.map { "    \(prop.name): \(prop.type) = \($0)" }
                ?? "    \(prop.name): \(prop.type)"
        }
            + offeredAxes.map { "    \($0.name): \($0.type) = \($0.defaultText ?? "nil")" }
            + ["    id: String? = nil", "    class extra: ClassName? = nil"])
            .joined(separator: ",\n")
        let ordered = payload.map(\.name) + offeredAxes.map(\.name)
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

            // qualified on purpose: `Tag` is written into the *host's* file
            // scope, where another module's `Tag` (Testing vends one) can
            // shadow it. the host already has WebUI in scope to declare
            // `Content: View`, and WebUI re-exports WebUICore.
            DeclSyntax("""
            \(raw: access)static var tag: WebUICore.Tag? { \(raw: spec.tag) }
            """),

            DeclSyntax("""
            \(raw: access)static var base: ClassName { \(raw: spec.base ?? ".init(\"\(kebab(structDecl.name.text))\")") }
            """),
        ]

        // only a component that declares parts writes this; the protocol
        // extension already supplies the empty prefix. the calls run in
        // declaration order, which is the order the parts render in.
        if !parts.isEmpty {
            let calls = parts.map { part in
                "    renderPart(\(part.name), tag: \(part.partTag), class: \(part.classText ?? "nil"), into: &buffer)"
            }.joined(separator: "\n")
            members.append(DeclSyntax("""
            \(raw: access)func renderParts(into buffer: inout HTMLBuffer) {
            \(raw: calls)
            }
            """))
        }

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

    // MARK: - the host's stored properties

    private struct StoredProperty {
        let name: String
        /// the declared type, verbatim, so `Stack?` keeps its optionality.
        let type: String
        /// the declared default expression, verbatim; nil means the initializer
        /// requires it at every call site.
        let defaultText: String?
        /// true when the property carries `@Axis` — a class axis, not data.
        let isAxis: Bool
        /// the declared part, when the property carries `@Part`.
        let part: PartSpec?
        /// false for a computed property: rendered, but never initialized.
        let isStored: Bool
        var isOptional: Bool { type.hasSuffix("?") }
        /// `@Part`'s tag expression, verbatim.
        var partTag: String { part?.tag ?? "" }
        /// `@Part`'s class expression, verbatim; nil when the part names none.
        var classText: String? { part?.className }
    }

    /// the tag and class of one `@Part(.h1, class: .detailTitle)`.
    struct PartSpec {
        let tag: String
        let className: String?
    }

    /// split the host's stored properties into **parts**, **axes** and
    /// **payload**.
    ///
    /// `@Part` and `@Axis` are the discriminators, and they live in the body
    /// beside the property they mark — the same shape rawdog uses, where a
    /// member macro is woven into the body of an enclosing attached macro. a
    /// macro cannot ask the type checker whether a property's type conforms to
    /// `ClassAxis`, so the marker is the honest way to say which is which.
    ///
    /// a computed property is skipped by the initializer (`isStored` is false):
    /// it is not storage, so nothing can assign it.
    private static func scanStored(_ structDecl: StructDeclSyntax) -> [StoredProperty] {
        var out: [StoredProperty] = []
        for member in structDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }
            guard variable.bindingSpecifier.text == "var" || variable.bindingSpecifier.text == "let" else {
                continue
            }

            let axisAttribute = variable.attributes.first { attribute in
                guard let attr = attribute.as(AttributeSyntax.self) else {
                    return false
                }
                return attr.attributeName.trimmedDescription == "Axis"
            }
            let partAttribute = variable.attributes.first { attribute in
                guard let attr = attribute.as(AttributeSyntax.self) else {
                    return false
                }
                return attr.attributeName.trimmedDescription == "Part"
            }
            let part = (partAttribute?.as(AttributeSyntax.self)).flatMap { parsePart($0) }
            // a property carrying both markers is a part: the part is rendered
            // from its own value, which a class axis never is.
            let isAxis = axisAttribute != nil && part == nil

            for binding in variable.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation
                else { continue }

                out.append(
                    StoredProperty(
                        name: pattern.identifier.text,
                        type: typeAnnotation.type.trimmedDescription,
                        defaultText: binding.initializer?.value.trimmedDescription,
                        isAxis: isAxis,
                        part: part,
                        isStored: binding.accessorBlock == nil
                    )
                )
            }
        }
        return out
    }

    /// `@Part(.h1, class: .detailTitle)` -> tag `.h1`, class `.detailTitle`.
    ///
    /// both expressions are kept verbatim, so the generated call resolves its
    /// leading dots against `renderPart`'s own parameter types — the same
    /// mechanism `@StyledElement`'s tag uses.
    private static func parsePart(_ node: AttributeSyntax) -> PartSpec? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let tagArgument = arguments.first(where: { $0.label == nil })
        else {
            return nil
        }
        let className = arguments
            .first(where: { $0.label?.text == "class" })?
            .expression.trimmedDescription
        return PartSpec(tag: tagArgument.expression.trimmedDescription, className: className)
    }

    // MARK: - parsing

    private struct Spec {
        /// the tag expression, verbatim, so `.div` keeps its leading dot and
        /// resolves against the emitted `static var tag: Tag?`.
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

// MARK: - PartMacro

/// `@Part(.h1, class: .detailTitle)` — marks a stored property as a **declared
/// child part** rather than payload.
///
/// peer role, empty expansion: the marker contributes nothing to the host. the
/// enclosing `@StyledElement` reads the marker — and its tag/class arguments —
/// off the property and emits that property's rendering into
/// `renderParts(into:)`, so the part is emitted after the host's open tag and
/// before `content`, in declaration order, with no renderer written anywhere.
///
/// the empty expansion is the whole job. the diagnostics below are the other
/// half: a marker that cannot be rendered is named, and the compiler plugin
/// stays alive — a trap here would take every macro expansion in the build
/// down with it.
///
/// ```swift
/// @StyledElement(.div, class: .detailCard)
/// struct DetailCard<Content: View> {
///     @Part(.h1, class: .detailTitle) var title: String = ""
///     @Part(.div, class: .detailSub) var sub: String = ""
/// }
/// ```
public struct PartMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: declaration,
                    message: MacroExpansionErrorMessage("@Part can only be applied to a stored property")
                )
            )
            return []
        }

        // a part is rendered from its own value, and a call site may set it, so
        // it must be a `var` — the same reason `@Axis` marks a `var`.
        guard variable.bindingSpecifier.text == "var" else {
            context.diagnose(
                Diagnostic(
                    node: variable.bindingSpecifier,
                    message: MacroExpansionErrorMessage("@Part marks a stored `var`: a `let` is not offered to a call site")
                )
            )
            return []
        }

        guard variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation
        else {
            context.diagnose(
                Diagnostic(
                    node: variable,
                    message: MacroExpansionErrorMessage(
                        "@Part needs one named property with a declared type, e.g. `@Part(.h1, class: .detailTitle) var title: String = \"\"`"
                    )
                )
            )
            return []
        }

        // a computed property has no storage for a call site to set, and the
        // host macro does not offer one. diagnose it here rather than emit a
        // renderer that reads a value nobody can pass.
        guard binding.accessorBlock == nil else {
            context.diagnose(
                Diagnostic(
                    node: variable,
                    message: MacroExpansionErrorMessage(
                        "@Part marks a stored property: `\(pattern.identifier.text)` is computed, so a call site has no value to set"
                    )
                )
            )
            return []
        }

        let typeText = typeAnnotation.type.trimmedDescription
        guard typeText == "String" || typeText == "String?" else {
            context.diagnose(
                Diagnostic(
                    node: typeAnnotation.type,
                    message: MacroExpansionErrorMessage(
                        "@Part renders its value as text: `\(pattern.identifier.text)` is `\(typeText)`, not `String` or `String?`"
                    )
                )
            )
            return []
        }

        guard isInsideStyledElementHost(variable, in: context) else {
            context.diagnose(
                Diagnostic(
                    node: node,
                    message: MacroExpansionErrorMessage(
                        "@Part must be declared inside a `@StyledElement` host: nothing else reads the marker"
                    )
                )
            )
            return []
        }

        return []
    }

    /// true unless the enclosing declaration is known to be a struct *without*
    /// `@StyledElement`.
    ///
    /// a peer macro sees only the property it is attached to, so the host is
    /// found two ways: `lexicalContext` — the enclosing declarations the
    /// expansion context carries — and, failing that, the syntax tree's parent
    /// chain. when neither can see an enclosing type (a hand-built tree, or a
    /// context that carries no lexical scope), the check is skipped rather than
    /// guessed: no diagnostic is emitted on a context that cannot be read.
    private static func isInsideStyledElementHost(
        _ declaration: some SyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> Bool {
        for enclosing in context.lexicalContext {
            if let structDecl = enclosing.as(StructDeclSyntax.self) {
                return carriesStyledElement(structDecl)
            }
        }

        guard var node = declaration.parent else {
            return true
        }
        while true {
            if let structDecl = node.as(StructDeclSyntax.self) {
                return carriesStyledElement(structDecl)
            }
            guard let parent = node.parent else {
                // the chain ended without an enclosing type — file scope, a
                // function body, or a type that is not a struct.
                return false
            }
            node = parent
        }
    }

    private static func carriesStyledElement(_ structDecl: StructDeclSyntax) -> Bool {
        structDecl.attributes.contains { attribute in
            guard let attr = attribute.as(AttributeSyntax.self) else {
                return false
            }
            return attr.attributeName.trimmedDescription == "StyledElement"
        }
    }
}

