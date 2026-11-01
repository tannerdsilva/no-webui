import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import WebUIDesignSystemMacros

// the expansion is a contract, not a demo: every expectation below is the whole
// expanded file, compared by `assertMacroExpansion`. a change to the emitted
// shape fails here with the expected/actual diff inline, which is the dump this
// file used to print — it now costs nothing because it only exists on failure.

// MARK: - strict expansion helper

private let styledMacros: [String: Macro.Type] = [
    "StyledElement": StyledElementMacro.self,
    "Axis": AxisMacro.self,
    "Part": PartMacro.self,
]

private func assertStyledExpansion(
    _ source: String,
    expanded expected: String
) {
    assertMacroExpansion(
        source,
        expandedSource: expected,
        macroSpecs: styledMacros.mapValues { MacroSpec(type: $0) },
        failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
    )
}

/// every diagnostic the macros emit for `source`, in source order.
///
/// diagnostics are how the macro refuses input: it must never trap, because a
/// trap takes the whole compiler plugin down with it.
private func emittedDiagnostics(_ source: String) -> [String] {
    let file = Parser.parse(source: source)
    let context = BasicMacroExpansionContext()
    _ = file.expand(
        macros: styledMacros,
        contextGenerator: { _ in context }
    )
    return context.diagnostics.map { $0.message }
}

// MARK: - expansion fixtures

@Suite("StyledElement macro expansion")
struct StyledElementMacroExpansionTests {

    /// the member role: storage, both initializers, and the two statics the
    /// shared renderer reads. the extension role appends the conformance, so
    /// the host writes neither `: StyledElement` nor a `render(into:)`.
    @Test("member role emits storage, both inits, and tag/base")
    func memberRoleEmitsStorageAndBothInitializers() {
        assertStyledExpansion(
            """
            @StyledElement(.div, class: .detailSub)
            public struct DetailSub<Content: View> {
            }
            """,
            expanded: """
            public struct DetailSub<Content: View> {

                public let content: Content

                public let id: String?

                public let extra: ClassName?

                public init(
                    id: String? = nil,
                    class extra: ClassName? = nil,
                    @ElementBuilder content: () -> Content
                ) {

                    self.id = id
                    self.extra = extra
                    self.content = content()
                }

                public init(
                    id: String? = nil,
                    class extra: ClassName? = nil
                ) where Content == EmptyView {
                    self.init(
                        id: id,
                        class: extra
                    ) {
                        EmptyView()
                    }
                }

                public static var tag: WebUICore.Tag? {
                    .div
                }

                public static var base: ClassName {
                    .detailSub
                }
            }

            extension DetailSub: StyledElement {
            }
            """
        )
    }

    /// the extension role on its own: it emits the conformance and nothing
    /// else. pinned by calling that entry point directly, because the member
    /// and extension roles always run together through `assertMacroExpansion`.
    @Test("extension role adds the StyledElement conformance")
    func extensionRoleAddsTheConformance() throws {
        let source = """
            @StyledElement(.div, class: .detailSub)
            public struct DetailSub<Content: View> {
            }
            """
        let file = Parser.parse(source: source)
        let structDecl = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
        let attribute = try #require(structDecl.attributes.first?.as(AttributeSyntax.self))

        let extensions = try StyledElementMacro.expansion(
            of: attribute,
            attachedTo: structDecl,
            providingExtensionsOf: TypeSyntax("DetailSub"),
            conformingTo: [TypeSyntax("StyledElement")],
            in: BasicMacroExpansionContext()
        )

        #expect(extensions.map(\.description) == ["extension DetailSub: StyledElement {}"])
    }

    /// `@Axis` splits the host's stored properties: payload is required at the
    /// call site and never contributes a class; an axis is a parameter with its
    /// declared default and contributes its token.
    @Test("an @Axis property is payload-excluded and contributes its token")
    func axisSplitsFromPayload() {
        assertStyledExpansion(
            """
            @StyledElement(.div, class: .setRow)
            struct SetRow<Content: View> {
                enum Stack: String, ClassAxis {
                    case regular = "set-row-stack"
                }
                @Axis var stack: Stack? = nil
                let name: String
            }
            """,
            expanded: """
            struct SetRow<Content: View> {
                enum Stack: String, ClassAxis {
                    case regular = "set-row-stack"
                }
                var stack: Stack? = nil
                let name: String

                let content: Content

                let id: String?

                let extra: ClassName?

                init(
                    name: String,
                    stack: Stack? = nil,
                    id: String? = nil,
                    class extra: ClassName? = nil,
                    @ElementBuilder content: () -> Content
                ) {
                    self.name = name
                    self.stack = stack
                    self.id = id
                    self.extra = extra
                    self.content = content()
                }

                init(
                    name: String,
                    stack: Stack? = nil,
                    id: String? = nil,
                    class extra: ClassName? = nil
                ) where Content == EmptyView {
                    self.init(
                        name: name,
                        stack: stack,
                        id: id,
                        class: extra
                    ) {
                        EmptyView()
                    }
                }

                static var tag: WebUICore.Tag? {
                    .div
                }

                static var base: ClassName {
                    .setRow
                }

                func contribute(to tokens: inout ClassTokens) {
                    if let stack = stack, !stack.token.isEmpty {
                        tokens.add(token: stack.token)
                    }
                }
            }

            extension SetRow: StyledElement {
            }
            """
        )
    }

