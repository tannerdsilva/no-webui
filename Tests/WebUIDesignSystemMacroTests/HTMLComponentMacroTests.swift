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
