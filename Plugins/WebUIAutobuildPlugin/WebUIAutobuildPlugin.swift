import Foundation
import PackagePlugin

// MARK: - WebUIAutobuildPlugin — the DX-5 autobuild (CONTINUUM_DX §2.5, candidate b)
//
// a build-tool plugin a consumer app attaches to its own target. at every
// `swift build` — the developer's plain command, no `--disable-sandbox`, no
// manual verb — it cross-builds the REAL island graph (island main ->
// WebUIIslandCore -> WebUISharedCore, the frame's zero-remote leaf) for
// wasm32-wasip1 with the wasm sdk's embedded variant, via the framework's
// `WebUIContinuumTool wasm-cross` verb: a DIRECT two-stage swiftc over the
// on-disk graph, NO nested SwiftPM resolution (the red-team killed candidate
// (a)'s nested build on remote deps and candidate (c)'s manifest side; the
// surviving mechanism is (b)).
//
// sandbox geometry (measured): the emitted command runs under SwiftPM's
// `(allow process*) (allow file-read*)` seatbelt — it can exec swiftc and
// read the island sources anywhere, but it may WRITE only to the plugin work
// dir (+ tmp). the artifact therefore lands in `context.pluginWorkDirectoryURL`
// (a sandbox-writable zone on a home-dir checkout) and the serving seam reads
// it from there — NOT `.build/out/Products/…`, which a build command may not
// write on a home-dir project.
//
// warm builds are free via llbuild: the command declares the island sources
// as `inputFiles` and the artifact as `outputFiles`, so an unchanged graph
// re-runs zero commands (measured 0.16 s budget).
//
// prereqs (a missing swiftly toolchain / wasm sdk) are pre-checked in the
// TOOL with named diagnostics; `WEBUI_WASM_SWIFTC` overrides the compiler
// path for machines/tests (the plugin host inherits custom env — verified).
// the recursion guard convention `WEBUI_ISLAND_NESTED=1` is honoured as a
// backstop (the tool also sets it on its own children).
@main
struct WebUIAutobuildPlugin: BuildToolPlugin {

	func createBuildCommands(
		context: PluginContext,
		target: Target
	) throws -> [Command] {
		// the island graph is the frame's zero-dep core: the plugin finds it
		// in the ATTACHED package (the frame itself) or in a declared
		// dependency package (a consumer app). a missing graph is a wiring
		// failure, never a silent skip the developer would discover at runtime.
		let graphURL: URL
		if Self.hasIslandGraph(context.package.directoryURL) {
			graphURL = context.package.directoryURL
		} else if let dep = context.package.dependencies.first(where: {
			Self.hasIslandGraph($0.package.directoryURL)
		}) {
			graphURL = dep.package.directoryURL
		} else {
			throw WebUIAutobuildError(
				"WebUIAutobuild: no island graph found — expected Sources/WebUIIslandCore + Sources/WebUISharedCore under the attached package or one of its dependencies (attach WebUIAutobuildPlugin to a target of the package that depends on the no-webui framework)"
			)
		}

		// discover the island products: executable source dirs whose main
		// imports the island core (a text scan — the house marker rule). the
		// graph contributes the frame's real islands; the ATTACHED package
		// contributes the developer's own consumer islands (the DX-5 end
		// state: `swift build` cross-builds yours alongside the frame's).
		let islands = try Self.discoverIslands(in: graphURL)
			+ (graphURL.standardizedFileURL != context.package.directoryURL.standardizedFileURL
			   ? try Self.discoverIslands(in: context.package.directoryURL)
			   : [])
		guard !islands.isEmpty else { return [] }

		let tool = try context.tool(named: "WebUIContinuumTool")
		let swiftc = Self.swiftcSelection()

		var commands: [Command] = []
		for island in islands {
			// a consumer island lives in the attached package; the frame's
			// islands live in the graph.
			let mainDir = context.package.directoryURL
				.appendingPathComponent("Sources/" + island)
			let mainInAttached = FileManager.default.fileExists(atPath: mainDir.path)
			let mainRoot = mainInAttached ? context.package.directoryURL : graphURL
			// sandbox-writable zone: everything for one island in its own
			// work subdir (parallel commands never share mutable scratch).
			let obj = context.pluginWorkDirectoryURL
				.appendingPathComponent(island + ".obj")
			let artifact = context.pluginWorkDirectoryURL
				.appendingPathComponent(island + ".wasm")
			var islandArgs = [
				"wasm-cross",
				"--graph", graphURL.path,
				"--product", island,
				"--obj", obj.path,
				"--out", artifact.path,
				"--swiftc", swiftc,
			]
			if mainInAttached {
				islandArgs += ["--main-dir", mainDir.path]
			}
			let inputs = Self.islandSources(graph: graphURL, mainRoot: mainRoot, island: island)

			commands.append(.buildCommand(
				displayName: "WebUIAutobuild: cross-building island \(island) (embedded wasm, direct swiftc)",
				executable: tool.url,
				arguments: islandArgs,
				inputFiles: inputs,
				outputFiles: [artifact]
			))
		}

		// DX-3 auto-pin: ONE measure command after all the cross-builds. its
		// inputFiles are every island artifact and its outputFiles are the
		// work-dir ContinuumManifest.json, so llbuild orders it after the
		// commands above and skips it warm (no artifact changed); the tool
		// scans the work dir itself, so no per-command sidecar or shared-file
		// race. the pins it writes (name/maxBytes/maxGzipBytes EXACTLY the
		// schema WebUIBudgetPlugin reads, + additive raw/gz/sha/url, version 2)
		// are spliced into the served /ui/continuum-manifest.json at
		// serve-emission by WebUIServer (DX-6b).
		let islandArtifacts = islands.map {
			context.pluginWorkDirectoryURL.appendingPathComponent($0 + ".wasm")
		}
		let pinManifest = context.pluginWorkDirectoryURL
			.appendingPathComponent("ContinuumManifest.json")
		commands.append(.buildCommand(
			displayName: "WebUIAutobuild: measuring island pins into ContinuumManifest.json (DX-3)",
			executable: tool.url,
			arguments: [
				"measure",
				"--work-dir", context.pluginWorkDirectoryURL.path,
				"--manifest", pinManifest.path,
			],
			inputFiles: islandArtifacts,
			outputFiles: [pinManifest]
		))
		return commands
	}

