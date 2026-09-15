import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct WebUIDesignSystemMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        WebUIThemeMacro.self,
    ]
}
