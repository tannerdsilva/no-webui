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
//
// the emitted shape is a discriminator (`ContentKind` + `kind`) plus one storage
// per content case: a `String` for a text case, the host's own generic parameter
// for a builder case. no payload is erased — that is the whole point of the
// generic content migration.

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

                private enum ContentKind {
                    case label
                }

                private let kind: ContentKind

                private let label: String

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.kind = .label
                    self.label = label
                }
            }
            """
        )
    }

    @Test("text case plus builder case: the builder rides the host's generic")
    func textAndBuilder() {
        assertExpansion(
            """
            @HTMLComponent(.text("label", unlabeled: true), .builder("views"))
            struct ArcButton<Views: View> {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton<Views: View> {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum ContentKind {
                    case label
                    case views
                }

                private let kind: ContentKind

                private let label: String

                private let views: Views

                init(_ label: String, id: String? = nil) where Views == EmptyView {
                    self.id = id
                    self.kind = .label
                    self.label = label
                    self.views = EmptyView()
                }

                init(id: String? = nil, @ElementBuilder views: () -> Views) {
                    self.id = id
                    self.kind = .views
                    self.label = ""
                    self.views = views()
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

                private enum ContentKind {
                    case label
                }

                private let kind: ContentKind

                private let label: String

                init(_ label: String, id: String? = nil, disabled: Bool = false) {
                    self.id = id
                    self.disabled = disabled
                    self.kind = .label
                    self.label = label
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
                var derived: String { "x" }
            }
            """,
            expanded: """
            struct ArcButton {
                var id: String? = nil
                var body: some View { EmptyView() }
                var derived: String { "x" }

                private enum ContentKind {
                    case label
                }

                private let kind: ContentKind

                private let label: String

                init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.kind = .label
                    self.label = label
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
            struct ArcButton<Views: View> {
                var id: String? = nil
                var body: some View { EmptyView() }
            }
            """,
            expanded: """
            struct ArcButton<Views: View> {
                var id: String? = nil
                var body: some View { EmptyView() }

                private enum ContentKind {
                    case title
                    case label
                    case views
                }

                private let kind: ContentKind

                private let title: String

                private let label: String

                private let views: Views

                init(_ label: String, id: String? = nil) where Views == EmptyView {
                    self.id = id
                    self.kind = .label
                    self.title = ""
                    self.label = label
                    self.views = EmptyView()
                }

                init(title: String, id: String? = nil) where Views == EmptyView {
                    self.id = id
                    self.kind = .title
                    self.title = title
                    self.label = ""
                    self.views = EmptyView()
                }

                init(id: String? = nil, @ElementBuilder views: () -> Views) {
                    self.id = id
                    self.kind = .views
                    self.title = ""
                    self.label = ""
                    self.views = views()
                }
            }
            """
        )
    }

    @Test("two builder cases: one generic parameter each, unused ones pinned")
    func twoBuilderCases() {
        assertExpansion(
            """
            @HTMLComponent(.builder("header"), .builder("body"))
            struct Shell<Header: View, Body: View> {
                var id: String? = nil
            }
            """,
            expanded: """
            struct Shell<Header: View, Body: View> {
                var id: String? = nil

                private enum ContentKind {
                    case header
                    case body
                }

                private let kind: ContentKind

                private let header: Header

                private let body: Body

                init(id: String? = nil, @ElementBuilder header: () -> Header) where Body == EmptyView {
                    self.id = id
                    self.kind = .header
                    self.header = header()
                    self.body = EmptyView()
                }

                init(id: String? = nil, @ElementBuilder body: () -> Body) where Header == EmptyView {
                    self.id = id
                    self.kind = .body
                    self.header = EmptyView()
                    self.body = body()
                }
            }
            """
        )
    }

    @Test("three builder cases keep declaration order in both storage and inits")
    func threeBuilderCases() {
        assertExpansion(
            """
            @HTMLComponent(.builder("leading"), .builder("content"), .builder("trailing"))
            struct Row<Leading: View, Content: View, Trailing: View> {
                var gap: Int = 0
            }
            """,
            expanded: """
            struct Row<Leading: View, Content: View, Trailing: View> {
                var gap: Int = 0

                private enum ContentKind {
                    case leading
                    case content
                    case trailing
                }

                private let kind: ContentKind

                private let leading: Leading

                private let content: Content

                private let trailing: Trailing

                init(gap: Int = 0, @ElementBuilder leading: () -> Leading) where Content == EmptyView, Trailing == EmptyView {
                    self.gap = gap
                    self.kind = .leading
                    self.leading = leading()
                    self.content = EmptyView()
                    self.trailing = EmptyView()
                }

                init(gap: Int = 0, @ElementBuilder content: () -> Content) where Leading == EmptyView, Trailing == EmptyView {
                    self.gap = gap
                    self.kind = .content
                    self.leading = EmptyView()
                    self.content = content()
                    self.trailing = EmptyView()
                }

                init(gap: Int = 0, @ElementBuilder trailing: () -> Trailing) where Leading == EmptyView, Content == EmptyView {
                    self.gap = gap
                    self.kind = .trailing
                    self.leading = EmptyView()
                    self.content = EmptyView()
                    self.trailing = trailing()
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

    @Test("a builder case with no generic parameter on the host is rejected")
    func builderWithoutGenericThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent(.builder("views"))
            struct ArcButton {
                var id: String? = nil
            }
            """,
            message: "@HTMLComponent declares 1 builder case(s) but the host declares 0 generic parameter(s) — one `: View` parameter per builder case, in declaration order"
        )
    }

    @Test("more builder cases than generic parameters is rejected")
    func tooFewGenericsThrows() {
        assertExpansionThrows(
            """
            @HTMLComponent(.builder("header"), .builder("body"))
            struct Shell<Header: View> {
                var id: String? = nil
            }
            """,
            message: "@HTMLComponent declares 2 builder case(s) but the host declares 1 generic parameter(s) — one `: View` parameter per builder case, in declaration order"
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
            struct ArcButton<Views: View> {
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

                private enum ContentKind {
                    case label
                }

                private let kind: ContentKind

                private let label: String

                init(_ label: String, action: @escaping () -> Void) {
                    self.action = action
                    self.kind = .label
                    self.label = label
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

                private enum ContentKind {
                    case label
                }

                private let kind: ContentKind

                private let label: String

                package init(_ label: String, id: String? = nil) {
                    self.id = id
                    self.kind = .label
                    self.label = label
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

    @Test("a property named kind is rejected")
    func reservedKindPropertyRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                var kind: String = ""
            }
            """,
            message: "'kind' is @HTMLComponent's discriminator — rename the property"
        )
    }

    @Test("a nested ContentKind type is rejected")
    func reservedContentKindTypeRejected() {
        assertExpansionThrows(
            """
            @HTMLComponent(.text("label"))
            struct Panel {
                enum ContentKind { case a }
            }
            """,
            message: "'ContentKind' is @HTMLComponent's discriminator enum — rename the nested type"
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
