import Foundation
import PackagePlugin

@main
struct WebUIShowcasePlugin: CommandPlugin {

    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        // Parse optional --output argument
        var outputPath = context.pluginWorkDirectory.appending("showcase").appending("index.html")
        if let outputIndex = arguments.firstIndex(of: "--output"),
           outputIndex + 1 < arguments.count {
            outputPath = Path(arguments[outputIndex + 1])
        }

        // Build the showcase generator
        print("Building WebUI Showcase generator...")
        let showcaseTool = try context.tool(named: "WebUIShowcase")
        let executableURL = URL(fileURLWithPath: showcaseTool.path.string)

        // Run the generator with --generate flag
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--generate", outputPath.string]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("")
            print("WebUI Showcase generated at:")
            print("  file://\(outputPath.string)")
            print("")
            print("Open this URL in your browser to view the showcase.")
        } else {
            print("Error: Showcase generation failed with exit code \(process.terminationStatus)")
        }
    }
}