    /// `@Part` splits a declared child out of the payload's rendering: the
    /// property is still offered by the initializer (declaration order), and it
    /// is emitted by `renderParts` — which is written only when a host declares
    /// a part. the marker itself leaves nothing behind.
    @Test("a @Part property renders before content, in declaration order")
    func partSplitsADeclaredChild() {
        assertStyledExpansion(
            """
            @StyledElement(.div, class: .detailCard)
            struct DetailCard<Content: View> {
                @Part(.h1, class: .detailTitle) var title: String = ""
                @Part(.div, class: .detailSub) var sub: String? = nil
                let body: String
            }
            """,
            expanded: """
            struct DetailCard<Content: View> {
                var title: String = ""
                var sub: String? = nil
                let body: String

                let content: Content

                let id: String?

                let extra: ClassName?

                init(
                    title: String = "",
                    sub: String? = nil,
                    body: String,
                    id: String? = nil,
                    class extra: ClassName? = nil,
                    @ElementBuilder content: () -> Content
                ) {
                    self.title = title
                    self.sub = sub
                    self.body = body
                    self.id = id
                    self.extra = extra
                    self.content = content()
                }

                init(
                    title: String = "",
                    sub: String? = nil,
                    body: String,
                    id: String? = nil,
                    class extra: ClassName? = nil
                ) where Content == EmptyView {
                    self.init(
                        title: title,
                        sub: sub,
                        body: body,
                        id: id,
                        class: extra
                    ) {
                        EmptyView()
                    }
                }

                static var tag: WebUICore.Tag? {
                    .div
                }

                static var base: ClassName {
                    .detailCard
                }

                func renderParts(into buffer: inout HTMLBuffer) {
                    renderPart(title, tag: .h1, class: .detailTitle, into: &buffer)
                    renderPart(sub, tag: .div, class: .detailSub, into: &buffer)
                }
            }

            extension DetailCard: StyledElement {
            }
            """
        )
    }

    /// `tag: nil` is an element-free component: the static is optional, and the
    /// shared renderer emits parts and content with no wrapper.
    @Test("a nil tag is emitted as Tag? for an element-free component")
    func nilTagIsEmittedAsOptional() {
        assertStyledExpansion(
            """
            @StyledElement(nil)
            struct PlainStack<Content: View> {
            }
            """,
            expanded: """
            struct PlainStack<Content: View> {

                let content: Content

                let id: String?

                let extra: ClassName?

                init(
                    id: String? = nil,
                    class extra: ClassName? = nil,
                    @ElementBuilder content: () -> Content
                ) {

                    self.id = id
                    self.extra = extra
                    self.content = content()
                }

                init(
                    id: String? = nil,
                    class extra: ClassName? = nil
                ) where Content == EmptyView {
                    self.init(
                        id: id,
                        class: extra
                    ) {
                        EmptyView()
                    }
                }

                static var tag: WebUICore.Tag? {
                    nil
                }

                static var base: ClassName {
                    .init("plain-stack")
                }
            }

            extension PlainStack: StyledElement {
            }
            """
        )
    }

    /// with no `class:` argument the base class is derived from the type name,
    /// so a component names its class by being named. a digit does not open a
    /// new word — `FormGrid2` derives `form-grid2`, not `form-grid-2` — which
    /// is why the probe overrides exactly this case with an explicit `class:`.
    @Test("no class argument derives the base class from the type name")
    func derivedBaseClassFromTypeName() {
        assertStyledExpansion(
            """
            @StyledElement(.div)
            struct FormGrid2<Content: View> {
            }
            """,
            expanded: """
            struct FormGrid2<Content: View> {

                let content: Content

                let id: String?

                let extra: ClassName?

                init(
                    id: String? = nil,
                    class extra: ClassName? = nil,
                    @ElementBuilder content: () -> Content
                ) {

                    self.id = id
                    self.extra = extra
                    self.content = content()
                }

                init(
                    id: String? = nil,
                    class extra: ClassName? = nil
                ) where Content == EmptyView {
                    self.init(
                        id: id,
                        class: extra
                    ) {
                        EmptyView()
                    }
                }

                static var tag: WebUICore.Tag? {
                    .div
                }

                static var base: ClassName {
                    .init("form-grid2")
                }
            }

            extension FormGrid2: StyledElement {
            }
            """
        )
    }
}

