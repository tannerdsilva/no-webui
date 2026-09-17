import Foundation
import PackagePlugin

/// a missing asset file is a build failure, never a silent degrade — the
/// generated embed is load-bearing (a stale or empty Assets+Generated.swift
/// would ship wrong bytes or none at all).
struct AssetError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

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
            throw AssetError("designer/assets/ directory not found at \(assetsDir.path) — required to embed the shipped css/js assets")
        }

        let cssFile = assetsDir.appendingPathComponent("design-system.css")
        let jsFile = assetsDir.appendingPathComponent("webui-runtime.js")
        let clientFile = assetsDir.appendingPathComponent("webui-client.js")
        let clientBootFile = assetsDir.appendingPathComponent("client-demo-boot.js")
        let clientSearchBootFile = assetsDir.appendingPathComponent("search-demo-boot.js")
        let cssExists = FileManager.default.fileExists(atPath: cssFile.path)
        let jsExists = FileManager.default.fileExists(atPath: jsFile.path)
        let clientExists = FileManager.default.fileExists(atPath: clientFile.path)
        let clientBootExists = FileManager.default.fileExists(atPath: clientBootFile.path)
        let clientSearchBootExists = FileManager.default.fileExists(atPath: clientSearchBootFile.path)

        guard cssExists || jsExists else {
            throw AssetError("no css or js files found in designer/assets/ at \(assetsDir.path) — required to embed the shipped assets")
        }

        let assetTool = try context.tool(named: "WebUIAssetTool")

        // the wasm-clean design-system core embeds the generated token
        // vocabulary (`DesignTokens+Generated.swift`); the server-bound WebUI
        // target embeds the assets (`Assets+Generated.swift`). the split (p5-t7)
        // keeps `DesignToken` reachable from the client build without rawdog.
        if target.name == "WebUIDesignSystemCore" {
            guard cssExists else {
                throw AssetError("designer/assets/design-system.css not found — required to generate the DesignToken vocabulary")
            }
            let tokensOutputURL = context.pluginWorkDirectoryURL
                .appendingPathComponent("DesignTokens+Generated.swift")
            return [
                .buildCommand(
                    displayName: "Generating DesignToken from designer/assets/",
                    executable: assetTool.url,
                    arguments: ["--css-input", cssFile.path, "--tokens-output", tokensOutputURL.path],
                    inputFiles: [cssFile],
                    outputFiles: [tokensOutputURL]
                )
            ]
        }

        let outputURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("Assets+Generated.swift")

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
        if clientExists {
            args += ["--client-input", clientFile.path]
            inputs.append(clientFile)
        }
        if clientBootExists {
            args += ["--client-boot-input", clientBootFile.path]
            inputs.append(clientBootFile)
        }
        if clientSearchBootExists {
            args += ["--client-search-boot-input", clientSearchBootFile.path]
            inputs.append(clientSearchBootFile)
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
