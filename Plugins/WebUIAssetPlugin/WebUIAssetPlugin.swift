import Foundation
import PackagePlugin

@main
struct WebUIAssetPlugin: BuildToolPlugin {

    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        // Assets live in designer/assets/ at the package root
        let assetsDir = context.package.directory.appending("designer").appending("assets")
        guard FileManager.default.fileExists(atPath: assetsDir.string) else {
            Diagnostics.warning("designer/assets/ directory not found at \(assetsDir.string)")
            return []
        }

        let cssFile = assetsDir.appending("design-system.css")
        let jsFile = assetsDir.appending("webui-runtime.js")
        let cssExists = FileManager.default.fileExists(atPath: cssFile.string)
        let jsExists = FileManager.default.fileExists(atPath: jsFile.string)

        guard cssExists || jsExists else {
            Diagnostics.warning("No CSS or JS files found in designer/assets/")
            return []
        }

        let outputPath = context.pluginWorkDirectory
            .appending("Assets+Generated.swift")

        let assetTool = try context.tool(named: "WebUIAssetTool")

        var args: [String] = []
        var inputs: [URL] = []
        if cssExists {
            args += ["--css-input", cssFile.string]
            inputs.append(URL(fileURLWithPath: cssFile.string))
        }
        if jsExists {
            args += ["--js-input", jsFile.string]
            inputs.append(URL(fileURLWithPath: jsFile.string))
        }
        args += ["--output", outputPath.string]

        return [
            .buildCommand(
                displayName: "Embedding WebUI assets from designer/assets/",
                executable: URL(fileURLWithPath: assetTool.path.string),
                arguments: args,
                inputFiles: inputs,
                outputFiles: [URL(fileURLWithPath: outputPath.string)]
            )
        ]
    }
}
