import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import WebUIDesignSystem
@testable import WebUIDesignSystemMacros

// MARK: - strict expansion helper

private func assertExpansion(
    _ source: String,
    expanded expected: String,
    macros: [String: Macro.Type] = [
        "HTMLComponent": ComponentMacro.self,
    ]
) {
    assertMacroExpansion(
        source,
        expandedSource: expected,
        macroSpecs: macros.mapValues { MacroSpec(type: $0) },
        failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
    )
}

private func assertExpansionThrows(_ source: String, message: String) {
    let file = Parser.parse(source: source)
    let context = BasicMacroExpansionContext()
    _ = file.expand(
        macros: ["HTMLComponent": ComponentMacro.self],
        contextGenerator: { _ in context }
    )
    let messages = context.diagnostics.map(\.message)
    #expect(messages.contains(message), "expected diagnostic \(String(reflecting: message)); got \(messages)")
}

// MARK: - expansion fixtures

@Suite("@HTMLComponent macro expansion")
struct HTMLComponentMacroExpansionTests {

    @Test("single text case, unlabeled")
    func textCaseUnlabeled() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum Content {
                    case label(String)
                }

                private let content: Content

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.content = .label(label)
                }
            }
            """
        )
    }

    @Test("text case plus builder case")
    func textAndBuilder() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true), .builder("views"))
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum Content {
                    case label(String)
                    case views([any WebUI.View])
                }

                private let content: Content

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.content = .label(label)
                }

                init(id: String? = nil, @ViewBuilder views: () -> [any WebUI.View]) {
                    self.id = id
                    self.content = .views(views())
                }
            }
            """
        )
    }

    @Test("shared property with default expression")
    func defaultExpressionPreserved() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            struct ArcButton {
                var id: String? = nil
                var disabled: Bool = false
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var disabled: Bool = false
                var body: some View { EmptyView() }

                private enum Content {
                    case label(String)
                }

                private let content: Content

                init(_ label: String, id: String? = nil, disabled: Bool = false) {
                    self.id = id
                    self.disabled = disabled
                    self.content = .label(label)
                }
            }
            """
        )
    }

    @Test("computed property is skipped")
    func computedPropertySkipped() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum Content {
                    case label(String)
                }

                private let content: Content

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.content = .label(label)
                }
            }
            """
        )
    }

    @Test("canonical ordering: unlabeled first, then labeled, then builder")
    func canonicalOrdering() {
        assertExpansion(
            """
            @HTMLComponent(.text("title"), .text("label", unlabeled: true), .builder("views"))
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum Content {
                    case title(String)
                    case label(String)
                    case views([any WebUI.View])
                }

                private let content: Content

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.content = .label(label)
                }

                init(title: String, id: String? = nil) {
                    self.id = id
                    self.content = .title(title)
                }

                init(id: String? = nil, @ViewBuilder views: () -> [any WebUI.View]) {
                    self.id = id
                    self.content = .views(views())
                }
            }
            """
        )
    }
}

// MARK: - negative cases

@Suite("@HTMLComponent macro misuse")
struct HTMLComponentMacroNegativeTests {

    @Test("zero cases throws")
    func zeroCasesThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent()
            struct ArcButton {
                var id: String? = nil
            }
            """,
            message: "@HTMLComponent requires at least one content case"
        )
    }

    @Test("two builders throw")
    func twoBuildersThrow() {
        assertExpansionThrows(
            """
            @HTMLComponent(.builder("a"), .builder("b"))
            struct ArcButton {
                var id: String? = nil
            }
            """,
            message: "@HTMLComponent declares 2 builder cases; at most one is allowed"
        )
    }

    @Test("duplicate case names throw")
    func duplicateCaseNamesThrow() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("x"), .text("x"))
            struct ArcButton {
                var id: String? = nil
            }
            """,
            message: "content case 'x' is declared more than once"
        )
    }

    @Test("unlabeled on builder throws")
    func unlabeledOnBuilderThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent(.builder("views", unlabeled: true))
            struct ArcButton {
                var id: String? = nil
            }
            """,
            message: "unlabeled: is only valid on .text cases, not .builder"
        )
    }

    @Test("stored property without type annotation throws")
    func missingTypeAnnotationThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            struct ArcButton {
                var id = nil
            }
            """,
            message: "stored property 'id' has no type annotation — @HTMLComponent requires an explicit type"
        )
    }

    @Test("non-struct host throws")
    func nonStructHostThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            class ArcButton {
                var id: String? = nil
            }
            """,
            message: "@HTMLComponent can only be applied to a struct"
        )
    }
}

// MARK: - shapes the macro must widen or reject
//
// each case here was a compile error in *generated* code (or a silently wrong
// emission) before the macro learned to see it. the assertion is the message,
// because the diagnostic is the whole point: the author should never have to
// read a macro expansion to find out what went wrong.

@Suite("@HTMLComponent hardening")
struct HTMLComponentHardeningTests {

    @Test("a closure-typed property is @escaping on the generated parameter")
    func closurePropertyIsEscaping() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            struct Panel {
                var action: () -> Void
            }
            """,
            expanded: """
            struct Panel {
                var action: () -> Void

                private enum Content {
                    case label(String)
                }

                private let content: Content

                init(_ label: String, action: @escaping () -> Void) {
                    self.action = action
                    self.content = .label(label)
                }
            }
            """
        )
    }

    @Test("a package struct gets a package init")
    func packageAccessPropagates() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true))
            package struct Panel {
                var id: String? = nil
            }
            """,
            expanded: """
            package struct Panel {
                var id: String? = nil

                private enum Content {
                    case label(String)
                }

                private let content: Content

                package init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.content = .label(label)
                }
            }
            """
        )
    }

    @Test("a case name that is not an identifier is rejected")
    func nonIdentifierCaseNameRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("a b"))
            struct Panel {
                var id: String? = nil
            }
            """,
            message: "content case 'a b' is not a valid Swift identifier"
        )
    }

    @Test("a case name colliding with a property is rejected")
    func casePropertyCollisionRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                var label: String = ""
            }
            """,
            message: "content case 'label' collides with the stored property of the same name — one of them needs a different name"
        )
    }

    @Test("a property named content is rejected")
    func reservedContentPropertyRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                var content: String = ""
            }
            """,
            message: "'content' is @HTMLComponent's storage — rename the property"
        )
    }

    @Test("a nested Content type is rejected")
    func reservedContentTypeRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                enum Content { case a }
            }
            """,
            message: "'Content' is @HTMLComponent's enum — rename the nested type"
        )
    }

    @Test("a property carrying an attribute is rejected")
    func attributedPropertyRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                @MainActor var id: String? = nil
            }
            """,
            message: "stored property 'id' carries an attribute that @HTMLComponent cannot re-emit on a generated parameter"
        )
    }

    @Test("a non-literal unlabeled value is rejected")
    func nonLiteralUnlabeledRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label", unlabeled: flag))
            struct Panel {
                var id: String? = nil
            }
            """,
            message: "unlabeled: requires a boolean literal (true or false)"
        )
    }
}
