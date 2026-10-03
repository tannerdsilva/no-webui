import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import WebUI
@testable import WebUIContinuumMacros

// the continuum macro suite's shared assertions.
//
// `assertMacroExpansion` defaults its failure handler to XCTFail, which is a
// no-op under Swift Testing — every mismatch would be silently swallowed and
// reported PASS. the handler below records a real Swift Testing `Issue` so a
// divergence in the emitted text fails the suite.

public let continuumMacroSpecs: [String: Macro.Type] = [
	"HotView": HotViewMacro.self,
	"HotClass": HotClassMacro.self,
]

public func assertExpansion(
	_ source: String,
	expanded expected: String
) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: continuumMacroSpecs.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// asserts a misuse throws the expected message. uses the raw expander and
/// compares diagnostic messages (position-immune) — `assertMacroExpansion`'s
/// `DiagnosticSpec` binds line/column, which shift across swift-syntax
/// generations for identical source.
public func assertExpansionThrows(_ source: String, message: String) {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	_ = file.expand(macros: continuumMacroSpecs, contextGenerator: { _ in context })
	let messages = context.diagnostics.map(\.message)
	#expect(messages.contains(message), "expected diagnostic \(String(reflecting: message)); got \(messages)")
}

/// the raw expansion as text — the "assert by name" half of the checks: a member
/// name must be present in the expansion regardless of exact formatting drift.
public func expandedText(of source: String) -> String {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	return file.expand(macros: continuumMacroSpecs, contextGenerator: { _ in context }).description
}
