import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - shared argument parsing

/// the continuum macros share one argument shape: unlabeled string literals
/// (`@HotView("feed")`, `@HotClass("feed-item", "feed-item__meta")`). anything else
/// is a misuse — diagnosed with the accepted spelling so the fix is one read away.
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

/// `@HotView` wave-1 signature is name-only: exactly one unlabeled string literal.
private func singleNameArgument(of node: AttributeSyntax) throws -> String {
	let values = try stringArguments(of: node)
	guard values.count == 1 else {
		throw MacroExpansionErrorMessage(
			"@HotView takes exactly one argument — the island name, as @HotView(\"feed\")"
		)
	}
	return values[0]
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

/// `@HotView("feed")` — one declaration, both paths (server + island). wave-1
/// signature is name-only; the `imports:`/`budget:` parameters and the view-side
/// runtime protocols arrive in wave 2. the generated extension carries:
///
/// - `static let continuumDescriptor` — name/grants/budget/class, greppable;
/// - `struct <Type>Island: ContinuumIsland` — the adapter. `reduce` forwards to the
///   author's `reduce`; `State`/`Action` alias the view's;
/// - `@_expose(wasm, …)` codec shims — the t2.3 export names (bodies land with the
///   codec, lane C);
/// - the `ContinuumServerPath` conformance — the server adapter.
///
/// generated members reference the seam vocabulary by name only. the output is pure
/// declaration text: it adds no runtime work the declaration does not state.
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
		let name = try singleNameArgument(of: node)
		guard !name.isEmpty else {
			throw MacroExpansionErrorMessage(
				"@HotView requires a non-empty island name — as @HotView(\"feed\")"
			)
		}

		let typeName = type.trimmedDescription
		let islandName = typeName + "Island"
		let className = siblingHotClasses(on: declaration).joined(separator: " ")
		let access = structDecl.modifiers.contains { $0.name.text == "public" } ? "public " : ""

		let extensionDecl: DeclSyntax =
			"""
			extension \(raw: typeName): ContinuumServerPath {
			\t\(raw: access)static let continuumDescriptor = ContinuumDescriptor(
			\t\tname: "\(raw: name)",
			\t\tgrants: [],
			\t\tbudget: IslandBudget(maxBytes: 0, maxGzipBytes: nil),
			\t\tclassName: "\(raw: className)"
			\t)

			\t\(raw: access)struct \(raw: islandName): ContinuumIsland {
			\t\t\(raw: access)typealias State = \(raw: typeName).State
			\t\t\(raw: access)typealias Action = \(raw: typeName).Action
			\t\t\(raw: access)static var name: String { "\(raw: name)" }
			\t\t\(raw: access)static var imports: [any HostCapability.Type] { [] }
			\t\t\(raw: access)static var budget: IslandBudget { \(raw: typeName).continuumDescriptor.budget }

			\t\t\(raw: access)static func reduce(state: inout State, action: Action) -> [HotEffect] {
			\t\t\t\(raw: typeName).reduce(state: &state, action: action)
			\t\t}

			\t\t// island exports. the @_expose names are the t2.3 ABI contract;
			// bodies land with the codec once lane C's record table is in.
			\t\t@_expose(wasm, "\(raw: name)_encode")
			\t\t\(raw: access)static func _continuumEncode() -> [UInt8] { [] }

			\t\t@_expose(wasm, "\(raw: name)_decode")
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