	// MARK: - helpers

	/// the graph root carries the two leaf modules of the island graph.
	static func hasIslandGraph(_ dir: URL) -> Bool {
		FileManager.default.fileExists(atPath: dir.appendingPathComponent("Sources/WebUIIslandCore").path)
			&& FileManager.default.fileExists(atPath: dir.appendingPathComponent("Sources/WebUISharedCore").path)
	}

	/// island products = `Sources/<Name>/` dirs whose main (main.swift /
	/// Main.swift) imports `WebUIIslandCore` (the island mains in the frame
	/// all do — probe + validate; a board executable does not).
	static func discoverIslands(in graph: URL) throws -> [String] {
		let sources = graph.appendingPathComponent("Sources")
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sources.path) else {
			throw WebUIAutobuildError("WebUIAutobuild: cannot list \(sources.path)")
		}
		var islands: [String] = []
		for name in entries.sorted() {
			guard !name.hasPrefix(".") else { continue }
			let dir = sources.appendingPathComponent(name)
			var isDir: ObjCBool = false
			guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
			for mainName in ["main.swift", "Main.swift"] {
				let mainURL = dir.appendingPathComponent(mainName)
				guard let text = try? String(contentsOf: mainURL, encoding: .utf8) else { continue }
				if text.contains("import WebUIIslandCore") || text.contains("import WebUISharedCore") {
					islands.append(name)
				}
				break
			}
		}
		return islands
	}

	/// every swift source the cross-build reads: the graph's two leaf modules
	/// plus the island's own dir (wherever it lives: the graph or the attached
	/// package). declaring these as inputs gives llbuild its invalidation
	/// signal — a source edit re-runs exactly that island's command.
	static func islandSources(graph: URL, mainRoot: URL, island: String) -> [URL] {
		var dirs = [graph.appendingPathComponent("Sources/WebUISharedCore"),
		            graph.appendingPathComponent("Sources/WebUIIslandCore"),
		            mainRoot.appendingPathComponent("Sources/" + island)]
		var files: [URL] = []
		for dir in dirs {
			guard let enumerator = FileManager.default.enumerator(atPath: dir.path) else { continue }
			while let relative = enumerator.nextObject() as? String {
				guard relative.hasSuffix(".swift"), !relative.contains("/.build/") else { continue }
				files.append(dir.appendingPathComponent(relative))
			}
		}
		return files.sorted { $0.path < $1.path }
	}

	/// the wasm-capable compiler to pass to the tool: the swiftly-hosted
	/// toolchain swiftc (the Xcode frontend cannot read the wasm sdk's
	/// modules). `WEBUI_WASM_SWIFTC` overrides for non-standard machines and
	/// tests (verified: custom env reaches the plugin host).
	static func swiftcSelection() -> String {
		let env = ProcessInfo.processInfo.environment
		if let override = env["WEBUI_WASM_SWIFTC"], !override.isEmpty {
			return override
		}
		let toolchains = NSHomeDirectory() + "/Library/Developer/Toolchains"
		if let entries = try? FileManager.default.contentsOfDirectory(atPath: toolchains) {
			let candidates = entries.filter { $0.hasSuffix(".xctoolchain") }.sorted()
			if let latest = candidates.last {
				let bin = toolchains + "/" + latest + "/usr/bin/swiftc"
				if FileManager.default.fileExists(atPath: bin) { return bin }
			}
		}
		let shim = NSHomeDirectory() + "/.swiftly/bin/swiftc"
		if FileManager.default.fileExists(atPath: shim) { return shim }
		return "/usr/bin/swiftc"
	}
}

struct WebUIAutobuildError: Error, CustomStringConvertible {
	let description: String
	init(_ description: String) { self.description = description }
}
