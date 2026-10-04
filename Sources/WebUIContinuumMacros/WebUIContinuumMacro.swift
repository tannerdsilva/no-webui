import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - shared argument parsing
//
// the continuum macros share one argument shape: unlabeled string literals
// (`@HotView("feed")`, `@HotClass("feed-item", "feed-item__meta")`). anything else
// is a misuse — diagnosed with the accepted spelling so the fix is one read away.
// every refusal below is a diagnostic (`MacroExpansionErrorMessage`, reported with
// file/line at the attribute); none of them traps (AGENTS.md rule).

private func stringArguments(of node: AttributeSyntax) throws -> [String] {
	guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
		return []
	}
	var values: [String] = []
	for argument in arguments {
		guard argument.label == nil else {
			throw MacroExpansionErrorMessage(
				"continuum macros take unlabeled string literals — pass the names positionally, not as labeled arguments"
			)
		}
		guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
			let value = literal.representedLiteralValue
		else {
			throw MacroExpansionErrorMessage(
				"continuum macros take string literals only, e.g. @HotView(\"feed\") or @HotClass(\"feed-item\")"
			)
		}
		values.append(value)
	}
	return values
}

/// a sibling `@HotClass(...)` on the same declaration contributes the descriptor's
/// class vocabulary. read off the attribute (not the emitted member) so each macro
/// stays independently useful — `@HotView` without `@HotClass` emits an empty class.
private func siblingHotClasses(on declaration: some DeclGroupSyntax) -> [String] {
	var classes: [String] = []
	for attribute in declaration.attributes {
		guard case .attribute(let attribute) = attribute else { continue }
		guard attribute.attributeName.trimmedDescription == "HotClass" else { continue }
		// the sibling's own expansion diagnoses malformed arguments; a miss here
		// degrades to the empty vocabulary, never to a crash.
		if let values = try? stringArguments(of: attribute) {
			classes += values
		}
	}
	return classes
}

// MARK: - @HotView argument parsing

/// the accepted spelling, quoted verbatim in every argument-related diagnostic.
private let hotViewSpelling =
	"@HotView(\"feed\") or @HotView(\"feed\", imports: [ClockCapability.self], budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096))"

/// the parsed `@HotView(...)` argument list. `imports`/`budget` keep the raw
/// expression so the expansion copies the author's own spelling (the generated
/// members sit in the same file, so the copied expression resolves identically).
private struct HotViewArguments {
	let name: String
	let imports: ExprSyntax?
	/// `imports:` written as a literally empty array — equivalent to absent, and
	/// the only spelling that is (so "imports ⇒ budget" cannot false-positive on it).
	let importsIsEmpty: Bool
	let budget: ExprSyntax?
}

/// the one misuse of `imports:` the type checker cannot phrase kindly: wire
/// strings (or other non-metatype values). conformance itself is enforced by the
/// parameter type (`[any HostCapability.Type]`), at the use site.
private let importsFixHint =
	"imports: takes HostCapability types, not wire strings or values — write imports: [ClockCapability.self]; a capability's wireName is its wire spelling"

private func isEmptyArrayLiteral(_ expression: ExprSyntax) -> Bool {
	guard let array = expression.as(ArrayExprSyntax.self) else { return false }
	return array.elements.isEmpty
}

private func validateImports(_ expression: ExprSyntax) throws {
	if expression.is(StringLiteralExprSyntax.self) {
		throw MacroExpansionErrorMessage(importsFixHint)
	}
	guard let array = expression.as(ArrayExprSyntax.self) else { return }
	for element in array.elements {
		let value = element.expression
		if value.is(StringLiteralExprSyntax.self)
			|| value.is(IntegerLiteralExprSyntax.self)
			|| value.is(FloatLiteralExprSyntax.self)
			|| value.is(BooleanLiteralExprSyntax.self) {
			throw MacroExpansionErrorMessage(importsFixHint)
		}
	}
}

