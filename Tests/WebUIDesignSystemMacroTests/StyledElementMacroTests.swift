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
    return context.diagnostics.map(\.message)
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

                public static var tag: Tag {
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

                static var tag: Tag {
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

                static var tag: Tag {
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
