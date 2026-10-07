import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
import WebUIServerMacros

// the automated half of d-h — the generated shape is reviewed as API, and
// that taste is an enforced invariant here, not a prose rule:
//   • no `func` nested inside another `func`'s body;
//   • no `: ()` Void-marker parameters;
//   • initializer values emitted directly (no immediately-invoked closures).
//
// plus the appendix-D.2 re-expansion parse gate: every frozen fixture is
// re-expanded through the raw expander, must re-parse cleanly, and must emit
// ZERO diagnostics (a positive fixture that starts warning fails here).

/// collects shape violations in a parsed Swift tree.
private final class ShapeScanner: SyntaxVisitor {
	var violations: [String] = []

	init() {
		super.init(viewMode: .sourceAccurate)
	}

	override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
		var ancestor = node.parent
		while let current = ancestor {
			if current.is(FunctionDeclSyntax.self) {
				violations.append("a 'func' nested inside another func ('\(node.name.text)')")
				break
			}
			ancestor = current.parent
		}
		return .visitChildren
	}

	override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
		if let tuple = node.type.as(TupleTypeSyntax.self), tuple.elements.isEmpty {
			violations.append("a Void-marker parameter ': ()' on '\(node.firstName.text)'")
		}
		return .visitChildren
	}

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		if node.calledExpression.is(ClosureExprSyntax.self) {
			violations.append("an immediately-invoked closure \\(…)() — an initializer value must be emitted directly")
		}
		return .visitChildren
	}
}

private func assertShapeGate(_ expanded: String) {
	let file = Parser.parse(source: expanded)
	#expect(!file.hasError, "the frozen expansion does not parse")
	let scanner = ShapeScanner()
	scanner.walk(file)
	#expect(scanner.violations.isEmpty, "shape violations: \(scanner.violations)")
}

private func assertParseGate(_ fixture: FrozenFixture) {
	let file = Parser.parse(source: fixture.source)
	let context = BasicMacroExpansionContext()
	let expanded = file.expand(macros: liveMacroSpecs, contextGenerator: { _ in context })
	// a positive fixture must expand clean: zero diagnostics from the macro.
	#expect(context.diagnostics.isEmpty, "expected a diagnostic-free expansion; got \(context.diagnostics.map(\.message))")
	// the re-expansion parse gate: the generated source must parse cleanly.
	let reparsed = Parser.parse(source: expanded.description)
	#expect(!reparsed.hasError, "the generated source does not parse cleanly")
}

@Suite("the shape gate — generated code is reviewed as API (d-h)")
struct ShapeGateTests {
	@Test(arguments: frozenFixtures)
	func generatedShapePassesTheReviewGate(fixture: FrozenFixture) {
		assertShapeGate(fixture.expanded)
	}
}

@Suite("the re-expansion parse gate (appendix D.2)")
struct ParseGateTests {
	@Test(arguments: frozenFixtures)
	func reexpansionParsesCleanly(fixture: FrozenFixture) {
		assertParseGate(fixture)
	}
}
