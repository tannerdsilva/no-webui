import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - WebUIThemeTool — the DX-15a theme-emission driver (mechanism (a))
//
// a framework executable a CONSUMER's build runs via the WebUIThemePlugin
// build-tool command. given the consumer's `ThemeCatalog` source file(s), it
// drives a DIRECT `swiftc` over them PLUS a generated driver main that calls
// `WebUIThemeBuild.emit`, and the emitted `WebUIShippedAsset` conformance lands
// in the plugin work dir (declared as the command's outputFile → SwiftPM
// compiles it into the consumer target). NO consumer tooling.
//
// the spike (dx2-notes/t-theme-spike-verdict.md) settled the two firsts:
//  (f1) `-load-plugin-executable <products>/WebUIDesignSystemMacros#…` loads —
//       the @Theme macro expands under direct swiftc, its deps resolving via
//       the dylib's @loader_path rpath into the same products dir;
//  (f2) `-I <products>` consumes the .build swiftmodules and `-L <products>` +
//       the rawdog/Logging C modulemaps link a real driver that ran
//       WebUIAssetBuilder.emit and wrote a valid conformance.
//
// the tool builds its invocation from its OWN location: a plugin tool product
// lives in `<root>/.build/out/Products/<config>/` next to the macro dylib, so
// `dirname(argv[0])` IS the products dir and the modulemaps dir is its stable
// sibling — no hard-coded build path, which is what keeps this working when a
// consumer's build root differs (dependency products land in the consumer's
// own .build/out).
//
// sandbox geometry (the dx-5 precedent, measured): the build command runs
// under `(allow process*) (allow file-read*)` — it may exec swiftc and read
// anywhere, but WRITE only to the plugin work dir (+ tmp + llvm cache). every
// intermediate therefore lands under the passed `--work-dir` (the plugin's
// work dir), and the outputFile (the generated asset) is declared by the
// plugin command, so SwiftPM's sandbox allows the write.
//
// ordering (f2's hard half, settled in the verdict): the tool is a framework
// PRODUCT of the same package, so `context.tool(named:)` forces SwiftPM to
// build it — and its dependency closure (WebUIDesignSystem → the macro dylib,
// WebUIThemeBuild, WebUIDesignSystemCore, WebUIBuild → rawdog/Logging) — BEFORE
// the plugin command runs. every .build product the driver needs therefore
// exists, and the plugin command never has to guess a target-product order.

enum ToolError: Error, CustomStringConvertible {
	case missingOption(String)
	case noCatalog
	case noThemeCatalogConformance(String)
	case buildFailed(String)
	case emitFailed(String)

	var description: String {
		switch self {
		case .missingOption(let o): return "missing value for \(o)"
		case .noCatalog: return "no theme catalog type named — pass --catalog <Type> or let the plugin scan for a ThemeCatalog conformance"
		case .noThemeCatalogConformance(let file): return "no `: ThemeCatalog` conformance found in \(file) — the consumer theme source must declare a ThemeCatalog"
		case .buildFailed(let text): return "swiftc failed:\n\(text)"
		case .emitFailed(let text): return "driver failed:\n\(text)"
		}
	}
}

@main
enum WebUIThemeTool {

	static func main() {
		let argv = Array(CommandLine.arguments.dropFirst())
		do {
			try run(argv)
		} catch {
			writeError("error: \(error)")
			exit(1)
		}
	}

	static func option(_ argv: [String], _ flag: String) -> String? {
		guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
		return argv[i + 1]
	}

	static func require(_ argv: [String], _ flag: String) throws -> String {
		guard let v = option(argv, flag) else { throw ToolError.missingOption(flag) }
		return v
	}

	static func writeError(_ text: String) {
		FileHandle.standardError.write(Data((text + "\n").utf8))
	}

	// MARK: - the emit verb

