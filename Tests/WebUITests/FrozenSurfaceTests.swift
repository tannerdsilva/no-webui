import Testing
import Foundation

// the frozen surface, generated — the enforcement arm of
// `Documentation/STABILITY.md`. `Documentation/frozen-surface.symbols` is a
// generated list, not hand-maintained: `swift-symbolgraph-extract` (a real
// toolchain tool — `swift package` has no `api` verb, and the external
// `swift-package-tool` binary enumerates top-level declarations only) runs
// over the built product modules and emits member-level symbols — public
// inits, methods, properties, enum cases, typealiases, macros — which are
// canonicalized here into sorted, deduplicated per-module sections.
//
// the gate fails when the committed list and a fresh extraction diverge,
// naming every added and removed symbol, so the list cannot go stale
// silently. moving the surface means regenerating: `FROZEN_SURFACE_EMIT=1
// swift test --filter FrozenSurfaceTests` rewrites the file in place, and the
// regeneration is committed in the same commit as the api change, justified
// there.
//
// the tool is a stated prerequisite: any swift toolchain ships
// `swift-symbolgraph-extract` (this package builds with swiftpm 6.4 / swift
// 6). it is deliberately NOT wired into `swift build` — this repo has no CI,
// and an undeclared build dependency would break a fresh clone.

enum FrozenSurface {
	// the products plus the modules their `@_exported` cores re-export
	// (WebUI → WebUICore → WebUISharedCore, WebUIDesignSystem →
	// WebUIDesignSystemCore): the public surface a consumer reaches through
	// `import WebUI` / `WebUIDesignSystem` / `WebUIAuth` / `WebUIChart`.
	static let modules: [String] = [
		"WebUISharedCore", "WebUICore", "WebUI",
		"WebUIDesignSystemCore", "WebUIDesignSystem",
		"WebUIAuth", "WebUIChart", "WebUIServer",
	]

	static let fileName = "Documentation/frozen-surface.symbols"

	// symbol kinds that represent declared, callable public surface. extension
	// blocks and generic type parameters are structural, not callable; their
	// members are attributed to the extended nominal by the extractor.
	private static let wantedKinds: Set<String> = [
		"swift.enum", "swift.struct", "swift.class", "swift.protocol",
		"swift.typealias", "swift.func", "swift.func.op",
		"swift.enum.case", "swift.init", "swift.method", "swift.type.method",
		"swift.property", "swift.type.property",
		"swift.subscript", "swift.type.subscript",
		"swift.associatedtype", "swift.macro",
	]

	struct Surface {
		var symbols: [String: Set<String>] = [:]
		var total: Int { symbols.values.reduce(0) { $0 + $1.count } }
	}

	// MARK: - tool resolution