private func hotViewArguments(of node: AttributeSyntax) throws -> HotViewArguments {
	guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
		throw MacroExpansionErrorMessage("@HotView requires the island name — as \(hotViewSpelling)")
	}
	var name: String?
	var imports: ExprSyntax?
	var budget: ExprSyntax?
	for argument in arguments {
		switch argument.label?.text {
		case nil:
			guard name == nil else {
				throw MacroExpansionErrorMessage(
					"@HotView takes exactly one island name — the first, unlabeled argument; capabilities go in imports: and the pin in budget:"
				)
			}
			guard let literal = argument.expression.as(StringLiteralExprSyntax.self),
				let value = literal.representedLiteralValue
			else {
				throw MacroExpansionErrorMessage(
					"continuum macros take string literals only, e.g. @HotView(\"feed\") or @HotClass(\"feed-item\")"
				)
			}
			name = value
		case "imports":
			guard imports == nil else {
				throw MacroExpansionErrorMessage("@HotView takes at most one imports: argument")
			}
			try validateImports(argument.expression)
			imports = argument.expression
		case "budget":
			guard budget == nil else {
				throw MacroExpansionErrorMessage("@HotView takes at most one budget: argument")
			}
			budget = argument.expression
		case .some(let label):
			throw MacroExpansionErrorMessage(
				"unknown @HotView argument `\(label):` — the accepted spelling is \(hotViewSpelling)"
			)
		}
	}
	guard let name else {
		throw MacroExpansionErrorMessage("@HotView requires the island name — as \(hotViewSpelling)")
	}
	return HotViewArguments(
		name: name,
		imports: imports,
		importsIsEmpty: imports.map(isEmptyArrayLiteral) ?? true,
		budget: budget
	)
}

// MARK: - declaration checks

/// the members the generated adapter forwards: nested `State`/`Action` types or
/// typealiases. a source-level check (the macro has no type information) — the
/// conformance itself (`HotState`/`HotAction`) is the type checker's business.
private func stateActionNames(in declaration: some DeclGroupSyntax) -> Set<String> {
	var names: Set<String> = []
	for member in declaration.memberBlock.members {
		let decl = member.decl
		if let alias = decl.as(TypeAliasDeclSyntax.self) {
			names.insert(alias.name.text)
		} else if let nested = decl.as(StructDeclSyntax.self) {
			names.insert(nested.name.text)
		} else if let nested = decl.as(EnumDeclSyntax.self) {
			names.insert(nested.name.text)
		} else if let nested = decl.as(ClassDeclSyntax.self) {
			names.insert(nested.name.text)
		} else if let associated = decl.as(AssociatedTypeDeclSyntax.self) {
			names.insert(associated.name.text)
		}
	}
	return names
}

private func missingStateActionMessage(in declaration: some DeclGroupSyntax) -> String? {
	let declared = stateActionNames(in: declaration)
	let missing = ["State", "Action"].filter { !declared.contains($0) }
	guard !missing.isEmpty else { return nil }
	let list = missing.map { "`\($0)`" }.joined(separator: " and ")
	return "@HotView requires \(list) — declare `typealias State = …` (a HotState) / `typealias Action = …` (a HotAction); the generated island adapter forwards them"
}

/// the hot body must be `@HotBuilder func render(state: …)`. found + annotated →
/// nil; missing or unannotated → the fix hint.
private func renderBuilderMessage(in declaration: some DeclGroupSyntax) -> String? {
	var found = false
	var hasBuilder = false
	for member in declaration.memberBlock.members {
		guard let function = member.decl.as(FunctionDeclSyntax.self) else { continue }
		guard function.name.text == "render" else { continue }
		let parameters = function.signature.parameterClause.parameters
		guard parameters.count == 1, parameters.first?.firstName.text == "state" else { continue }
		found = true
		for attribute in function.attributes {
			guard case .attribute(let attribute) = attribute else { continue }
			if attribute.attributeName.trimmedDescription == "HotBuilder" {
				hasBuilder = true
			}
		}
	}
	guard found else {
		return "@HotView requires the hot body — declare `@HotBuilder func render(state: State) -> HotTree { … }`"
	}
	guard hasBuilder else {
		return "@HotView: render(state:) must be @HotBuilder — annotate it so the body is type-checked against the hot vocabulary (Hot.Text, Hot.Container, Hot.Spacer)"
	}
	return nil
}

