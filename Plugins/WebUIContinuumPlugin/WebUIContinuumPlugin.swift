import Foundation
import PackagePlugin

@main
struct WebUIContinuumPlugin: BuildToolPlugin {

    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) throws -> [Command] {
        // the class inventory scans the design-system core sources (the
        // component vocabulary lives there). a missing dir is a build
        // failure, never a silent skip: the generated inventory is load-
        // bearing (the engine's attr allowlist and the class machinery's
        // static half read it).
        let coreDir = context.package.directoryURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("WebUIDesignSystemCore")
        guard FileManager.default.fileExists(atPath: coreDir.path) else {
            throw ContinuumPluginError("Sources/WebUIDesignSystemCore/ not found — required to generate the continuum class inventory")
        }

        // only the WebUI target consumes the generated inventory; the scan
        // itself reads the shared core sources (which do NOT attach this
        // plugin — avoid a build cycle: the core cannot import the inventory
        // it feeds).
        guard target.name == "WebUI" else { return [] }

        let outputURL = context.pluginWorkDirectoryURL
            .appendingPathComponent("Continuum+Generated.swift")

        let tool = try context.tool(named: "WebUIContinuumTool")
        let inputFiles = try FileManager.default.contentsOfDirectory(
            atPath: coreDir.path
        )
        .filter { $0.hasSuffix(".swift") }
        .map { coreDir.appendingPathComponent($0) }

        // the WebUI target is where the consumer surface (@HotView / @HotClass
        // markers) lands; the capability lint scans it alongside the core.
        let webUIDir = context.package.directoryURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("WebUI")
        let webUIInputs: [URL] = (try? FileManager.default.contentsOfDirectory(
            atPath: webUIDir.path
        )
        .filter { $0.hasSuffix(".swift") }
        .map { webUIDir.appendingPathComponent($0) }) ?? []

        // the capability gate's cache stamp: the lint itself writes this after
        // a clean scan, so a deliberate violation stops the build with the
        // t2.6 message instead of being cached away.
        let lintOutput = context.pluginWorkDirectoryURL
            .appendingPathComponent("Capabilities.ok")

        return [
            .buildCommand(
                displayName: "Generating the continuum class inventory from Sources/WebUIDesignSystemCore/",
                executable: tool.url,
                arguments: [
                    "generate",
                    "--sources", coreDir.path,
                    "--output", outputURL.path,
                ],
                inputFiles: inputFiles,
                outputFiles: [outputURL]
            ),
            // d2 t2.6: the capability-grants gate. runs on every build over the
            // marker-bearing sources; a mismatch (`@HotView` imports something
            // the host manifest does not grant) fails the build with the parent
            // plan's exact message.
            .buildCommand(
                displayName: "Checking continuum capability grants against the host manifest (@HotView imports:)",
                executable: tool.url,
                arguments: [
                    "lint",
                    "--sources", coreDir.path,
                    "--hotview-sources", webUIDir.path,
                    "--touch", lintOutput.path,
                ],
                inputFiles: inputFiles + webUIInputs,
                outputFiles: [lintOutput]
            ),
        ]
    }
}

struct ContinuumPluginError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
