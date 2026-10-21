import Foundation
import PackagePlugin

/// `swift package --disable-sandbox plugin wasm-island [--product WebUIValidateIsland]`
///
/// cross-builds a capability island product with the official wasm sdk's **embedded**
/// variant, strips custom sections, and copies the artifact to the canonical
/// `.build/out/Products/Release-webassembly-wasm32/<product>.wasm` location the serving
/// seam reads. the embedded variant is what keeps an island kb-scale — the full-sdk link
/// of the same sources is ~40× larger — and the leaf the island builds against is
/// deliberately scalar-clean for that stdlib: keep island-bound code free of
/// `firstRange(of:)`, `String.contains(_:)` and grapheme-constructing APIs
/// (`Character(...)`, `String(decoding:as:)`), or the embedded compile fails. `--sdk`
/// overrides the default for a product that is not embedded-clean.
///
/// same constraints as the other cross-build verbs: `--disable-sandbox` (the nested swift
/// build re-enters its own sandbox), an isolated scratch root (the plugin invocation holds
/// the package `.build` lock), and the swiftly shim (the Xcode frontend cannot read the
/// wasm sdk's modules).
@main
struct WebUIIslandPlugin: CommandPlugin {
	func performCommand(
		context: PluginContext,
		arguments: [String]
	) throws {
		var product = "WebUIValidateIsland"
		var sdk = "swift-6.4.0-RELEASE_wasm-embedded"
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

		// artifact contract, part 0 — the graph shape the artifact audits rely on.
		// a deny-list derived from the manifest is worthless if an accidental
		// dependency edge can legitimise the leak, so pin the shape first: shared
		// modules depend only on each other, capability modules are leaves, and a
		// product owns at most one capability. fail before spending a cross-build.
		try auditDependencyGraph(package: context.package)

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

		// the embedded unicode tables are declared as a wasi-scoped linker
		// setting on `WebUIIslandRuntime` (see Package.swift), not passed here:
		// a global `-Xswiftc -lswiftUnicodeDataTables` also lands on the host
		// link of any macro target in the graph (rawdog's RAW_macros), where ld
		// rejects the wasm archive ("not a mach-o file").

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
		]
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
		// artifact contract, part 1 — the unstripped artifact still carries its
		// name section, so this is the only moment foreign capability symbols are
		// visible. an island that carries another capability's code is not an
		// island; fail the build rather than ship it.
		try auditSymbols(artifact: builtArtifact, product: product, swiftBin: swiftBin, context: context)

		let destination = outputOverride
			?? packageDir + "/.build/out/Products/Release-webassembly-wasm32/" + product + ".wasm"

		// the strip path below hands `WebUIWasmTool` an output beside `destination`, and the
		// tool does not create directories — on a checkout where
		// `.build/out/Products/Release-webassembly-wasm32/` does not exist yet (no artifact
		// has been produced), the write fails and the plugin reports "custom-section strip …
		// failed". `copyFile` creates the directory for the no-strip path; create it here for
		// both, before anything writes.
		try FileManager.default.createDirectory(
			at: URL(fileURLWithPath: destination).deletingLastPathComponent(),
			withIntermediateDirectories: true
		)

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

		// artifact contract, part 2 — the export surface is the wire contract,
		// checked on the artifact that actually ships (stripping removes the name
		// section, never the export section).
		try auditExports(artifact: destination, product: product, context: context)