// MARK: - the budget: tightening rule (CONTINUUM_DX W2, lane D)
//
// DX-3 measurement-fed budgets (§2.3): `budget:` is TIGHTENING-ONLY — the
// measured auto-pin (the DX-3 `maxBytes`/`raw`/`gz`/`sha` row lane B writes
// alongside every cross-built island) is the default; a DECLARED pin is
// honored as a ceiling and may only be TIGHTER than it. the remembered
// `imports:→budget:` rule retires: non-empty `imports:` auto-defaults the
// budget and no longer requires a declared pin (the sentinel
// `IslandBudget(maxBytes: 0, maxGzipBytes: nil)` is the "auto/unset" marker —
// the budget plugin reads the manifest, not this declaration).
// the tighter-than-measured COMPARISON needs lane B's measured rows, which
// are enforced build-side (BudgetDriftTests "declarations are tightening-only"
// + the plugin); the macro-side contribution here is the tightening-
// READINESS guard: a declared pin that can never be a legal tightening
// (a 0-byte pin = the auto spelling taken as a real pin, or a
// non-literal/non-positive value) is refused with the fix hint.

/// `budget:` when declared must be a legal tightening pin — a positive
/// `maxBytes:` integer literal (and `maxGzipBytes:` positive or absent). a
/// declared `maxBytes: 0` is the auto/unset spelling mistakenly written as a
/// pin — omit `budget:` instead. nil = valid.
private func declaredBudgetMessage(arguments: HotViewArguments) -> String? {
	guard let budget = arguments.budget else { return nil }
	// a budget expression must spell `IslandBudget(maxBytes: <pos>, ...)`.
	let text = budget.trimmedDescription
	guard let maxBytes = text.firstMatch(of: /maxBytes\s*:\s*(\d+)/) else {
		return "@HotView: budget: must be an IslandBudget pin with a positive integer maxBytes: — e.g. budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096) (budget: is tightening-only; omit it to auto-pin from the measured row)"
	}
	let raw = String(maxBytes.1)
	guard let value = Int(raw), value > 0 else {
		return "@HotView: a declared maxBytes: of 0 is the auto/unset spelling, not a pin — omit budget: (the measured auto-pin applies); if you meant a ceiling, declare a positive maxBytes:"
	}
	if let gz = text.firstMatch(of: /maxGzipBytes\s*:\s*(\d+)/) {
		let gzValue = Int(String(gz.1)) ?? 0
		guard gzValue > 0 else {
			return "@HotView: a declared maxGzipBytes: of 0 is the auto/unset spelling, not a pin — omit maxGzipBytes: (nil auto-defaults) or declare a positive value"
		}
	}
	return nil
}

// MARK: - registry markers final (CONTINUUM_DX W2, lane D)
//
// the strict `@HotView("name")` marker form the continuum scan consumes
// (`WebUIContinuumTool.hotViewMarkers` parses the name as the FIRST quoted
// token of the attribute body): the name must be a single ASCII token because
// it becomes (a) the wasm export suffix `<name>_encode`/`<name>_decode`,
// (b) the served URL segment, (c) the manifest `islands[]` key. whitespace,
// punctuation, quotes, and non-ASCII are refused here so the scan's text pass
// can never mis-split a marker. ambiguity/duplicate at the declaration level
// (a doubled attribute, or a generated member colliding with an author-declared
// one) is a build error with a fix hint — never `fatalError` (AGENTS.md).

/// ASCII-letter test for the strict token form (no Foundation — the macro
/// target's host surface is swift-syntax only).
private func isAsciiLetter(_ s: Unicode.Scalar) -> Bool {
	(0x41 ... 0x5A).contains(s.value) || (0x61 ... 0x7A).contains(s.value)
}

private func isAsciiDigit(_ s: Unicode.Scalar) -> Bool {
	(0x30 ... 0x39).contains(s.value)
}

