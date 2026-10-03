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

/// a declaration that names host imports is a sized island: the budget pin is
/// mandatory (`WebUIBudgetPlugin` enforces the generated pin before ship).
private func missingBudgetMessage(arguments: HotViewArguments) -> String? {
	guard arguments.imports != nil, !arguments.importsIsEmpty, arguments.budget == nil else { return nil }
	return "@HotView: missing budget: — a declaration that names host imports is a sized island; add budget: IslandBudget(maxBytes: 16_384, maxGzipBytes: 4_096) (the budget plugin pins it before ship)"
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
/// (server + island). the generated extension carries:
///
/// - `static let continuumDescriptor` — name/grants/budget/class, greppable;
/// - `struct <Type>Island: ContinuumIsland` — the adapter. `reduce` forwards to the
///   author's `reduce`; `State`/`Action` alias the view's; `imports`/`budget`
///   carry the declared values;
/// - `@_expose(wasm, …)` codec shims — the t2.3 export names (`<name>_encode` /
///   `<name>_decode`; bodies land with the island runtime slice);
/// - the `ContinuumServerPath` conformance — the server adapter.
///
/// generated members reference the seam vocabulary by name; the expansion is pure
/// declaration text and adds no runtime work the declaration does not state. it
/// synthesizes no `Codable` and never routes state through `JSONEncoder`/`Decoder`
/// — the island path carries values with `JSONValue` + `HotOpCodec` (the
/// embed-Codable gate, `c-to-d.md`).
public struct HotViewMacro: ExtensionMacro {

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
		let arguments = try hotViewArguments(of: node)
		guard !arguments.name.isEmpty else {
			throw MacroExpansionErrorMessage(
				"@HotView requires a non-empty island name — as @HotView(\"feed\")"
			)
		}
		if let message = missingBudgetMessage(arguments: arguments) {
			throw MacroExpansionErrorMessage(message)
		}
		if let message = missingStateActionMessage(in: declaration) {
			throw MacroExpansionErrorMessage(message)
		}
		if let message = renderBuilderMessage(in: declaration) {
			throw MacroExpansionErrorMessage(message)
		}

		let typeName = type.trimmedDescription
		let islandName = typeName + "Island"
		let className = siblingHotClasses(on: declaration).joined(separator: " ")
		let access = structDecl.modifiers.contains { $0.name.text == "public" } ? "public " : ""

		// the copied expressions; the sentinel budget is the wave-1 "unset" value
		// the name-only signature has always emitted (additive).
		let grantsSource = arguments.imports?.trimmedDescription ?? "[]"
		let budgetSource = arguments.budget?.trimmedDescription
			?? "IslandBudget(maxBytes: 0, maxGzipBytes: nil)"

		let extensionDecl: DeclSyntax =
			"""
			extension \(raw: typeName): ContinuumServerPath {
			\t\(raw: access)static let continuumDescriptor = ContinuumDescriptor(
			\t\tname: "\(raw: arguments.name)",
			\t\tgrants: \(raw: grantsSource),
			\t\tbudget: \(raw: budgetSource),
			\t\tclassName: "\(raw: className)"
			\t)

			\t\(raw: access)struct \(raw: islandName): ContinuumIsland {
			\t\t\(raw: access)typealias State = \(raw: typeName).State
			\t\t\(raw: access)typealias Action = \(raw: typeName).Action
			\t\t\(raw: access)static var name: String { "\(raw: arguments.name)" }
			\t\t\(raw: access)static var imports: [any HostCapability.Type] { \(raw: grantsSource) }
			\t\t\(raw: access)static var budget: IslandBudget { \(raw: budgetSource) }

			\t\t\(raw: access)static func reduce(state: inout State, action: Action) -> [HotEffect] {
			\t\t\t\(raw: typeName).reduce(state: &state, action: action)
			\t\t}

			\t\t// island exports. the @_expose names are the t2.3 ABI contract;
			\t\t// bodies land with the island runtime slice (the frame-buffer op loop).
			\t\t@_expose(wasm, "\(raw: arguments.name)_encode")
			\t\t\(raw: access)static func _continuumEncode() -> [UInt8] { [] }

			\t\t@_expose(wasm, "\(raw: arguments.name)_decode")
			\t\t\(raw: access)static func _continuumDecode() -> [HotEffect] { [] }
			\t}
			}
			"""

		guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
			throw MacroExpansionErrorMessage("@HotView could not synthesize the island + server adapter extension")
		}
		return [parsed]
	}
}