	static func run(_ argv: [String]) throws {
		let sources = try (require(argv, "--sources"))
			.split(separator: ",")
			.map(String.init)
		let catalog = try require(argv, "--catalog")
		let typeName = try require(argv, "--type-name")
		let output = try require(argv, "--output")
		let workDir = try require(argv, "--work-dir")

		// the products dir is where THIS tool lives (a plugin tool product).
		let productsDir = URL(fileURLWithPath: CommandLine.arguments[0])
			.deletingLastPathComponent()
		// .../Products/<config> -> two up is .../out -> sibling Intermediates.noindex.
		let moduleMapsDir = productsDir
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Intermediates.noindex/GeneratedModuleMaps")

		let macroPlugin = productsDir.appendingPathComponent("WebUIDesignSystemMacros")
		guard FileManager.default.fileExists(atPath: macroPlugin.path) else {
			throw ToolError.buildFailed("[WebUIThemeTool] macro plugin not found at \(macroPlugin.path) — the WebUIDesignSystemMacros product must be built first (the tool's dependency closure builds it)")
		}

		// the consumer's theme sources must each carry a ThemeCatalog conformance
		// (that is the contract the driver names by).
		for source in sources {
			guard let text = try? String(contentsOfFile: source, encoding: .utf8),
			      text.contains("ThemeCatalog") else {
				throw ToolError.noThemeCatalogConformance(source)
			}
		}

		// a driver main, generated beside the consumer's sources so the catalog
		// type is visible in the same compilation.
		let driverPath = (workDir as NSString).appendingPathComponent("ThemeEmitDriver.swift")
		let driver = Self.driverSource(catalog: catalog, typeName: typeName)
		try driver.write(toFile: driverPath, atomically: true, encoding: .utf8)

		// swiftc over [consumer theme sources] + [generated driver].
		let exe = (workDir as NSString).appendingPathComponent("theme-emit-driver")
		let modCache = (workDir as NSString).appendingPathComponent("ModuleCache")
		var cmd = [
			"/usr/bin/swiftc",
			// the spike's f1 mechanism detail: the compiler wraps external macro
			// plugin launches in its own sandbox-exec, and a nested sandbox
			// cannot apply inside SwiftPM's plugin-command seatbelt
			// (`sandbox_apply: Operation not permitted`). -disable-sandbox tells
			// the frontend not to re-sandbox the plugin process; the plugin then
			// runs under the command's own (allow process*) + (allow file-read*)
			// geometry, which is all it needs. verified: the sandboxed and
			// unsandboxed emissions are byte-identical.
			"-Xfrontend", "-disable-sandbox",
			"-load-plugin-executable", macroPlugin.path + "#WebUIDesignSystemMacros",
			"-I", productsDir.path,
			"-I", moduleMapsDir.path,
		]
		// the rawdog C shim modulemaps the swiftmodule interface pulls in.
		for shim in ["CRAW", "__crawdog_sha256", "__crawdog_argon2", "__crawdog_blake2"] {
			let mm = moduleMapsDir.appendingPathComponent(shim + ".modulemap")
			if FileManager.default.fileExists(atPath: mm.path) {
				cmd += ["-Xcc", "-fmodule-map-file=\(mm.path)"]
			}
		}
		cmd += ["-Xcc", "-I\(moduleMapsDir.path)"]
		cmd += sources
		cmd += [driverPath]
		cmd += ["-L", productsDir.path]
		// the link closure the driver symbols need. two layout spellings are
		// possible depending on how SwiftPM materialized the dependency: static
		// archives (`lib<M>.a` → `-l<M>`) in the classic layout, or per-module
		// whole objects (`<M>.o`, the new-build-system spelling a path
		// dependency produces). each module is linked either way; a missing
		// module is skipped so a framework dep that stops being needed never
		// hard-breaks emission (the undefined symbols would, if it were).
		//
		// WebUIDesignSystem is deliberately ABSENT from the closure: the
		// consumer theme source imports it (its `@Theme` attribute declaration
		// and re-exports), but every symbol the expanded macro references lives
		// in WebUIDesignSystemCore/WebUICore. linking the whole WebUIDesignSystem
		// object drags WebUI + its embedded assets (HTMLDocument, WebUIAssets…)
		// into the driver for zero reason.
		let linkModules = [
			"WebUIThemeBuild", "WebUIDesignSystemCore",
			"WebUIBuild", "WebUICore", "WebUISharedCore",
		]
		for module in linkModules {
			let archive = productsDir.appendingPathComponent("lib\(module).a")
			let object = productsDir.appendingPathComponent("\(module).o")
			if FileManager.default.fileExists(atPath: archive.path) {
				cmd += ["-l\(module)"]
			} else if FileManager.default.fileExists(atPath: object.path) {
				cmd += [object.path]
			} else {
				print("[WebUIThemeTool] warning: link module \(module) not found in \(productsDir.path) — the driver will fail at link if it references it")
			}
		}
		// loose object files SwiftPM does not archive (rawdog + Logging + CRAW
		// shims) — present in both layouts.
		for obj in ["RAW.o", "RAW_sha256.o", "Logging.o", "CRAW.o", "__crawdog_sha256.o", "__crawdog_argon2.o", "__crawdog_blake2.o"] {
			let p = productsDir.appendingPathComponent(obj)
			if FileManager.default.fileExists(atPath: p.path) {
				cmd += [p.path]
			}
		}
		cmd += ["-o", exe]
		cmd += ["-module-cache-path", modCache]

		let buildText = try runCaptured(cmd)
		print("[WebUIThemeTool] swiftc: \(buildText.trimmingCharacters(in: .whitespacesAndNewlines))")

		// run the driver: it writes the generated asset to `output`.
		guard FileManager.default.fileExists(atPath: exe) else {
			throw ToolError.buildFailed("driver executable missing at \(exe)")
		}
		let driverOut = try runCaptured([exe, output])
		print("[WebUIThemeTool] " + driverOut.trimmingCharacters(in: .whitespacesAndNewlines))
		guard FileManager.default.fileExists(atPath: output) else {
			throw ToolError.emitFailed("no asset written to \(output) by the theme driver")
		}
	}

