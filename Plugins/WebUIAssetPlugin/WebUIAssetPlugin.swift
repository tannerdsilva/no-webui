import Foundation
import PackagePlugin

@main
struct WebUIAssetPlugin: BuildToolPlugin {

    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        // Assets live in designer/assets/ at the package root
        let assetsDir = context.package.directoryURL
            .appendingPathComponent("designer")
            .appendingPathComponent("assets")
        guard FileManager.default.fileExists(atPath: assetsDir.path) else {
            Diagnostics.warning("designer/assets/ directory not found at \(assetsDir.path)")
            return []
        }

        let cssFile = assetsDir.appendingPathComponent("design-system.css")
        let jsFile = assetsDir.appendingPathComponent("webui-runtime.js")
        let cssExists = FileManager.default.fileExists(atPath: cssFile.path)
        let jsExists = FileManager.default.fileExists(atPath: jsFile.path)

        guard cssExists || jsExists else {
            Diagnostics.warning("No CSS or JS files found in designer/assets/")
            return []
        }

        let outputURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("Assets+Generated.swift")

        let assetTool = try context.tool(named: "WebUIAssetTool")

        var args: [String] = []
        var inputs: [URL] = []
        if cssExists {
            args += ["--css-input", cssFile.path]
            inputs.append(cssFile)
        }
        if jsExists {
            args += ["--js-input", jsFile.path]
            inputs.append(jsFile)
        }
        args += ["--output", outputURL.path]

        return [
            .buildCommand(
                displayName: "Embedding WebUI assets from designer/assets/",
                executable: assetTool.url,
                arguments: args,
                inputFiles: inputs,
                outputFiles: [outputURL]
            )
        ]
    }
}
