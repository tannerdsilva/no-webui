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
	let budget: ExprSyntax?
}

/// the one misuse of `imports:` the type checker cannot phrase kindly: wire
/// strings (or other non-metatype values). conformance itself is enforced by the
/// parameter type (`[any HostCapability.Type]`), at the use site.
private let importsFixHint =
	"imports: takes HostCapability types, not wire strings or values — write imports: [ClockCapability.self]; a capability's wireName is its wire spelling"

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
					"@HotView takes exactly one island name — the first, unlabeled argument; capabilities go in imports: (budget: is an optional tightening pin)"
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

/// budget diagnostics (DX-3, W2): the `imports:` ⇒ `budget:` requirement
/// **retired** — non-empty `imports:` auto-defaults the budget (the build
/// auto-pins it from the measurement). the only remaining budget diagnostic
/// is the *tighter-than-measured* refusal: a declared pin below the measured
/// auto-pin can never hold. it needs lane B's measured row (`maxBytes/raw/gz/
/// sha` per island in the work-dir manifest — b-docs:571–573 handoff), which
/// is not on the tree at W2-D start; until it lands the comparison stays
/// dormant and the macro is strictly additive (defined in d-docs.md +
/// d-to-b.md, no refusal emitted).

// MARK: - the plan (shared by both macro roles)

/// everything both roles emit from: parsed + validated once, so the peer role
/// (export shims) and the extension role (descriptor + adapter) cannot drift.
///
/// budget semantics (DX-3, W2): `budget:` is a **tightening-only** ceiling —
/// the build measures every island and auto-pins `maxBytes`/`maxGzipBytes`
/// (measured × 1.05) into `ContinuumManifest.json`'s `islands[]` (lane B), so
/// a declaration that names host imports no longer needs a pin: non-empty
/// `imports:` **auto-defaults** the budget (the wave-1 sentinel
/// `IslandBudget(maxBytes: 0, maxGzipBytes: nil)` is the auto marker the
/// build substitutes the measured pin for). the only budget diagnostic that
/// remains is the *tighter-than-measured* refusal — a declared pin below the
/// measured auto-pin can never hold — and it compares against the measured
/// row B exposes (`maxBytes/raw/gz/sha` per island in the work-dir manifest;
/// handoff b-docs:571–573). that row is not on the tree at W2-D start, so the
/// comparison is defined-but-dormant: the macro emits the declared pin
/// verbatim and adds no refusal (the additive reading — continuum-notes/
/// d-docs.md + d-to-b.md carry the definition and the dependency).
private struct HotViewPlan {
	let name: String
	let typeName: String
	let islandName: String
	let islandQualifiedName: String
	let className: String
	let access: String
	let grantsSource: String
	let budgetSource: String
}

private func hotViewPlan(of node: AttributeSyntax, on structDecl: StructDeclSyntax) throws -> HotViewPlan {
	let arguments = try hotViewArguments(of: node)
	guard !arguments.name.isEmpty else {
		throw MacroExpansionErrorMessage("@HotView requires a non-empty island name — as @HotView(\"feed\")")
	}
	if let message = missingStateActionMessage(in: structDecl) {
		throw MacroExpansionErrorMessage(message)
	}
	if let message = renderBuilderMessage(in: structDecl) {
		throw MacroExpansionErrorMessage(message)
	}
	let typeName = structDecl.name.text
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
		budgetSource: arguments.budget?.trimmedDescription ?? "IslandBudget(maxBytes: 0, maxGzipBytes: nil)"
	)
}

/// the fragment appended to the shim prefixes: the compiler requires peer names
/// at global scope to derive from the attached declaration's name (`prefixed(p)`
/// covers `p` + the annotated name — verified against the compiler), so the
/// export shims for `struct Feed` are `_continuumEncodeFeed`/`_continuumDecodeFeed`.
private func shimName(_ prefix: String, _ typeName: String) -> String {
	prefix + typeName
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
///   codec entry points, delegating to the runtime slice's shared record codec
///   — the codec the reactor's state/op channels drain (`HotOpCodec`); the
///   live-core binding is the runtime-accessor handoff, `continuum-notes/d-to-c.md`),
///   and the `ContinuumServerPath` conformance;
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
			\t\t\(raw: plan.access)static var name: String { "\(raw: plan.name)" }
			\t\t\(raw: plan.access)static var imports: [any HostCapability.Type] { \(raw: plan.grantsSource) }
			\t\t\(raw: plan.access)static var budget: IslandBudget { \(raw: plan.budgetSource) }

			\t\t\(raw: plan.access)static func reduce(state: inout State, action: Action) -> [HotEffect] {
			\t\t\t\(raw: plan.typeName).reduce(state: &state, action: action)
			\t\t}

					// the island-side codec entry points (t2.3 ABI): delegations to the
					// runtime slice's record codec (`HotOpCodec`, WebUISharedCore) — the
					// codec the reactor's state/op channels drain. the live core (retained
					// state + queued op records) is owned by `IslandRuntimeCore` inside
					// WebUIIslandCore; at the adapter's static scope the drained frame is
					// served: encode yields the canonical empty record stream, decode
					// yields no pending effects. the live-core binding is the
					// runtime-accessor handoff (continuum-notes/d-to-c.md).
					\(raw: plan.access)static func _continuumEncode() -> [UInt8] {
						(try? HotOpCodec.encodeBatch([])) ?? []
					}

					\(raw: plan.access)static func _continuumDecode() -> [HotEffect] {
						(try? HotOpCodec.decode([])).map { [.ops([$0])] } ?? []
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