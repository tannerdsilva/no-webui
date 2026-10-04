import Foundation
import PackagePlugin

// MARK: - WebUIVerifyPlugin — the DX-8 `verify` verb (CONTINUUM_DX §4.7, W3)
//
// a command plugin: `swift package --disable-sandbox plugin verify` runs the
// FULL island verification path (host build → wasm cross-build → DX-3
// measure/auto-pin → the WebUIBudgetPlugin budget row) against THIS package —
// the same one-verb surface a consumer gets from the tool directly
// (`webui-continuum verify --package-dir <app> --framework <no-webui path>`).
//
// `wasm-island` stays internal (unchanged semantics; the ladder + acceptance
// keep calling it) — `verify` is the consolidated consumer-facing verb, so no
// getting-started path names `plugin wasm-island` (the no-manual-steps audit,
// §4.7, recorded in b-docs).
//
// the plugin is a thin wrapper, exactly like WebUIScaffoldPlugin: all stage
// logic lives in the tool so the same surface is usable directly. `--package-dir`
// is injected (the tool defaults to "."); `--framework` is resolved from this
// package's own dependency graph when the manifest declares no-webui, so an
// in-repo invocation needs no arguments.
@main
struct WebUIVerifyPlugin: CommandPlugin {

	func performCommand(
		context: PluginContext,
		arguments: [String]
	) async throws {
		let tool = try context.tool(named: "WebUIContinuumTool")
		let packageDir = context.package.directoryURL.path

		// --package-dir is injected by the plugin (the tool defaults to "." for
		// a direct invocation); everything else is forwarded.
		var toolArgs = ["verify", "--package-dir", packageDir] + arguments

		// --framework resolves to the no-webui framework this package depends on
		// (verify needs the island graph root: WebUIIslandCore/WebUISharedCore).
		if !arguments.contains("--framework"),
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
			throw VerifyPluginError(
				"WebUIContinuumTool verify failed (exit \(process.terminationStatus)) — see the stage output above"
			)
		}
	}
}

struct VerifyPluginError: Error, CustomStringConvertible {
	let description: String
	init(_ description: String) { self.description = description }
}
