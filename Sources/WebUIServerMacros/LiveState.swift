import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - @LiveState
//
// an actor gets `nonisolated func subscribe` + `notify()` from the notifier
// plumbing. the third documented footgun dies here: `nonisolated` is generated
// BY CONSTRUCTION (d-x7), so the synchronous hop onto a busy actor — the
// failure mode that blocks `start()` — cannot be written by accident.
//
// the notifier storage is a MEMBER, not an extension member: Swift extensions
// cannot add stored properties, so the member role is the only role that can
// own the storage. the conformance itself comes from the extension role.

public struct LiveStateMacro: MemberMacro {
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		guard declaration.as(ActorDeclSyntax.self) != nil else {
			throw MacroExpansionErrorMessage("@LiveState can only be applied to an actor")
		}

		let declared = declaredNames(of: declaration)
		if declared.contains("subscribe") {
			throw MacroExpansionErrorMessage(
				"@LiveState generates 'subscribe' — a hand-written 'subscribe' on the same actor is ambiguous; remove it"
			)
		}
		if declared.contains("notify") {
			throw MacroExpansionErrorMessage(
				"@LiveState generates 'notify' — a hand-written 'notify' on the same actor is ambiguous; remove it"
			)
		}
		if declared.contains("liveNotifier") {
			throw MacroExpansionErrorMessage(
				"@LiveState generates 'liveNotifier' — a hand-written 'liveNotifier' on the same actor is ambiguous; remove it"
			)
		}

		let access = accessPrefix(for: declaration)
		return [
			"private let liveNotifier = LiveNotifier()",
			"""
			\(raw: access)nonisolated func subscribe(_ onChange: @escaping @Sendable () -> Void) -> LiveSubscription {
				liveNotifier.add(onChange)
			}
			""",
			"""
			\(raw: access)func notify() {
				liveNotifier.notify()
			}
			""",
		]
	}
}

extension LiveStateMacro: ExtensionMacro {
	public static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingExtensionsOf type: some TypeSyntaxProtocol,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [ExtensionDeclSyntax] {
		let typeName = type.trimmedDescription
		let extensionDecl: DeclSyntax = "extension \(raw: typeName): LiveState {}"
		guard let parsed = extensionDecl.as(ExtensionDeclSyntax.self) else {
			throw MacroExpansionErrorMessage("@LiveState could not synthesize the state conformance")
		}
		return [parsed]
	}
}