import Foundation
import PackagePlugin

/// the client artifact is OPTIONAL now: the engine is the default runtime, so
/// an absent `WebUIClient.wasm` must not fail the host build — the plugin emits
/// a `present = false` carrier and the wasm routes 404 for explicit wasm-mode
/// consumers until they run `wasm-client`. a *present but corrupt* artifact is
/// still a failure (it would ship wrong bytes to every client-mode page).
struct WasmPluginError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct WebUIWasmPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        // the framework's own client artifact lives at the standard SwiftPM
        // 6.4 wasm-triple output path under the package root, resolved
        // explicitly against context.package.directoryURL (the tool's CWD is
        // not guaranteed across host/dependency builds — verified 2026-09).
        // in-repo this finds WebUIClient.wasm after `wasm-client` runs; under
        // a consumer build the checkout has no .build/out remnant, so the
        // consumer must produce their own artifact via `WebUIBoot.wasmProductURL(productName:)`
        // before the host build.
        let artifactURL = context.package.directoryURL
            .appendingPathComponent(".build")
            .appendingPathComponent("out")
            .appendingPathComponent("Products")
            .appendingPathComponent("Release-webassembly-wasm32")
            .appendingPathComponent("WebUIClient.wasm")
        let outputURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("Wasm+Generated.swift")

        let tool = try context.tool(named: "WebUIWasmTool")

        let artifactExists = FileManager.default.fileExists(atPath: artifactURL.path)

        if artifactExists {
            // artifact present: validate + hash it; corrupt fails the build,
            // and the sha is known at compile time for the immutable route.
            return [
                .buildCommand(
                    displayName: "Validating + hashing WebUIClient.wasm for host embed",
                    executable: tool.url,
                    arguments: [
                        "--wasm-input", artifactURL.path,
                        "--output", outputURL.path,
                        "--product", "WebUIClient",
                    ],
                    inputFiles: [artifactURL],
                    outputFiles: [outputURL]
                )
            ]
        } else {
            // absent artifact = soft absent carrier. the engine is the default
            // client runtime, so engine-only hosts build green; pages that
            // declare the wasm client run `wasm-client` first, and their wasm
            // routes 404 (loudly) until the artifact exists.
            return [
                .buildCommand(
                    displayName: "Emitting absent WebUIClient carrier (soft)",
                    executable: tool.url,
                    arguments: [
                        "--missing",
                        "--output", outputURL.path,
                        "--product", "WebUIClient",
                    ],
                    outputFiles: [outputURL]
                )
            ]
        }
    }
}
