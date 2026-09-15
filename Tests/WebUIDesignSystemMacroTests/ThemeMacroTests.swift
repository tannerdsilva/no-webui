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
//
// `assertMacroExpansion` defaults its failure handler to XCTFail, which is a
// no-op under Swift Testing — every mismatch would be silently swallowed and
// reported PASS. the handler below records a real Swift Testing `Issue` so a
// divergence in the emitted text fails the suite.

private func assertExpansion(
	_ source: String,
	expanded expected: String,
	macros: [String: Macro.Type] = ["Theme": WebUIThemeMacro.self]
) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: macros.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// asserts a misuse throws the expected message. uses the raw expander and
/// compares diagnostic messages (position-immune) — `assertMacroExpansion`'s
/// `DiagnosticSpec` binds line/column, which shift across swift-syntax
/// generations for identical source.
private func assertExpansionThrows(_ source: String, message: String) {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	_ = file.expand(macros: ["Theme": WebUIThemeMacro.self], contextGenerator: { _ in context })
	let messages = context.diagnostics.map(\.message)
	#expect(messages.contains(message), "expected diagnostic \(String(reflecting: message)); got \(messages)")
}

// MARK: - expansion fixtures

@Suite("@Theme macro expansion")
struct ThemeMacroExpansionTests {

	@Test("full theme: tokens, scheme, rules, customTokens")
	func fullTheme() {
		assertExpansion(
			"""
			@Theme
			struct NexusDark {
				static let scheme = ColorScheme.dark
				static let rules: [CSSRule] = [.chatBubble, .streamDots]
				static let customTokens = ["--chat-user-bubble": "#2a2a2e"]
				static let colorPrimarySolid = "#6c8cff"
				static let colorBg = "#101014"
			}
			""",
			expanded: """
			struct NexusDark {
				static let scheme = ColorScheme.dark
				static let rules: [CSSRule] = [.chatBubble, .streamDots]
				static let customTokens = ["--chat-user-bubble": "#2a2a2e"]
				static let colorPrimarySolid = "#6c8cff"
				static let colorBg = "#101014"
			}

			extension NexusDark: WebUIThemeProvider {
				static var theme: WebUITheme {
					WebUITheme(
						tokens: [.colorPrimarySolid: colorPrimarySolid, .colorBg: colorBg],
						customTokens: customTokens,
						scheme: scheme,
						rules: rules
					)
				}
			}
			"""
		)
	}

	@Test("bare struct emits an empty token bag and a conformance")
	func bareStruct() {
		assertExpansion(
			"""
			@Theme
			struct Bare {
			}
			""",
			expanded: """
			struct Bare {
			}

			extension Bare: WebUIThemeProvider {
				static var theme: WebUITheme {
					WebUITheme(
						tokens: []
					)
				}
			}
			"""
		)
	}

	@Test("scheme-only theme omits the undeclared axes")
	func schemeOnly() {
		assertExpansion(
			"""
			@Theme
			struct DarkOnly {
				static let scheme = ColorScheme.dark
			}
			""",
			expanded: """
			struct DarkOnly {
				static let scheme = ColorScheme.dark
			}

			extension DarkOnly: WebUIThemeProvider {
				static var theme: WebUITheme {
					WebUITheme(
						tokens: [],
						scheme: scheme
					)
				}
			}
			"""
		)
	}

	@Test("tokens-only theme emits tokens without the special axes")
	func tokensOnly() {
		assertExpansion(
			"""
			@Theme
			struct Tokens {
				static let colorText = "#e7ecf5"
				static let colorTextMuted = "#97a3b8"
			}
			""",
			expanded: """
			struct Tokens {
				static let colorText = "#e7ecf5"
				static let colorTextMuted = "#97a3b8"
			}

			extension Tokens: WebUIThemeProvider {
				static var theme: WebUITheme {
					WebUITheme(
						tokens: [.colorText: colorText, .colorTextMuted: colorTextMuted]
					)
				}
			}
			"""
		)
	}

	@Test("a public struct gets a public theme witness")
	func publicStruct() {
		assertExpansion(
			"""
			@Theme
			public struct PublicTheme {
				static let colorBg = "#101014"
			}
			""",
			expanded: """
			public struct PublicTheme {
				static let colorBg = "#101014"
			}

			extension PublicTheme: WebUIThemeProvider {
				public static var theme: WebUITheme {
					WebUITheme(
						tokens: [.colorBg: colorBg]
					)
				}
			}
			"""
		)
	}
}

// MARK: - negative cases

@Suite("@Theme macro misuse")
struct ThemeMacroNegativeTests {

	@Test("non-struct targets throw")
	func nonStructThrows() {
		assertExpansionThrows(
			"""
			@Theme
			class NotAStruct {
			}
			""",
			message: "@Theme can only be applied to a struct"
		)
	}

	@Test("instance members throw")
	func instanceMemberThrows() {
		assertExpansionThrows(
			"""
			@Theme
			struct HasInstance {
				static let colorPrimarySolid = "#6c8cff"
				let colorBackground = "#101014"
			}
			""",
			message: "@Theme member 'colorBackground' must be a 'static let' declaration"
		)
	}

	@Test("static vars throw")
	func staticVarThrows() {
		assertExpansionThrows(
			"""
			@Theme
			struct HasVar {
				static var colorPrimarySolid: String = "#6c8cff"
			}
			""",
			message: "@Theme member 'colorPrimarySolid' must be a 'static let' declaration"
		)
	}
}
