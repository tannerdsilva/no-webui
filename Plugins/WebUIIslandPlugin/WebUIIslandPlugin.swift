import Foundation
import PackagePlugin

/// `swift package --disable-sandbox plugin wasm-island [--product WebUIValidateIsland]`
///
/// cross-builds a capability island product with the official wasm sdk, strips
/// custom sections, and copies the artifact to the canonical
/// `.build/out/Products/Release-webassembly-wasm32/<product>.wasm` location the
/// serving seam reads. same constraints as `wasm-client`: `--disable-sandbox`
/// (the nested swift build re-enters its own sandbox), an isolated scratch
/// root (the plugin invocation holds the package `.build` lock), and the
/// swiftly shim (the Xcode frontend cannot read the wasm sdk's modules).
@main
struct WebUIIslandPlugin: CommandPlugin {
	func performCommand(
		context: PluginContext,
		arguments: [String]
	) throws {
		var product = "WebUIValidateIsland"
		var sdk = "swift-6.4.0-RELEASE_wasm"
		var outputOverride: String?
		var noStrip = false
		var iterator = arguments.makeIterator()
		while let flag = iterator.next() {
			switch flag {
			case "--product":
				product = iterator.next() ?? product
			case "--sdk":
				sdk = iterator.next() ?? sdk
			case "--output":
				outputOverride = iterator.next()
			case "--no-strip":
				noStrip = true
			default:
				break
			}
		}

		let env = ProcessInfo.processInfo.environment
		let swiftBin: String
		if let override = env["SWIFT_BIN"], !override.isEmpty {
			swiftBin = override
		} else if FileManager.default.fileExists(atPath: NSString(string: "~/.swiftly/bin/swift").expandingTildeInPath) {
			swiftBin = NSString(string: "~/.swiftly/bin/swift").expandingTildeInPath
		} else {
			swiftBin = "swift"
		}

		let packageDir = context.package.directoryURL.path
		let scratch = packageDir + "/.build/wasm-island-scratch"

		// embedded wasm keeps the unicode (nfd + grapheme) tables in a separate
		// static archive the default link line omits — without it a String that
		// reaches canonical-equality/dictionary-key comparison fails to link on
		// the `_swift_stdlib_*` normalization symbols. locate it from the sdk's
		// own `-print-target-info` (resource dir) so no path is hardcoded.
		let unicodeTableArgs = unicodeTableLinkArgs(swiftBin: swiftBin, sdk: sdk)

		print("WebUIIsland: cross-building '\(product)' with \(sdk) (via \(swiftBin))")
		let build = Process()
		build.executableURL = URL(fileURLWithPath: swiftBin)
		build.arguments = [
			"build",
			"-c", "release",
			"--swift-sdk", sdk,
			"--build-path", scratch,
			"--package-path", packageDir,
			"--product", product,
			"-Xswiftc", "-Osize",
		] + unicodeTableArgs
		let pipe = Pipe()
		build.standardOutput = pipe
		build.standardError = pipe
		build.environment = env
		try build.run()
		build.waitUntilExit()
		let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		guard build.terminationStatus == 0 else {
			print(out)
			print("WebUIIsland: cross-build failed (\(build.terminationStatus))")
			throw WebUIIslandError.buildFailed(build.terminationStatus)
		}

		let builtArtifact = scratch + "/out/Products/Release-webassembly-wasm32/" + product + ".wasm"
		guard FileManager.default.fileExists(atPath: builtArtifact) else {
			print(out)
			print("WebUIIsland: artifact not found at \(builtArtifact)")
			throw WebUIIslandError.artifactMissing(builtArtifact)
		}
		let destination = outputOverride
			?? packageDir + "/.build/out/Products/Release-webassembly-wasm32/" + product + ".wasm"

		if noStrip {
			try Self.copyFile(from: builtArtifact, to: destination)
		} else {
			let stripTool = try context.tool(named: "WebUIWasmTool")
			let stripped = destination + ".stripped"
			let strip = Process()
			strip.executableURL = stripTool.url
			strip.arguments = ["--strip-input", builtArtifact, "--strip-output", stripped]
			let spipe = Pipe()
			strip.standardOutput = spipe
			strip.standardError = spipe
			try strip.run()
			strip.waitUntilExit()
			let sout = String(data: spipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
			guard strip.terminationStatus == 0, FileManager.default.fileExists(atPath: stripped) else {
				print(sout)
				throw WebUIIslandError.stripFailed
			}
			try Self.copyFile(from: stripped, to: destination)
			if let _ = try? FileManager.default.removeItem(atPath: stripped) {}
		}

		let size = (try? FileManager.default.attributesOfItem(atPath: destination)[.size] as? Int) ?? 0
		print("WebUIIsland: artifact ready at \(destination) (\(size) bytes\(noStrip ? ", unstripped" : ", custom-sections stripped"))")
	}

	/// resolves the embedded unicode data tables archive from the installed
	/// wasm-sdk artifact bundles (a bounded scan of `swift-sdks/*/*/…`) and
	/// returns the `-Xswiftc` argument list that links it, or an empty list
	/// when no archive exists (full-stdlib sdk / older toolchains).
	private func unicodeTableLinkArgs(swiftBin: String, sdk: String) -> [String] {
		guard ProcessInfo.processInfo.environment["WEBUI_SKIP_UNICODE_TABLES"] == nil else { return [] }
		let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
		let sdksDir = home + "/Library/org.swift.swiftpm/swift-sdks"
		guard FileManager.default.fileExists(atPath: sdksDir) else { return [] }
		let bundles = (try? FileManager.default.contentsOfDirectory(atPath: sdksDir)) ?? []
		for bundle in bundles {
			guard bundle.hasSuffix(".artifactbundle") else { continue }
			let root = sdksDir + "/" + bundle
			let enumerator = FileManager.default.enumerator(atPath: root)
			while let relative = enumerator?.nextObject() as? String {
				guard relative.hasSuffix("libswiftUnicodeDataTables.a"),
				      relative.contains("/embedded/wasm32-unknown-wasip1/") else { continue }
				let archive = root + "/" + relative
				let libDir = URL(fileURLWithPath: archive).deletingLastPathComponent().path
				print("WebUIIsland: linking embedded unicode tables from \(libDir)")
				return [
					"-Xswiftc", "-Xlinker", "-Xswiftc", "-L\(libDir)",
					"-Xswiftc", "-Xlinker", "-Xswiftc", "-lswiftUnicodeDataTables",
				]
			}
		}
		return []
	}

	private static func copyFile(from: String, to: String) throws {
		try FileManager.default.createDirectory(
			at: URL(fileURLWithPath: to).deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		if FileManager.default.fileExists(atPath: to) {
			try FileManager.default.removeItem(atPath: to)
		}
		try FileManager.default.copyItem(atPath: from, toPath: to)
	}
}

enum WebUIIslandError: Error, CustomStringConvertible {
	case buildFailed(Int32)
	case artifactMissing(String)
	case stripFailed
	var description: String {
		switch self {
		case .buildFailed(let code): return "wasm island cross-build failed with exit \(code)"
		case .artifactMissing(let path): return "built island artifact missing at \(path)"
		case .stripFailed: return "custom-section strip of the island artifact failed"
		}
	}
}
