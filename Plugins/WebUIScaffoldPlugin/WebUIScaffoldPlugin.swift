import Foundation
import PackagePlugin

// MARK: - WebUIScaffoldPlugin — the DX-2 scaffold verb (CONTINUUM_DX §2.2)
//
// a command plugin: `swift package --disable-sandbox plugin scaffold` runs
// `WebUIContinuumTool scaffold` against THIS package (the writeToPackageDirectory
// permission lets the tool append the island product+target entries and emit
// Sources/<Name>/main.swift). port-free, on demand — the DX-2 explicit path
// for existing apps; new apps start from the template whose manifest already
// carries the inert block.
//
// sub-surfaces (forwarded verbatim to the tool):
//   --add-island <Name> [--package no-webui] [--print]
//   --bootstrap --name <App> --framework <no-webui path> [--print]
//
// the plugin is a thin wrapper: all anchor/append/refusal logic lives in the
// tool so the same surface is usable directly (`webui-continuum scaffold`).
@main
struct WebUIScaffoldPlugin: CommandPlugin {

	func performCommand(
		context: PluginContext,
		arguments: [String]
	) async throws {
		let tool = try context.tool(named: "WebUIContinuumTool")
		let packageDir = context.package.directoryURL.path

		// --package-dir is injected by the plugin (the tool defaults to "." for
		// a direct invocation); everything else is forwarded.
		var toolArgs = ["scaffold", "--package-dir", packageDir] + arguments

		// --bootstrap needs the no-webui framework path. if the manifest
		// already declares the dependency, resolve it from the plugin context
		// so the caller does not have to pass --framework.
		if arguments.contains("--bootstrap"),
		   !arguments.contains("--framework"),
		   let framework = context.package.dependencies.first(where: { dependency in
			   dependency.package.displayName == "no-webui"
		   }) {
			toolArgs += ["--framework", framework.package.directoryURL.path]
		}

		let process = Process()
		process.executableURL = tool.url
		process.arguments = toolArgs
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardError
		try process.run()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			throw ScaffoldPluginError(
				"WebUIContinuumTool scaffold failed (exit \(process.terminationStatus)) — see the tool output above"
			)
		}
	}
}

struct ScaffoldPluginError: Error, CustomStringConvertible {
	let description: String
	init(_ description: String) { self.description = description }
}
