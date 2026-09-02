import Foundation
import PackagePlugin

@main
struct WebUIIconPlugin: BuildToolPlugin {

	func createBuildCommands(
		context: PluginContext,
		target: Target
	) throws -> [Command] {
		// The icon catalog lives in designer/icons/icon-manifest.json at the package root.
		let manifest = context.package.directoryURL
			.appendingPathComponent("designer")
			.appendingPathComponent("icons")
			.appendingPathComponent("icon-manifest.json")
		guard FileManager.default.fileExists(atPath: manifest.path) else {
			Diagnostics.warning("icon manifest not found at \(manifest.path) — skipping icon generation")
			return []
		}

		let outputURL = context.pluginWorkDirectoryURL
			.appendingPathComponent("IconLibrary.swift")

		let iconTool = try context.tool(named: "WebUIIconTool")

		let args: [String] = [
			"generate",
			"--manifest", manifest.path,
			"--swift-output", outputURL.path,
		]

		return [
			.buildCommand(
				displayName: "Generating WebUI icon catalog from designer/icons/icon-manifest.json",
				executable: iconTool.url,
				arguments: args,
				inputFiles: [manifest],
				outputFiles: [outputURL]
			)
		]
	}
}