/// the strict single-token name check; nil = valid.
private func strictIslandNameMessage(_ name: String) -> String? {
	let scalars = Array(name.unicodeScalars)
	guard let first = scalars.first, isAsciiLetter(first) || first == "_" else {
		return "@HotView: the island name must be a single token starting with a letter or underscore, e.g. @HotView(\"feed\") — \"\(name)\" does not; it becomes the wasm export suffix, the URL segment, and the manifest key"
	}
	for scalar in scalars.dropFirst() {
		if !(isAsciiLetter(scalar) || isAsciiDigit(scalar) || scalar == "-" || scalar == "_") {
			return "@HotView: the island name must be a single token of letters, digits, '-' and '_' (the strict marker form the registry scan consumes) — \"\(name)\" contains '\(Character(scalar))'; it becomes the wasm export suffix, the URL segment, and the manifest key"
		}
	}
	return nil
}

/// two `@HotView` attributes on one declaration = a duplicate registry marker.
private func duplicateHotViewMessage(on declaration: some DeclGroupSyntax) -> String? {
	var count = 0
	for attribute in declaration.attributes {
		guard case .attribute(let attribute) = attribute else { continue }
		if attribute.attributeName.trimmedDescription == "HotView" { count += 1 }
	}
	guard count > 1 else { return nil }
	return "@HotView applied \(count) times — one declaration registers exactly one island; remove the duplicate attribute (pick the one name)"
}

/// the generated members (`continuumDescriptor`, the island adapter struct)
/// would redeclare author-declared members: fail with a fix hint instead of
/// the compiler's raw redeclaration error.
private func memberCollisionMessage(in declaration: some DeclGroupSyntax, adapterName: String) -> String? {
	for member in declaration.memberBlock.members {
		let decl = member.decl
		let name: String?
		if let alias = decl.as(TypeAliasDeclSyntax.self) { name = alias.name.text }
		else if let nested = decl.as(StructDeclSyntax.self) { name = nested.name.text }
		else if let nested = decl.as(EnumDeclSyntax.self) { name = nested.name.text }
		else if let nested = decl.as(ClassDeclSyntax.self) { name = nested.name.text }
		else if let variable = decl.as(VariableDeclSyntax.self) {
			name = variable.bindings.first?.pattern.trimmedDescription
		} else { name = nil }
		guard let name else { continue }
		if name == "continuumDescriptor" {
			return "@HotView: your declared `static let continuumDescriptor` would collide with the generated one — @HotView emits it; remove yours (or drop @HotView and hand-write the ContinuumServerPath conformance)"
		}
		if name == adapterName {
			return "@HotView: your declared `\(adapterName)` would collide with the generated island adapter — @HotView emits it; rename your member (the generated adapter is named `\(adapterName)`)"
		}
		if name == "elementIDs" {
			return "@HotView: your declared `static let elementIDs` would collide with the generated DX-9 id vocabulary — @HotView walks the @HotBuilder body and emits it; remove yours (or drop @HotView and hand-write the ContinuumServerPath conformance)"
		}
	}
	return nil
}

// MARK: - DX-9 — the macro-emitted element-id vocabulary (CONTINUUM_DX §2.9)
//
// the literal-only walk of the @HotBuilder body: every `id:` argument spelled
// as a string literal (`Hot.Text(id: "feed-status", …)`, `Hot.Container(id:
// "panel", …)`, `Hot.KeyedList(id: "feed", …)`, …) — or as the spelled
// `ElementID("…")` literal form — is collected into the generated
// `static let elementIDs: Set<ElementID>`, the macro-emitted mirror of the
// hand-kept `ProbeIslandIDs` pattern (d-docs §DX-9).
//
// the LITERAL-ONLY boundary: interpolated / dynamic ids (`ElementID("t-\(key)")`,
// key-derived `-k<key>` list ids) are NOT statically knowable — they defer to
// the runtime dev check's `isKnownElementID` family, never to compile time.
// over-collection is permissive-safe (the dev check ignores ids the island
// never emits); a missed literal is the only bug class — and this walk is the
// whole-value collection, so a missed literal is a body rewrite that drops the
// call, not a walk bug.
private final class ElementIDLiteralCollector: SyntaxVisitor {
	var ids: Set<String> = []

