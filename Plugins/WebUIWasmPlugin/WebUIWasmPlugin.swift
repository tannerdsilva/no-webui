import Foundation
import PackagePlugin

/// a missing artifact is tolerated (present=false carrier — the host build
/// stays green without a wasm build, matching the runtime's absent → alias
/// route behavior); a *present but corrupt* artifact is a build failure (it
/// would ship wrong bytes to every client-mode page). this mirrors the
/// `WebUIAssetPlugin` discipline: load-bearing generated files never degrade
/// silently.
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
        // plugin emits the absent carrier and the consumer serves their own
        // artifact via `WebUIBoot.wasmProductURL(productName:)` at runtime.
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
        } else if ProcessInfo.processInfo.environment["WEBUI_REQUIRE_WASM"] == "1" {
            // a consumer that ships client-mode pages can opt into a hard
            // gate: absent artifact = build failure, never a silent 404 in
            // production. the env var is read at plugin-execution time, so it
            // works from the repo and from consumer builds alike.
            throw WasmPluginError(
                "WebUIClient.wasm is absent at \(artifactURL.path) and WEBUI_REQUIRE_WASM=1 is set — run `swift package --disable-sandbox plugin wasm-client` (or build with the wasm sdk) before this host build."
            )
        } else {
            // artifact absent at build time: emit the absent carrier so the
            // serving seam routes to the no-store alias (and likely 404s).
            // the consumer runs `swift package --disable-sandbox plugin
            // wasm-client` to produce it.
            return [
                .buildCommand(
                    displayName: "WebUIClient.wasm absent — embedding empty carrier (run `swift package --disable-sandbox plugin wasm-client`)",
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
