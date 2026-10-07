import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @LiveRegion
//
// a struct declares what it IS (id, cadence, its state source) and what it
// renders; the conformance, `id`, `cadence` and the `source` hook are
// generated. two of the three documented footguns die here: `source` becomes a
// marked property (a property the author writes anyway), and `id` can no
// longer disagree with the DOM id it replaces — there is one spelling.
//
// the conformance itself comes from the extension role (a member macro cannot
// declare conformances — swift-syntax 603 MemberMacro docs); the member role
// supplies the witnesses, and the notifier storage `@LiveState` needs is
// likewise a member, because an extension cannot add stored properties.

/// `@LiveRegion(id:cadence:)` — the region declaration macro.
public struct LiveRegionMacro: MemberMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard declaration.as(StructDeclSyntax.self) != nil
			|| declaration.as(ClassDeclSyntax.self) != nil
			|| declaration.as(ActorDeclSyntax.self) != nil
		else {
			throw MacroExpansionErrorMessage(
				"@LiveRegion can only be applied to a struct, class or actor"
			)
		}

		var id: String?
		var cadence: String?
		if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
			for argument in arguments {
				switch argument.label?.text {
				case "id":
					guard let value = stringLiteralValue(argument.expression) else {
						throw MacroExpansionErrorMessage(
							"@LiveRegion(id:) must be a string literal — the id is the DOM id and the pushed fragment id, stated once"
						)
					}
					id = value
				case "cadence":
					cadence = argument.expression.trimmedDescription
				default:
					break
				}
			}
		}
		guard let id else {
			throw MacroExpansionErrorMessage("@LiveRegion requires an id: argument")
		}

		let declared = declaredNames(of: declaration)
		for reserved in ["id", "cadence", "source"] where declared.contains(reserved) {
			throw MacroExpansionErrorMessage(
				"@LiveRegion generates '\(reserved)' — a hand-written '\(reserved)' on the same type is ambiguous; remove it"
			)
		}
		if !declared.contains("render") {
			throw MacroExpansionErrorMessage(
				"@LiveRegion requires the type to declare 'func render() async -> String?' in its body (a member added in an extension is invisible to this macro)"
			)
		}

		let markers = markedPropertyNames("RegionState", in: declaration)
		if markers.count > 1 {
			throw MacroExpansionErrorMessage(
				"@RegionState marks \(markers.count) properties (\(markers.joined(separator: ", "))) — exactly one, or none, is allowed"
			)
		}

		let access = accessPrefix(for: declaration)
		var members: [DeclSyntax] = []
		members.append("\(raw: access)var id: String { \"\(raw: id)\" }")
		if let cadence {
			members.append("\(raw: access)var cadence: Duration? { \(raw: cadence) }")
		} else {
			members.append("\(raw: access)var cadence: Duration? { nil }")
		}
		if let marked = markers.first {
			members.append("\(raw: access)var source: (any LiveState)? { \(raw: marked) }")
		} else {
			members.append("\(raw: access)var source: (any LiveState)? { nil }")
		}
		return members
	}
}

extension LiveRegionMacro: ExtensionMacro {
	public static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingExtensionsOf type: some TypeSyntaxProtocol,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [ExtensionDeclSyntax] {
		let typeName = type.trimmedDescription
		let extensionDecl: DeclSyntax = "extension \(raw: typeName): LiveRegion {}"
		guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
			throw MacroExpansionErrorMessage("@LiveRegion could not synthesize the region conformance")
		}
		return [parsed]
	}
}

// MARK: - @RegionState
//
// a MARKER, never an expansion of its own: a peer macro is how Swift admits a
// custom attribute on a stored property, and `@LiveRegion`'s member scan is
// what reads it. it emits nothing.

/// `@RegionState` — marks the one stored property that is the region's source.
public struct RegionStateMarker: PeerMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingPeersOf declaration: some DeclSyntaxProtocol,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		[]
	}
}