		let size = (try? FileManager.default.attributesOfItem(atPath: destination)[.size] as? Int) ?? 0
		print("WebUIIsland: artifact ready at \(destination) (\(size) bytes\(noStrip ? ", unstripped" : ", custom-sections stripped"))")
	}

	// MARK: - artifact contract
	//
	// "island" is a build property, not a naming convention. the artifact may
	// define only its own capability's code plus the shared wire/runtime/leaf,
	// and it may export only the wire's entry points plus what its own sources
	// declare. both expectations are derived from the manifest and the sources —
	// no per-product allowlist to maintain — so a new capability is covered the
	// moment it exists, and a leaked one fails the build that produced it.

	private func auditSymbols(
		artifact: String,
		product: String,
		swiftBin: String,
		context: PluginContext
	) throws {
		let forbidden = Self.foreignCapabilityModules(product: product, package: context.package)
		guard !forbidden.isEmpty else {
			print("WebUIIsland: symbol audit: single island product, nothing foreign to check")
			return
		}
		guard let nm = Self.llvmNM(swiftBin: swiftBin) else {
			print("WebUIIsland: symbol audit SKIPPED (no llvm-nm; set WEBUI_LLVM_NM)")
			return
		}
		let listing = try Self.run(nm, ["--defined-only", artifact])
		var defined = 0
		var foreign: [(module: String, symbol: String)] = []
		for line in listing.split(separator: "\n") {
			let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
			guard parts.count == 3 else { continue }
			defined += 1
			let symbol = String(parts[2])
			guard let module = Self.moduleName(of: symbol), forbidden.contains(module) else { continue }
			foreign.append((module, symbol))
		}
		guard foreign.isEmpty else {
			for entry in foreign.prefix(8) {
				print("  foreign: \(entry.module)  \(entry.symbol)")
			}
			let modules = Set(foreign.map(\.module)).sorted()
			print("WebUIIsland: symbol audit FAILED — '\(product)' carries \(foreign.count) symbol(s) from \(modules)")
			throw WebUIIslandError.artifactViolation("\(product) carries foreign capability symbols: \(modules)")
		}
		print("WebUIIsland: symbol audit: \(defined) defined, 0 foreign (forbidden: \(forbidden.sorted()))")
	}

	/// the wire's canonical entry points. the gate ships with the framework, so it
	/// carries them; in-package it also cross-checks the runtime's `@_expose` set
	/// against this list, so the two can never drift apart silently.
	private static let standardExports: Set<String> = [
		"webui_input_ptr", "webui_frame_ptr", "webui_frame_len", "webui_render_region",
	]

	private func auditExports(
		artifact: String,
		product: String,
		context: PluginContext
	) throws {
		let bytes = Array(try Data(contentsOf: URL(fileURLWithPath: artifact)))
		let exported = Set(try Self.exportNames(bytes))
		let runtimeExposed = Set(Self.exposedNames(in: context.package, target: "WebUIIslandRuntime"))
		if !runtimeExposed.isEmpty, runtimeExposed != Self.standardExports {
			let drift = runtimeExposed.symmetricDifference(Self.standardExports).sorted()
			print("WebUIIsland: export audit: wire contract drifted \(drift)")
			throw WebUIIslandError.artifactViolation("WebUIIslandRuntime exports \(drift) beyond the canonical wire set")
		}
		let declared = Self.standardExports.union(Self.exposedNames(in: context.package, target: product))
		// wasm always exports memory, and a wasi command module exports _start;
		// everything else must be declared in source.
		let baseline: Set<String> = ["memory", "_start"]
		let missing = declared.subtracting(exported).sorted()
		let undeclared = exported.subtracting(declared).subtracting(baseline).sorted()
		guard missing.isEmpty, undeclared.isEmpty else {
			if !missing.isEmpty { print("WebUIIsland: export audit: missing \(missing)") }
			if !undeclared.isEmpty { print("WebUIIsland: export audit: undeclared \(undeclared)") }
			throw WebUIIslandError.artifactViolation("export surface of \(product) does not match its declarations")
		}
		print("WebUIIsland: export audit: \(exported.count) exports (\(exported.sorted().joined(separator: ", ")))")
	}

	/// the shared layer every island links. nothing here may depend on a capability.
	private static let sharedModules: Set<String> = [
		"WebUISharedCore", "WebUIIslandWire", "WebUIIslandWireRAW", "WebUIIslandRuntime",
	]

	/// graph rules, checked before any build:
	///   r1  a capability module is a leaf — it depends only on the shared layer
	///   r2  an island product owns at most one capability module
	///   r3  a shared module never depends on a capability module
	/// without these, the symbol audit's "foreign" set is self-referential: an
	/// accidental edge would move the leaked module into the product's own closure
	/// and the gate would call the leak legitimate.
	private func auditDependencyGraph(package: Package) throws {
		var byName: [String: Target] = [:]
		for target in package.targets { byName[target.name] = target }
		let products = package.targets.filter { $0.name.hasSuffix("Island") }
		guard !products.isEmpty else { return }

		var capability: Set<String> = []
		for product in products {
			capability.formUnion(Self.closure(of: product.name, in: byName).subtracting(Self.sharedModules))
		}
		capability.subtract(Set(products.map(\.name)))

		for shared in Self.sharedModules.sorted() {
			guard let target = byName[shared] else { continue }
			for dependency in target.dependencies {
				guard case .target(let dependency) = dependency, capability.contains(dependency.name) else { continue }
				throw WebUIIslandError.artifactViolation(
					"shared module \(shared) depends on capability module \(dependency.name) — the shared layer is capability-free"
				)
			}
		}

		for name in capability.sorted() {
			guard let target = byName[name] else { continue }
			for dependency in target.dependencies {
				guard case .target(let dependency) = dependency,
				      capability.contains(dependency.name), dependency.name != name
				else { continue }
				throw WebUIIslandError.artifactViolation(
					"capability module \(name) depends on capability module \(dependency.name) — capability modules are leaves"
				)
			}
		}

		for product in products {
			let owned = product.dependencies.compactMap { dependency -> String? in
				guard case .target(let target) = dependency, capability.contains(target.name) else { return nil }
				return target.name
			}
			guard owned.count <= 1 else {
				throw WebUIIslandError.artifactViolation(
					"\(product.name) owns \(owned.count) capability modules (\(owned.sorted())) — a product is one capability"
				)
			}
		}
	}

	private static func closure(of name: String, in byName: [String: Target]) -> Set<String> {
		var seen: Set<String> = []
		var stack = [name]
		while let current = stack.popLast() {
			guard seen.insert(current).inserted, let target = byName[current] else { continue }
			for dependency in target.dependencies {
				if case .target(let target) = dependency { stack.append(target.name) }
			}
		}
		return seen
	}

	/// capability modules another island product reaches but this one does not.
	/// the shared wire/runtime/leaf are never foreign, and neither is anything in
	/// this product's own closure (two fixtures sharing a helper is not a leak).
	private static func foreignCapabilityModules(product: String, package: Package) -> Set<String> {
		var byName: [String: Target] = [:]
		for target in package.targets { byName[target.name] = target }
		let own = closure(of: product, in: byName)
		var foreign: Set<String> = []
		for target in package.targets
		where target.name.hasSuffix("Island") && target.name != product {
			foreign.formUnion(closure(of: target.name, in: byName).subtracting(sharedModules).subtracting(own))
		}
		return foreign
	}

	private static func exposedNames(in package: Package, target name: String) -> [String] {
		guard let target = package.targets.first(where: { $0.name == name }) as? SwiftSourceModuleTarget else {
			return []
		}
		var names: [String] = []
		for file in target.sourceFiles where file.path.string.hasSuffix(".swift") {
			guard let text = try? String(contentsOfFile: file.path.string, encoding: .utf8) else { continue }
			var remainder = Substring(text)
			while let marker = remainder.range(of: "@_expose(wasm,") {
				remainder = remainder[marker.upperBound...]
				guard let open = remainder.firstIndex(of: "\""),
				      let close = remainder[remainder.index(after: open)...].firstIndex(of: "\"")
				else { break }
				names.append(String(remainder[remainder.index(after: open)..<close]))
				remainder = remainder[close...]
			}
		}
		return names
	}

	/// module name out of a swift symbol ($e15WebUIIslandWire… / $s15WebUIIslandWire…):
	/// skip the mangling prefix letters, read the length, take that many characters.
	private static func moduleName(of symbol: String) -> String? {
		guard let dollar = symbol.firstIndex(of: "$") else { return nil }
		var rest = symbol[symbol.index(after: dollar)...]
		while let character = rest.first, character.isLetter { rest = rest.dropFirst() }
		var digits = ""
		while let character = rest.first, character.isNumber {
			digits.append(character)
			rest = rest.dropFirst()
		}
		guard let length = Int(digits), length > 0,
		      let end = rest.index(rest.startIndex, offsetBy: length, limitedBy: rest.endIndex)
		else { return nil }
		return String(rest[rest.startIndex..<end])
	}

	/// wasm export section (id 7): count, then (name, kind, index) triples.
	private static func exportNames(_ bytes: [UInt8]) throws -> [String] {
		guard bytes.count > 8, bytes[0] == 0x00, bytes[1] == 0x61, bytes[2] == 0x73, bytes[3] == 0x6d else {
			throw WebUIIslandError.artifactViolation("not a wasm binary")
		}
		var cursor = 8
		func byte() -> UInt8 { defer { cursor += 1 }; return bytes[cursor] }
		func leb() -> Int {
			var result = 0
			var shift = 0
			while true {
				let chunk = byte()
				result |= Int(chunk & 0x7f) << shift
				if chunk & 0x80 == 0 { return result }
				shift += 7
			}
		}
		while cursor < bytes.count {
			let section = byte()
			let size = leb()
			let end = cursor + size
			guard section == 7 else {
				cursor = end
				continue
			}
			var names: [String] = []
			for _ in 0..<leb() {
				let length = leb()
				names.append(String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self))
				cursor += length
				_ = byte()  // kind
				_ = leb()   // index
			}
			return names
		}
		return []
	}

	private static func llvmNM(swiftBin: String) -> String? {
		let environment = ProcessInfo.processInfo.environment
		var candidates: [String] = []
		if let override = environment["WEBUI_LLVM_NM"], !override.isEmpty { candidates.append(override) }
		candidates.append((swiftBin as NSString).deletingLastPathComponent + "/llvm-nm")
		for probe in [
			(executable: "/usr/bin/which", arguments: ["llvm-nm"]),
			(executable: "/usr/bin/xcrun", arguments: ["--find", "llvm-nm"]),
		] {
			guard let found = try? run(probe.executable, probe.arguments) else { continue }
			let trimmed = found.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmed.isEmpty { candidates.append(trimmed) }
		}
		let toolchains = (environment["HOME"] ?? "") + "/Library/Developer/Toolchains"
		for entry in (try? FileManager.default.contentsOfDirectory(atPath: toolchains)) ?? [] {
			candidates.append(toolchains + "/" + entry + "/usr/bin/llvm-nm")
		}
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	private static func run(_ executable: String, _ arguments: [String]) throws -> String {
		guard FileManager.default.isExecutableFile(atPath: executable) else { return "" }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		process.waitUntilExit()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(data: data, encoding: .utf8) ?? ""
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
	case artifactViolation(String)
	var description: String {
		switch self {
		case .buildFailed(let code): return "wasm island cross-build failed with exit \(code)"
		case .artifactMissing(let path): return "built island artifact missing at \(path)"
		case .stripFailed: return "custom-section strip of the island artifact failed"
		case .artifactViolation(let reason): return "island artifact contract violated: \(reason)"
		}
	}
}
