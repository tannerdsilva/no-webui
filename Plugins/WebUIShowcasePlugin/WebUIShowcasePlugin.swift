import Foundation
import PackagePlugin

@main
struct WebUIShowcasePlugin: CommandPlugin {

    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        // Default: write the showcase into designer/previews/ (allowed via the
        // writeToPackageDirectory permission). --output overrides to any path.
        var outputURL = context.package.directoryURL
            .appendingPathComponent("designer/previews/showcase.html")
        if let outputIndex = arguments.firstIndex(of: "--output"),
           outputIndex + 1 < arguments.count {
            outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
        }

        print("Building WebUI Showcase generator...")
        let showcaseTool = try context.tool(named: "WebUIShowcase")

        let process = Process()
        process.executableURL = showcaseTool.url
        process.arguments = ["--generate", outputURL.path]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("")
            print("WebUI Showcase generated at:")
            print("  file://\(outputURL.path)")
            print("")
            print("Open this URL in your browser to view the showcase.")
        } else {
            print("Error: Showcase generation failed with exit code \(process.terminationStatus)")
        }
    }
}
