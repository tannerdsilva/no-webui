import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WebUIContinuumMacroPlugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [
		HotViewMacro.self,
		HotClassMacro.self,
	]
}