	// MARK: - the generated driver

	/// the driver main compiled alongside the consumer's theme sources: it calls
	/// the library's emit entry point with the consumer's catalog metatype.
	static func driverSource(catalog: String, typeName: String) -> String {
		return """
		import Foundation
		import WebUIBuild
		import WebUIThemeBuild

		// generated by WebUIThemeTool — do not edit.

		@main
		struct ThemeEmitDriver {
			static func main() {
				guard CommandLine.arguments.count > 1 else { exit(2) }
				let output = URL(fileURLWithPath: CommandLine.arguments[1])
				do {
					let receipt = try WebUIThemeBuild.emit(
						catalog: \(catalog).self,
						typeName: \(literal(typeName)),
						options: WebUIAssetBuilder.Options(
							minify: true,
							prose: .check,
							contentType: "text/css; charset=utf-8"
						),
						to: output
					)
					print("emitted \\(receipt.typeName): \\(receipt.bytes) B, gzip \\(receipt.gzipBytes ?? 0) B, stamp \\(receipt.stamp)")
				} catch {
					FileHandle.standardError.write(Data("[emit failed] \\(error)\\n".utf8))
					exit(1)
				}
			}
		}
		"""
	}

	static func literal(_ text: String) -> String {
		let escaped = text
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
		return "\"\(escaped)\""
	}

	// MARK: - process helpers

	static func runCaptured(_ args: [String]) throws -> String {
		guard let exec = args.first else { return "" }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: exec)
		process.arguments = Array(args.dropFirst())
		let out = Pipe()
		let err = Pipe()
		process.standardOutput = out
		process.standardError = err
		try process.run()
		process.waitUntilExit()
		let outData = out.fileHandleForReading.readDataToEndOfFile()
		let errData = err.fileHandleForReading.readDataToEndOfFile()
		let outText = String(decoding: outData, as: UTF8.self)
		let errText = String(decoding: errData, as: UTF8.self)
		let joined = (outText + (errText.isEmpty ? "" : "\n" + errText))
		guard process.terminationStatus == 0 else {
			throw ToolError.buildFailed("'\(exec)' exited \(process.terminationStatus):\n\(joined)")
		}
		return joined
	}
}
