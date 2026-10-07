import SwiftCompilerPlugin
import SwiftSyntaxMacros

// the live-data macro plugin: @LiveRegion · @RegionState · @LiveRegions · @LiveState.
//
// every macro here is a veneer, never a requirement: the hand-written path
// keeps compiling and behaving byte-identically (the substitution law, §3.0).
@main
struct WebUIServerMacroPlugin: CompilerPlugin {
	let providingMacros: [Macro.Type] = [
		LiveRegionMacro.self,
		RegionStateMarker.self,
		LiveRegionsMacro.self,
		LiveStateMacro.self,
	]
}