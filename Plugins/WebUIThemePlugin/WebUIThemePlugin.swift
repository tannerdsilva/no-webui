import Foundation
import PackagePlugin

// MARK: - WebUIThemePlugin — DX-15a consumer-sheet emission (mechanism (a))
//
// a FRAMEWORK build-tool plugin a consumer attaches to the app target that
// declares a `ThemeCatalog`. on every `swift build` it emits ONE build command
// running the framework's `WebUIThemeTool`, which spawns a DIRECT swiftc over
// the consumer's theme sources (the spike verdict: macro dylib load + .build
// module/link consumption both proven; see the lane T spike note). the command
// declares the generated `WebUIShippedAsset` conformance as its outputFile in
// the plugin work dir, so SwiftPM compiles it into the consumer target —
// the same mechanism by which `Assets+Generated.swift` and
// `Continuum+Generated.swift` become compilable target sources.
//
// the consumer's package needs NO other line: no tool target, no shim, no
// script. the manifest append (the DX-15a block) is the whole consumer surface
// beyond declaring a ThemeCatalog in the target this plugin attaches to.
//
// build ordering (f2's hard half): the command's tool (`context.tool(named:)`)
// is a product of THIS package whose dependency closure includes the macro
// dylib and every `.build` product the nested swiftc consumes — SwiftPM builds
// the tool product before the command runs, so the ordering is guaranteed by
// the tool dependency rather than by any target-product contract between this
// plugin and the consumer's app target.

@main
struct WebUIThemePlugin: BuildToolPlugin {

	func createBuildCommands(
		context: PluginContext,
		target: Target
	) throws -> [Command] {
		// the consumer's theme sources: target files whose text declares a
		// `ThemeCatalog` conformance. strict-marker scan (house style — same as
		// WebUIAutobuildPlugin's island discovery).
		let catalog = try Self.discoverCatalog(in: target)
		guard let catalog else {
			// no ThemeCatalog in this target: the plugin is inert. attaching it
			// to a target without a catalog is not an error — the same
			// convention as the autobuild plugin returning no commands when no
			// island imports the island core.
			return []
		}

		let tool = try context.tool(named: "WebUIThemeTool")
		let workDir = context.pluginWorkDirectoryURL
		// the emitted conformance, named from the catalog's type name (the
		// consumer's server references it as `WebUIAsset(<TypeName>Sheet.self,
		// path:)`).
		let typeName = catalog.typeName + "Sheet"
		let output = workDir.appendingPathComponent(typeName + ".swift")

		// the command inputs are the theme sources (llbuild re-runs the command
		// when any of them changes); the output is the generated asset, which
		// SwiftPM compiles into the attached target.
		return [
			.buildCommand(
				displayName: "WebUIThemePlugin: emitting \(typeName) from \(catalog.typeName) (theme pipeline)",
				executable: tool.url,
				arguments: [
					"--sources", catalog.sources.map(\.path).joined(separator: ","),
					"--catalog", catalog.typeName,
					"--type-name", typeName,
					"--output", output.path,
					"--work-dir", workDir.path,
				],
				inputFiles: catalog.sources,
				outputFiles: [output]
			)
		]
	}

	// MARK: - discovery

	struct Catalog: Equatable {
		let typeName: String
		let sources: [URL]
	}

	/// find the target's theme sources and the first `ThemeCatalog`
	/// conformance. a source qualifies when its text contains a top-level
	/// `…: ThemeCatalog` conformance (either alone or alongside other
	/// protocols) or a `@Theme` usage; we take all qualifying files as inputs
	/// and the FIRST catalog type as the emit target (a target with several
	/// catalogs emits for the first — the demo/twin shape is one catalog).
	static func discoverCatalog(in target: Target) throws -> Catalog? {
		let sources = target.sourceFiles(withSuffix: "swift").map(\.url)
		var themeSources: [URL] = []
		var typeName: String? = nil
		for url in sources {
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			// a ThemeCatalog conformance or a @Theme use marks a theme source.
			if text.contains("ThemeCatalog") || text.contains("@Theme") {
				themeSources.append(url)
				if typeName == nil, let name = Self.firstCatalogConformance(in: text) {
					typeName = name
				}
			}
		}
		guard !themeSources.isEmpty, let typeName else { return nil }
		return Catalog(typeName: typeName, sources: themeSources)
	}

	/// the first type conforming to `ThemeCatalog`:
	/// `struct|enum … <Name>(…): …ThemeCatalog…`. a text marker scan, strict
	/// forms only (the same discipline as the continuum tool's scanner).
	static func firstCatalogConformance(in text: String) -> String? {
		let pattern = /(?m)^\s*(?:public\s+|internal\s+|fileprivate\s+|private\s+)?(?:struct|enum|actor|final\s+class|class)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*:\s*[^\{]*ThemeCatalog/
		for line in text.split(separator: "\n") {
			if let m = String(line).firstMatch(of: pattern) {
				return String(m.1)
			}
		}
		return nil
	}
}