	static func packageRoot(from file: String = #filePath) -> URL {
		var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
		while dir.path != "/" {
			if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
				return dir
			}
			dir = dir.deletingLastPathComponent()
		}
		return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	}

	private static func run(_ executable: String, _ arguments: [String]) throws -> (code: Int32, out: String, err: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = [executable] + arguments
		let outPipe = Pipe()
		let errPipe = Pipe()
		process.standardOutput = outPipe
		process.standardError = errPipe
		try process.run()
		process.waitUntilExit()
		let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		return (process.terminationStatus, out, err)
	}

	static func extractorPath() throws -> String {
		let viaXcrun = try run("xcrun", ["-f", "swift-symbolgraph-extract"])
		if viaXcrun.code == 0, !viaXcrun.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return viaXcrun.out.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		let viaPath = try run("swift-symbolgraph-extract", ["--version"])
		if viaPath.code == 0 {
			return "swift-symbolgraph-extract"
		}
		throw FrozenSurfaceError.toolMissing
	}

	static func sdkPath() throws -> String {
		let result = try run("xcrun", ["--show-sdk-path"])
		guard result.code == 0 else { throw FrozenSurfaceError.contextUnavailable("xcrun --show-sdk-path failed: \(result.err)") }
		return result.out.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	static func hostTriple() throws -> String {
		let result = try run("swiftc", ["-print-target-info"])
		guard result.code == 0,
			let data = result.out.data(using: .utf8),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let target = json["target"] as? [String: Any],
			let triple = target["triple"] as? String
		else { throw FrozenSurfaceError.contextUnavailable("swiftc -print-target-info failed: \(result.err)") }
		return triple
	}

	// the package's .build is probed at runtime: the module dir and the
	// generated C-module modulemaps move with the scratch path, and the
	// rawdog `CRAW` c-family modules need explicit -fmodule-map-file flags.
	static func buildContext(root: URL) -> (includeDirs: [String], moduleMaps: [String]) {
		var includeDirs: [String] = []
		var moduleMaps: [String] = []
		let buildRoot = root.appendingPathComponent(".build")
		guard let enumerator = FileManager.default.enumerator(
			at: buildRoot,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		) else { return (includeDirs, moduleMaps) }
		var moduleMapDirs: [String] = []
		while let element = enumerator.nextObject() as? URL {
			let last = element.lastPathComponent
			if ["repositories", "artifacts"].contains(last) {
				enumerator.skipDescendants()
				continue
			}
			var isDir: ObjCBool = false
			FileManager.default.fileExists(atPath: element.path, isDirectory: &isDir)
			guard isDir.boolValue else { continue }
			if last == "GeneratedModuleMaps" {
				moduleMapDirs.append(element.path)
			}
			// swift modules live in a directory that contains a WebUI.swiftmodule
			if FileManager.default.fileExists(atPath: element.appendingPathComponent("WebUI.swiftmodule").path) {
				includeDirs.append(element.path)
			}
		}
		// `.build/debug` and `.build/out/Products/Debug` are the canonical ones
		for candidate in ["debug", "out/Products/Debug"] {
			let path = buildRoot.appendingPathComponent(candidate)
			if FileManager.default.fileExists(atPath: path.appendingPathComponent("WebUI.swiftmodule").path) {
				includeDirs.append(path.path)
			}
		}
		// c-family modulemaps come from two places: the build's generated ones
		// (rawdog CRAW, the swift-nio CNIOnes, …) and the ones dependency
		// checkouts ship themselves (swift-atomics `_AtomicsShims`, …).
		for dir in moduleMapDirs + [buildRoot.appendingPathComponent("checkouts").path] {
			guard let walker = FileManager.default.enumerator(
				at: URL(fileURLWithPath: dir),
				includingPropertiesForKeys: [.isDirectoryKey],
				options: []
			) else { continue }
			while let element = walker.nextObject() as? URL {
				if element.pathExtension == "modulemap" {
					moduleMaps.append(element.path)
				}
			}
		}
		includeDirs = Array(Set(includeDirs))
		moduleMaps = Array(Set(moduleMaps))
		return (includeDirs.sorted(), moduleMaps.sorted())
	}

	// MARK: - extraction

	static func extractModule(_ name: String, extractor: String, sdk: String, triple: String, includeDirs: [String], moduleMaps: [String]) throws -> Set<String> {
		let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("frozen-surface-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: workDir) }

		var arguments: [String] = []
		arguments += ["-module-name", name]
		for dir in includeDirs { arguments += ["-I", dir] }
		for map in moduleMaps { arguments += ["-Xcc", "-fmodule-map-file=\(map)"] }
		arguments += ["-sdk", sdk, "-output-dir", workDir.path, "-target", triple, "-minimum-access-level", "public", "-pretty-print"]

		let result = try run(extractor, arguments)
		guard result.code == 0 else {
			throw FrozenSurfaceError.extractionFailed(name, result.err)
		}

		var symbols = Set<String>()
		let files = (try? FileManager.default.contentsOfDirectory(atPath: workDir.path)) ?? []
		for file in files.sorted() where file.hasSuffix(".symbols.json") {
			// attribute the module's own file plus any re-export (`@`) files
			let isOwn = file == "\(name).symbols.json" || file.hasPrefix("\(name)@")
			guard isOwn, let data = try? Data(contentsOf: workDir.appendingPathComponent(file)) else { continue }
			guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let rawSymbols = json["symbols"] as? [[String: Any]]
			else { continue }
			for symbol in rawSymbols {
				guard let kind = (symbol["kind"] as? [String: Any])?["identifier"] as? String,
					wantedKinds.contains(kind),
					let identifier = (symbol["identifier"] as? [String: Any])?["precise"] as? String,
					!identifier.contains("SYNTHESIZED"),
					let pathComponents = symbol["pathComponents"] as? [String],
					!pathComponents.isEmpty
				else { continue }
				symbols.insert(pathComponents.joined(separator: "."))
			}
		}
		return symbols
	}

	static func extractAll(root: URL) throws -> Surface {
		let extractor = try extractorPath()
		let sdk = try sdkPath()
		let triple = try hostTriple()
		let context = buildContext(root: root)
		guard !context.includeDirs.isEmpty else {
			throw FrozenSurfaceError.contextUnavailable("no .build product modules found (\(root.path)/.build); run `swift build` first")
		}
		var surface = Surface()
		for module in modules {
			surface.symbols[module] = try extractModule(module, extractor: extractor, sdk: sdk, triple: triple, includeDirs: context.includeDirs, moduleMaps: context.moduleMaps)
		}
		return surface
	}

	// MARK: - the committed list

	static func render(_ surface: Surface) -> String {
		var lines: [String] = []
		lines.append("# generated — do not hand-edit.")
		lines.append("#")
		lines.append("# the frozen surface, emitted by `swift-symbolgraph-extract` (a real toolchain")
		lines.append("# tool — `swift package` has no `api` verb — over the built product modules,")
		lines.append("# canonicalized to member-level symbols: public inits, methods, properties,")
		lines.append("# enum cases, typealiases, macros. compiler-synthesized members are excluded.")
		lines.append("#")
		lines.append("# regenerate (`FROZEN_SURFACE_EMIT=1 swift test --filter FrozenSurfaceTests`")
		lines.append("# rewrites this file in place) and commit alongside the api change that")
		lines.append("# forced it. `Tests/WebUITests/FrozenSurfaceTests.swift` fails when this")
		lines.append("# file and a fresh extraction diverge, naming every added and removed symbol.")
		lines.append("#")
		lines.append("# re-measured 2026-10-09: \(surface.total) symbols across \(FrozenSurface.modules.count) modules.")
		lines.append("")
		for module in FrozenSurface.modules {
			lines.append("## \(module)")
			lines.append("")
			let symbols = surface.symbols[module] ?? []
			lines.append(contentsOf: symbols.sorted())
			lines.append("")
		}
		return lines.joined(separator: "\n")
	}

	static func parse(_ text: String) -> Surface {
		var surface = Surface()
		var current: String? = nil
		for rawLine in text.components(separatedBy: "\n") {
			let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
			if line.isEmpty { continue }
			if line.hasPrefix("## ") {
				current = String(line.dropFirst(3))
				continue
			}
			if line.hasPrefix("#") { continue }
			if let current {
				surface.symbols[current, default: []].insert(line)
			}
		}
		return surface
	}

	static func committedURL(root: URL) -> URL {
		root.appendingPathComponent(fileName)
	}
}

enum FrozenSurfaceError: Error, CustomStringConvertible {
	case toolMissing
	case contextUnavailable(String)
	case extractionFailed(String, String)

	var description: String {
		switch self {
		case .toolMissing:
			return "swift-symbolgraph-extract not found (via xcrun or PATH). it ships with every swift toolchain — install one (this package builds with swiftpm 6.4 / swift 6), or point PATH/DEVELOPER_DIR at it."
		case .contextUnavailable(let message):
			return message
		case .extractionFailed(let module, let stderr):
			return "swift-symbolgraph-extract failed for \(module): \(stderr)"
		}
	}
}

@Suite struct FrozenSurfaceTests {
	// the frozen surface is generated, not hand-maintained: this fails when
	// the committed list and a fresh toolchain extraction diverge, naming the
	// added and removed symbols. to move the surface, run with
	// `FROZEN_SURFACE_EMIT=1` and commit the rewritten file with the change.
	@Test func frozenSurfaceIsGeneratedAndComplete() throws {
		let root = FrozenSurface.packageRoot()
		let live = try FrozenSurface.extractAll(root: root)

		if ProcessInfo.processInfo.environment["FROZEN_SURFACE_EMIT"] == "1" {
			let text = FrozenSurface.render(live)
			try text.write(to: FrozenSurface.committedURL(root: root), atomically: true, encoding: .utf8)
			return
		}

		let committed: FrozenSurface.Surface
		do {
			let text = try String(contentsOf: FrozenSurface.committedURL(root: root), encoding: .utf8)
			committed = FrozenSurface.parse(text)
		} catch {
			Issue.record(Comment(rawValue: "missing \(FrozenSurface.fileName) — run `FROZEN_SURFACE_EMIT=1 swift test --filter FrozenSurfaceTests` to generate it"))
			return
		}

		var added: [String] = []
		var removed: [String] = []
		for module in FrozenSurface.modules {
			let liveSet = live.symbols[module] ?? []
			let committedSet = committed.symbols[module] ?? []
			for symbol in liveSet.subtracting(committedSet).sorted() {
				added.append("\(module).\(symbol)")
			}
			for symbol in committedSet.subtracting(liveSet).sorted() {
				removed.append("\(module).\(symbol)")
			}
		}

		if !added.isEmpty || !removed.isEmpty {
			var message = "frozen surface drifted (\(added.count) added, \(removed.count) removed). regenerate with `FROZEN_SURFACE_EMIT=1 swift test --filter FrozenSurfaceTests` and commit with the change:\n"
			for symbol in added.prefix(60) { message += "  + \(symbol)\n" }
			for symbol in removed.prefix(60) { message += "  - \(symbol)\n" }
			if added.count > 60 || removed.count > 60 {
				message += "  …"
			}
			Issue.record(Comment(rawValue: message))
		}
	}
}
