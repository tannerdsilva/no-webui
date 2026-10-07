import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import WebUIServerMacros

// the live-data macro suite's shared assertions.
//
// `assertMacroExpansion` defaults its failure handler to XCTFail, which is a
// no-op under Swift Testing — every mismatch would be silently swallowed and
// reported PASS. the handler below records a real Swift Testing `Issue`, so a
// divergence in the emitted text fails the suite. the default-handler variant
// is BANNED in this target.

public let liveMacroSpecs: [String: Macro.Type] = [
	"LiveRegion": LiveRegionMacro.self,
	"RegionState": RegionStateMarker.self,
	"LiveRegions": LiveRegionsMacro.self,
	"LiveState": LiveStateMacro.self,
]

/// assert the exact expansion text, with a failure handler that can fail.
func assertExpansion(
	_ source: String,
	expanded expected: String
) {
	assertMacroExpansion(
		source,
		expandedSource: expected,
		macroSpecs: liveMacroSpecs.mapValues { MacroSpec(type: $0) },
		failureHandler: { spec in Issue.record(Comment(stringLiteral: spec.message)) }
	)
}

/// assert a misuse produces the expected diagnostic message. uses the raw
/// expander and compares messages (position-immune): `assertMacroExpansion`'s
/// `DiagnosticSpec` binds line/column, and member-macro diagnostics thrown
/// during expansion are not captured by it at all.
func assertExpansionDiagnoses(_ source: String, message: String) {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	_ = file.expand(macros: liveMacroSpecs, contextGenerator: { _ in context })
	let messages = context.diagnostics.map(\.message)
	#expect(messages.contains(message), "expected diagnostic \(String(reflecting: message)); got \(messages)")
}

/// assert a misuse produces the expected diagnostic message with WARNING
/// severity (feature B: duplicates warn, non-literal ids say so — they are
/// not errors, and the suite must not let a warning silently become an error).
func assertExpansionWarns(_ source: String, message: String) {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	_ = file.expand(macros: liveMacroSpecs, contextGenerator: { _ in context })
	let matching = context.diagnostics.filter { $0.message == message }
	#expect(!matching.isEmpty, "expected warning \(String(reflecting: message)); got \(context.diagnostics.map(\.message))")
	for diagnostic in matching {
		#expect(diagnostic.diagMessage.severity == .warning,
			"'\(message)' must be a WARNING, not an error")
	}
}

/// the raw expansion as text — the "assert by name" half: a member name must be
/// present in the expansion regardless of formatting drift.
func expandedText(of source: String) -> String {
	let file = Parser.parse(source: source)
	let context = BasicMacroExpansionContext()
	return file.expand(macros: liveMacroSpecs, contextGenerator: { _ in context }).description
}