	init() {
		super.init(viewMode: .sourceAccurate)
	}

	override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
		for argument in node.arguments {
			guard argument.label?.text == "id" else { continue }
			collectID(from: argument.expression)
		}
		return .visitChildren
	}

	private func collectID(from expression: ExprSyntax) {
		// the plain literal: `id: "feed-status"`. `representedLiteralValue` is
		// nil for interpolated segments — the literal-only boundary, enforced
		// by the syntax node, not by a re-resolution.
		if let literal = expression.as(StringLiteralExprSyntax.self),
			let value = literal.representedLiteralValue {
			ids.insert(value)
			return
		}
		// the spelled form: `id: ElementID("feed-status")`.
		if let call = expression.as(FunctionCallExprSyntax.self),
			call.calledExpression.trimmedDescription == "ElementID",
			let argument = call.arguments.first,
			let literal = argument.expression.as(StringLiteralExprSyntax.self),
			let value = literal.representedLiteralValue {
			ids.insert(value)
		}
	}
}

/// the literal `id:` values the `@HotBuilder render(state:)` body spells, in
/// sorted order (deterministic emission; the expansion suite pins the exact
/// text).
private func renderBodyElementIDs(in declaration: some DeclGroupSyntax) -> [String] {
	for member in declaration.memberBlock.members {
		guard let function = member.decl.as(FunctionDeclSyntax.self) else { continue }
		guard function.name.text == "render" else { continue }
		guard function.signature.parameterClause.parameters.count == 1 else { continue }
		guard let body = function.body else { continue }
		let collector = ElementIDLiteralCollector()
		collector.walk(body)
		return Array(collector.ids).sorted()
	}
	return []
}

// MARK: - the plan (shared by both macro roles)

/// everything both roles emit from: parsed + validated once, so the peer role
/// (export shims) and the extension role (descriptor + adapter) cannot drift.
private struct HotViewPlan {
	let name: String
	let typeName: String
	let islandName: String
	let islandQualifiedName: String
	let className: String
	let access: String
	let grantsSource: String
	let budgetSource: String
	/// DX-9: the literal `id:` values the render body spells, sorted (may be
	/// empty — the always-emitted declaration still carries the vocabulary).
	let elementIDs: [String]
}

private func hotViewPlan(of node: AttributeSyntax, on structDecl: StructDeclSyntax) throws -> HotViewPlan {
	let arguments = try hotViewArguments(of: node)
	guard !arguments.name.isEmpty else {
		throw MacroExpansionErrorMessage("@HotView requires a non-empty island name — as @HotView(\"feed\")")
	}
	if let message = strictIslandNameMessage(arguments.name) {
		throw MacroExpansionErrorMessage(message)
	}
	if let message = duplicateHotViewMessage(on: structDecl) {
		throw MacroExpansionErrorMessage(message)
	}
	let typeName = structDecl.name.text
	if let message = memberCollisionMessage(in: structDecl, adapterName: typeName + "Island") {
		throw MacroExpansionErrorMessage(message)
	}
	if let message = declaredBudgetMessage(arguments: arguments) {
		throw MacroExpansionErrorMessage(message)
	}
	if let message = missingStateActionMessage(in: structDecl) {
		throw MacroExpansionErrorMessage(message)
	}
	if let message = renderBuilderMessage(in: structDecl) {
		throw MacroExpansionErrorMessage(message)
	}
	return HotViewPlan(
		name: arguments.name,
		typeName: typeName,
		islandName: typeName + "Island",
		islandQualifiedName: "\(typeName).\(typeName)Island",
		className: siblingHotClasses(on: structDecl).joined(separator: " "),
		access: structDecl.modifiers.contains { $0.name.text == "public" } ? "public " : "",
		// the copied expressions; the sentinel budget is the wave-1 "unset" value
		// the name-only signature has always emitted (additive).
		grantsSource: arguments.imports?.trimmedDescription ?? "[]",
		budgetSource: arguments.budget?.trimmedDescription ?? "IslandBudget(maxBytes: 0, maxGzipBytes: nil)",
		elementIDs: renderBodyElementIDs(in: structDecl)
	)
}

