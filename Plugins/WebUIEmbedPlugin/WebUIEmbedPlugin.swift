import Foundation
import PackagePlugin

/// the file half of the asset toolkit, framework-owned: a target that ships
/// `Assets/webui-assets.json` gets its declared files embedded on every build. the plugin
/// discovers the manifest, declares it and every file it references as inputs (so editing a
/// payload re-runs the command), and invokes the framework's own tool in its
/// `--embed-manifest` mode — a plugin cannot import a library, which is why the logic lives
/// in `WebUIBuild` and this is a thin, portable wrapper over it.
///
/// attaching this to a target that carries files the framework should embed is the whole
/// contract; the target should also `exclude: ["Assets"]` so swiftpm stops warning about
/// files it does not know how to handle (the plugin reads them through its own context,
/// which exclusion does not affect).
///
/// a target with no manifest is untouched: nothing generated, nothing warned.
///
/// (`target.directory` rather than `directoryURL`: this package's manifest is tools 6.0, and
/// the URL spelling arrived in the 6.1 plugin api.)
@main
struct WebUIEmbedPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
		guard let target = target as? SourceModuleTarget else { return [] }
		let assets = target.directory.appending("Assets")
		let manifest = assets.appending("webui-assets.json")
		guard FileManager.default.fileExists(atPath: manifest.string) else { return [] }

		let tool = try context.tool(named: "WebUIAssetTool")
		let output = context.pluginWorkDirectoryURL.appendingPathComponent("EmbeddedAssets.swift")

		return [
			.buildCommand(
				displayName: "embedding \(target.name) assets",
				executable: tool.url,
				arguments: ["--embed-manifest", manifest.string, "--output", output.path],
				inputFiles: Self.referencedInputs(manifest: manifest, assets: assets),
				outputFiles: [output]
			)
		]
	}

	/// every file the manifest references, so a payload edit re-runs the command. the
	/// manifest's *shape* is not validated here — an unreadable or malformed manifest is
	/// still an input, and the tool reports exactly what is wrong with it.
	static func referencedInputs(manifest: Path, assets: Path) -> [URL] {
		let manifestURL = URL(fileURLWithPath: manifest.string)
		var inputs = [manifestURL]
		guard
			let data = try? Data(contentsOf: manifestURL),
			let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
			let entries = root["types"] as? [[String: Any]]
		else { return inputs }

		for entry in entries {
			guard let path = entry["path"] as? String else { continue }
			let target = assets.appending(path).string
			if (entry["kind"] as? String) == "directory" {
				let extensions = (entry["extensions"] as? [String]) ?? []
				let names = (try? FileManager.default.contentsOfDirectory(atPath: target)) ?? []
				inputs.append(contentsOf: names
					.filter { name in extensions.contains { name.hasSuffix($0) } }
					.map { URL(fileURLWithPath: target + "/" + $0) })
			} else {
				inputs.append(URL(fileURLWithPath: target))
			}
		}
		return inputs
	}
}