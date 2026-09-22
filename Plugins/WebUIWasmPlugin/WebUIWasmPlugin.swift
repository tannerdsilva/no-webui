import Foundation
import PackagePlugin

/// a missing artifact is a build failure — wasm is the sole client runtime in
/// this package, so an absent artifact would ship a page that cannot run (the
/// serving seam would 404). a *present but corrupt* artifact is likewise a
/// failure (it would ship wrong bytes to every client-mode page). this mirrors
/// the `WebUIAssetPlugin` discipline: load-bearing generated files never
/// degrade silently.
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
            // absent artifact = hard build failure, never a silent 404. wasm is
            // unconditionally the client runtime; the consumer runs
            // `swift package --disable-sandbox plugin wasm-client` first.
            throw WasmPluginError(
                "WebUIClient.wasm is absent at \(artifactURL.path) — run `swift package --disable-sandbox plugin wasm-client` (or build with the wasm sdk) before this host build. client-mode pages require the wasm artifact."
            )
        }
    }
}