/// the fragment appended to the shim prefixes: the compiler requires peer names
/// at global scope to derive from the attached declaration's name (`prefixed(p)`
/// covers `p` + the annotated name — verified against the compiler), so the
/// export shims for `struct Feed` are `_continuumEncodeFeed`/`_continuumDecodeFeed`.
private func shimName(_ prefix: String, _ typeName: String) -> String {
	prefix + typeName
}

/// the `static let elementIDs` value: the literal ids as a `Set<ElementID>`
/// literal (`[]` when the render body spells none — the always-emitted
/// declaration still carries the vocabulary, so a check build fails loudly on
/// any op instead of silently passing an undeclared island).
private func elementIDsSource(_ ids: [String]) -> String {
	guard !ids.isEmpty else { return "[]" }
	let linePrefix = String(repeating: "\t", count: 3)
	let lines = ids.map { linePrefix + "ElementID(\"" + $0 + "\")" }
	return "[\n" + lines.joined(separator: ",\n") + "\n\t\t]"
}

// MARK: - HotClassMacro

/// `@HotClass("a", "b")` — declares a component's class vocabulary. the single
/// generated member is `static let continuumClasses: [String]`, the inventory the
/// registry scan and the attr lint (DESKTOP_GRADE §1.5) read. additive only: a
/// hand-written `static let continuumClasses` is the no-macro path and stays valid.
public struct HotClassMacro: MemberMacro {

	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw MacroExpansionErrorMessage(
				"@HotClass can only be applied to a struct (a component); move the class vocabulary onto the component type"
			)
		}
		let classes = try stringArguments(of: node)
		guard !classes.isEmpty else {
			throw MacroExpansionErrorMessage(
				"@HotClass requires at least one class name — as @HotClass(\"feed-item\", \"feed-item__meta\")"
			)
		}
		let access = structDecl.modifiers.contains { $0.name.text == "public" } ? "public " : ""
		let list = classes.map { "\"\($0)\"" }.joined(separator: ", ")
		let member: DeclSyntax = "\(raw: access)static let continuumClasses: [String] = [\(raw: list)]"
		return [member]
	}
}

// MARK: - HotViewMacro

/// `@HotView("feed", imports: […], budget: …)` — one declaration, both paths
/// (server + island). two roles, one plan:
///
/// - the *extension* role emits `static let continuumDescriptor` (name/grants/
///   budget/class, greppable), `struct <Type>Island: ContinuumIsland` (adapter:
///   `reduce` forwards, `State`/`Action` alias, `imports`/`budget` carry the
///   declared values, `_continuumEncode`/`_continuumDecode` are the island-side
///   codec entry points — bodies land with the island runtime slice), and the
///   `ContinuumServerPath` conformance;
/// - the *peer* role emits the `@_expose(wasm, "<name>_encode"/"<name>_decode")`
///   export shims as GLOBAL functions — `@_expose` rejects non-global placement
///   (verified against the compiler), so the statics alone cannot carry it.
///
/// generated members reference the seam vocabulary by name; the expansion is pure
/// declaration text and adds no runtime work the declaration does not state. it
/// synthesizes no `Codable` and never routes state through `JSONEncoder`/`Decoder`
/// — the island path carries values with `JSONValue` + `HotOpCodec` (the
/// embed-Codable gate, `c-to-d.md`).
///
/// the extension role owns the refusal diagnostics; the peer role validates
/// through the same plan and emits nothing when the declaration is invalid (one
/// clear error, no dangling shims).
public struct HotViewMacro: ExtensionMacro, PeerMacro {