// MARK: - the macro refuses input with a diagnostic, never a trap

@Suite("StyledElement macro diagnostics")
struct StyledElementMacroDiagnosticTests {

    @Test("a non-struct host is diagnosed")
    func nonStructHostDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            enum NotAStruct {
            }
            """
        )
        #expect(messages.contains("@StyledElement can only be applied to a struct"), "got \(messages)")
    }

    @Test("a host without one generic parameter is diagnosed")
    func missingGenericParameterDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            struct NoGenerics {
            }
            """
        )
        #expect(
            messages.contains(
                "@StyledElement needs exactly one generic `: View` parameter for the element's children, e.g. `struct SetRow<Content: View>`"
            ),
            "got \(messages)"
        )
    }

    @Test("a missing tag is diagnosed")
    func missingTagDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement()
            struct NoTag<Content: View> {
            }
            """
        )
        #expect(
            messages.contains("@StyledElement requires a tag: `@StyledElement(.div, class: .setRow)`"),
            "got \(messages)"
        )
    }
}

// MARK: - @Part refuses what it cannot render, with a diagnostic

@Suite("Part macro diagnostics")
struct PartMacroDiagnosticTests {

    @Test("@Part outside a @StyledElement host is diagnosed")
    func partOutsideAHostDiagnosed() throws {
        // the host is not a `@StyledElement`, and the expansion context carries
        // the lexical scope the macro reads — the same way the compiler's
        // plugin host supplies it. `file.expand` would carry no lexical context
        // and no parent chain here, which is the "cannot be read" case the
        // macro skips rather than guesses.
        let source = """
            struct NotAHost<Content: View> {
                @Part(.h1, class: .detailTitle) var title: String = ""
            }
            """
        let file = Parser.parse(source: source)
        let structDecl = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
        let variable = try #require(
            structDecl.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let attribute = try #require(variable.attributes.first?.as(AttributeSyntax.self))

        let context = BasicMacroExpansionContext(lexicalContext: [Syntax(structDecl)])
        _ = try PartMacro.expansion(of: attribute, providingPeersOf: variable, in: context)

        #expect(
            context.diagnostics.map { $0.message }.contains(
                "@Part must be declared inside a `@StyledElement` host: nothing else reads the marker"
            ),
            "got \(context.diagnostics.map { $0.message })"
        )
    }

    @Test("@Part inside a @StyledElement host is not diagnosed")
    func partInsideAHostIsAccepted() throws {
        let source = """
            @StyledElement(.div)
            struct Card<Content: View> {
                @Part(.h1) var title: String = ""
            }
            """
        let file = Parser.parse(source: source)
        let structDecl = try #require(file.statements.first?.item.as(StructDeclSyntax.self))
        let variable = try #require(
            structDecl.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let attribute = try #require(variable.attributes.first?.as(AttributeSyntax.self))

        let context = BasicMacroExpansionContext(lexicalContext: [Syntax(structDecl)])
        let peers = try PartMacro.expansion(of: attribute, providingPeersOf: variable, in: context)

        #expect(peers.isEmpty)
        #expect(context.diagnostics.isEmpty, "got \(context.diagnostics.map { $0.message })")
    }

    @Test("@Part on a let is diagnosed")
    func partOnALetDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            struct Card<Content: View> {
                @Part(.h1) let title: String
            }
            """
        )
        #expect(
            messages.contains("@Part marks a stored `var`: a `let` is not offered to a call site"),
            "got \(messages)"
        )
    }

    @Test("@Part on a computed property is diagnosed")
    func partOnAComputedPropertyDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            struct Card<Content: View> {
                @Part(.h1) var title: String { "constant" }
            }
            """
        )
        #expect(
            messages.contains("@Part marks a stored property: `title` is computed, so a call site has no value to set"),
            "got \(messages)"
        )
    }

    @Test("@Part on a non-String property is diagnosed")
    func partOnANonStringPropertyDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            struct Card<Content: View> {
                @Part(.h1) var level: Int = 1
            }
            """
        )
        #expect(
            messages.contains("@Part renders its value as text: `level` is `Int`, not `String` or `String?`"),
            "got \(messages)"
        )
    }

    @Test("@Part on a function is diagnosed")
    func partOnAFunctionDiagnosed() {
        let messages = emittedDiagnostics(
            """
            @StyledElement(.div)
            struct Card<Content: View> {
                @Part(.h1) func title() -> String { "constant" }
            }
            """
        )
        #expect(
            messages.contains("@Part can only be applied to a stored property"),
            "got \(messages)"
        )
    }
}
