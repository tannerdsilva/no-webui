import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WebUIDesignSystemMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WebUIThemeMacro.self,
        WiredMacro.self,
        WireGroupMacro.self,
    ]
}