	public static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingExtensionsOf type: some TypeSyntaxProtocol,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [ExtensionDeclSyntax] {
		guard let structDecl = declaration.as(StructDeclSyntax.self) else {
			throw MacroExpansionErrorMessage(
				"@HotView can only be applied to a struct (the hot view); move the attribute onto the view type"
			)
		}
		let plan = try hotViewPlan(of: node, on: structDecl)

		let extensionDecl: DeclSyntax =
			"""
			extension \(raw: plan.typeName): ContinuumServerPath {
			\t\(raw: plan.access)static let continuumDescriptor = ContinuumDescriptor(
			\t\tname: "\(raw: plan.name)",
			\t\tgrants: \(raw: plan.grantsSource),
			\t\tbudget: \(raw: plan.budgetSource),
			\t\tclassName: "\(raw: plan.className)"
			\t)

			\t\(raw: plan.access)struct \(raw: plan.islandName): ContinuumIsland {
			\t\t\(raw: plan.access)typealias State = \(raw: plan.typeName).State
			\t\t\(raw: plan.access)typealias Action = \(raw: plan.typeName).Action
					\(raw: plan.access)static var name: String { "\(raw: plan.name)" }
					\(raw: plan.access)static var imports: [any HostCapability.Type] { \(raw: plan.grantsSource) }
					\(raw: plan.access)static var budget: IslandBudget { \(raw: plan.budgetSource) }

					// DX-9 vocabulary (CONTINUUM_DX §2.9, lane D): the literal `id:`
					// arguments of the @HotBuilder body — the macro-emitted mirror of the
					// hand-kept ProbeIslandIDs pattern (d-docs §DX-9). the runtime's
					// CONTINUUM_ID_CHECK dev check reads this; interpolated/dynamic ids
					// defer to isKnownElementID and are never collected here.
					\(raw: plan.access)static let elementIDs: Set<ElementID> = \(raw: elementIDsSource(plan.elementIDs))

					\(raw: plan.access)static func reduce(state: inout State, action: Action) -> [HotEffect] {
			\t\t\t\(raw: plan.typeName).reduce(state: &state, action: action)
			\t\t}

					// t2.3 codec entry points (CONTINUUM_DX W3, lane D — the swap-in, d-to-c.md W3):
					// the runtime slice owns the retained state per wasm instance; the generated
					// adapter reads the BOUND runtime instance through lane C's W3 accessors —
					// `IslandRuntime<<Type>Island>.encodedState()` (the exact webui_state_save
					// payload) / `.decodePendingOps()` (the pending records, decode-only — never
					// drains). host/native builds never bind a runtime, so the statics report the
					// drained contract ([], no effects). the macro emits a ContinuumIsland-only
					// adapter; the spell requires the adapter to satisfy IslandRuntimeSurface at
					// the use site — author-supplied (the template-feed shape, c-to-d W3 item 3).
					\(raw: plan.access)static func _continuumEncode() -> [UInt8] {
						IslandRuntime<\(raw: plan.islandQualifiedName)>.encodedState()
					}

					\(raw: plan.access)static func _continuumDecode() -> [HotEffect] {
						IslandRuntime<\(raw: plan.islandQualifiedName)>.decodePendingOps()
					}
			\t}
			}
			"""

		guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
			throw MacroExpansionErrorMessage("@HotView could not synthesize the island + server adapter extension")
		}
		return [parsed]
	}

	public static func expansion(
		of node: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		// the extension role owns the refusal diagnostics; an invalid declaration
		// produces no peers (the build still fails once, with the fix hint).
		guard let structDecl = declaration.as(StructDeclSyntax.self),
			let plan = try? hotViewPlan(of: node, on: structDecl)
		else {
			return []
		}
		let encodeName = shimName("_continuumEncode", plan.typeName)
		let decodeName = shimName("_continuumDecode", plan.typeName)
		let encode: DeclSyntax =
			"""
			@_expose(wasm, "\(raw: plan.name)_encode")
			func \(raw: encodeName)() -> [UInt8] {
				\(raw: plan.islandQualifiedName)._continuumEncode()
			}
			"""
		let decode: DeclSyntax =
			"""
			@_expose(wasm, "\(raw: plan.name)_decode")
			func \(raw: decodeName)() -> [HotEffect] {
				\(raw: plan.islandQualifiedName)._continuumDecode()
			}
			"""
		return [encode, decode]
	}
}