import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @LiveRegions
//
// the property list IS the registry. the macro must be a MemberMacro: the
// assembly is defined by the member list, and an attached peer/body macro
// receives a member-less type shell (probe-verified; see swift-macro-development),
// so no other role can see it.
//
// classification is SYNTACTIC and stated, because a macro sees syntax and never
// types: a property is a REGION when its written type — or its initializer's
// callee — names a region type (a nested type carrying @LiveRegion, or one of
// the framework's two region constructors), and it is SKIPPED when that name is
// a known state (a nested @LiveState type, LiveBox, LiveNotifier). anything
// else is diagnosed rather than guessed: silently dropping a region is the
// region-never-pushes failure this arc exists to remove.

public struct LiveRegionsMacro: MemberMacro {
	private static let regionConstructors: Set<String> = ["ClosureLiveRegion", "StateLiveRegion"]
	private static let stateConstructors: Set<String> = ["LiveBox", "LiveNotifier"]

	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard declaration.as(StructDeclSyntax.self) != nil || declaration.as(ClassDeclSyntax.self) != nil else {
			throw MacroExpansionErrorMessage("@LiveRegions can only be applied to a struct or class")
		}

		let nested = nestedTypes(in: declaration)
		let regionTypeNames = Set(nested.filter { $0.attributes.contains("LiveRegion") }.map(\.name))
		let stateTypeNames = Set(nested.filter { $0.attributes.contains("LiveState") }.map(\.name))

		var regions: [String] = []
		for member in declaration.memberBlock.members {
			guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
			let isStatic = variable.modifiers.contains { $0.name.text == "static" || $0.name.text == "class" }
			guard !isStatic else { continue }
			for binding in variable.bindings {
				guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
				let name = identifier.identifier.text
				guard let typeName = candidateTypeName(of: binding) else {
					throw MacroExpansionErrorMessage(
						"@LiveRegions cannot tell whether '\(name)' is a live region — give it an explicit type (`let \(name): SomeRegionType = …`), or move it out of the group"
					)
				}
				if regionTypeNames.contains(typeName) || regionConstructors.contains(typeName) {
					regions.append(name)
				} else if stateTypeNames.contains(typeName) || stateConstructors.contains(typeName) {
					continue
				} else {
					throw MacroExpansionErrorMessage(
						"@LiveRegions cannot tell whether '\(name)' ('\(typeName)') is a live region — a region type carries @LiveRegion, a state type carries @LiveState; anything else does not belong in the group"
					)
				}
			}
		}

		guard !regions.isEmpty else {
			throw MacroExpansionErrorMessage(
				"@LiveRegions found zero region properties — an empty registry is a silent mistake"
			)
		}

		warnOnDuplicateIDs(in: declaration, regions: regions, context: context)

		let access = accessPrefix(for: declaration)
		let list = regions.joined(separator: ", ")
		let member: DeclSyntax = "\(raw: access)var registry: WebUILiveRegions { WebUILiveRegions([\(raw: list)]) }"
		return [member]
	}

	/// the macro can compare the literal `id:` arguments it can see; where it
	/// cannot read one, it says so. duplicates are a warning — the registry
	/// keeps the last definition and drops the earlier one's order slot.
	private static func warnOnDuplicateIDs(
		in declaration: some DeclGroupSyntax,
		regions: [String],
		context: some MacroExpansionContext
	) {
		var seen: [String: String] = [:]
		for member in declaration.memberBlock.members {
			let decl = member.decl
			if let attributeList = decl.as(StructDeclSyntax.self)?.attributes
				?? decl.as(ClassDeclSyntax.self)?.attributes
				?? decl.as(ActorDeclSyntax.self)?.attributes
				?? decl.as(EnumDeclSyntax.self)?.attributes {
				for attribute in attributeList.compactMap({ $0.as(AttributeSyntax.self) })
				where attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "LiveRegion" {
					guard let id = literalIDArgument(of: attribute) else { continue }
					check(id: id, against: &seen, at: Syntax(attribute), context: context)
				}
			}
			guard let variable = decl.as(VariableDeclSyntax.self) else { continue }
			for binding in variable.bindings {
				guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
				let name = identifier.identifier.text
				guard regions.contains(name),
				      let call = binding.initializer?.value.as(FunctionCallExprSyntax.self)
				else { continue }
				for argument in call.arguments where argument.label?.text == "id" {
					if let id = stringLiteralValue(argument.expression) {
						check(id: id, against: &seen, at: Syntax(binding), context: context)
					} else {
						context.diagnose(Diagnostic(
							node: Syntax(binding),
							message: MacroExpansionWarningMessage(
								"@LiveRegions cannot compare '\(name)''s id — it is not a string literal, so a duplicate would go unnoticed"
							)
						))
					}
				}
			}
		}
	}

	private static func check(
		id: String,
		against seen: inout [String: String],
		at node: Syntax,
		context: some MacroExpansionContext
	) {
		if let first = seen[id] {
			context.diagnose(Diagnostic(
				node: node,
				message: MacroExpansionWarningMessage(
					"duplicate live-region id '\(id)' — already used by \(first); the registry keeps the last definition"
				)
			))
		} else {
			seen[id] = "an earlier member"
		}
	}
}