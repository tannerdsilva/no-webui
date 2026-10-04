import Foundation
import WebUIBuild
#if os(Linux)
import Glibc
#else
import Darwin
#endif

// MARK: - the dx-5 `wasm-cross` verb (CONTINUUM_DX §2.5 candidate b)
//
// direct two-stage swiftc cross-compile of the REAL island graph — island
// main -> WebUIIslandCore -> WebUISharedCore (a zero-dep leaf) — for
// wasm32-unknown-wasip1 with the wasm sdk's EMBEDDED variant, `-Osize`,
// unicode data tables linked, custom sections stripped. this is the
// load-bearing DX-5 mechanism: no nested SwiftPM resolution (candidates
// (a)/(c) are dead per the red-team measurements), pure spawn + read from
// inside a build-tool-plugin command running under SwiftPM's
// `(allow process*) (allow file-read*)` sandbox, writing only to the
// declared writable zones (plugin work dir).
//
// the two-stage recipe mirrors the EXACT swiftc lines SwiftPM emits for
// `swift build --swift-sdk swift-6.4.0-RELEASE_wasm-embedded` (captured
// verbatim in the red-team's /tmp/dx-skeptic-a experiments and re-derived
// here at base ec1bcbc): compile each module with `-parse-as-library
// -package-name no-webui -static-stdlib -enable-experimental-feature
// Embedded -Osize -wmo`, link with `--gc-sections` + the embedded unicode
// tables archive (the one piece the stock link line omits, which fails on
// `_swift_stdlib_getNormData` otherwise).
//
// prereqs are PRE-CHECKED here with named diagnostics (a missing swiftly
// toolchain or wasm sdk bundle fails with a message naming the requirement,
// never with raw compiler output): the shim/toolchain swiftc must exist and
// the sdk artifactbundle must be present under
// `~/Library/org.swift.swiftpm/swift-sdks/`.

extension WebUIContinuumTool.Run {

	// MARK: - the dx-3 `measure` verb (CONTINUUM_DX §2.3 — auto-pinned budgets)
	//
	// `measure --work-dir <dir> --manifest <out.json>` scans the autobuild
	// work dir for the cross-built `<Product>.wasm` artifacts and writes the
	// measured per-island rows into the work-dir ContinuumManifest.json:
	//   name/maxBytes/maxGzipBytes  — the EXACT pin keys WebUIBudgetPlugin
	//     reads (name = the artifact product; the budget plugin matches by the
	//     same case-insensitive containment it already uses, so "validate" <-> 
	//     "WebUIValidateIsland.wasm" and "feed" <-> "FeedIsland.wasm" both
	//     resolve) — plus ADDITIVE raw/gz/sha/url beside the pins (never
	//     replacing them — the red-team fold).
	//   maxBytes = ceil(raw × 1.05); maxGzipBytes = ceil(gz × 1.05); sha over
	//     the STRIPPED artifact (WebUIBuild's rawdog-sha path, public facade);
	//     url = the existing URL convention "/__assets/webui-<name>.wasm".
	//
	// the plugin invokes this as its OWN build command (declared inputFiles =
	// every island artifact, outputFiles = the manifest), so llbuild orders it
	// AFTER the cross-build commands and skips it when no artifact changed —
	// no per-command sidecar writes, no shared-file races. the manifest the
	// budget plugin reads is found by the same plugin-outputs walk as the
	// generate-path one; at serve-emission WebUIServer splices these rows into
	// the served /ui/continuum-manifest.json (generate path stays
	// authoritative for allowlist/union), so one payload carries both.
	static func measure(_ argv: [String]) throws {
		let workDir = try Args.require(argv, "--work-dir")
		let manifest = try Args.require(argv, "--manifest")
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: workDir) else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] measure: cannot list work dir \(workDir)")
			exit(1)
		}
		var rows: [String] = []
		for file in entries.filter({ $0.hasSuffix(".wasm") }).sorted() {
			let path = (workDir as NSString).appendingPathComponent(file)
			guard let bytes = FileManager.default.contents(atPath: path), !bytes.isEmpty else { continue }
			let raw = bytes.count
			let gz = gzip(Data(bytes))?.count
			let sha = sha256Hex([UInt8](bytes))
			let name = (file as NSString).deletingPathExtension
			let maxBytes = Int((Double(raw) * 1.05).rounded(.up))
			var row = "{\"name\":\"\(name)\",\"maxBytes\":\(maxBytes),\"raw\":\(raw),\"sha\":\"\(sha)\",\"url\":\"/__assets/webui-\(name).wasm\""
			if let gz {
				row += ",\"gz\":\(gz),\"maxGzipBytes\":\(Int((Double(gz) * 1.05).rounded(.up)))"
			}
			row += "}"
			rows.append(row)
		}
		// one payload: the budget plugin reads islands[] (schema name/maxBytes/
		// maxGzipBytes); NEW raw/gz/sha/url sit alongside, additive, version 2.
		let payload = "{\n  \"kind\": \"continuum-engine-slice\",\n  \"version\": 2,\n  \"islands\": ["
			+ rows.joined(separator: ",\n") + "]\n}\n"
		try payload.write(toFile: manifest, atomically: true, encoding: .utf8)
		print("[WebUIAutobuild] measure: \(rows.count) island(s) pinned into \(manifest) (raw/gz/sha + maxBytes/maxGzipBytes)")
	}

	/// `wasm-cross --graph <pkg root> --product <Island> --obj <dir> --out <artifact.wasm>
	///              [--main-dir <dir>] [--sdk <id>] [--swiftc <path>] [--mod-cache <dir>]
	///              [--no-strip] [--skip-unicode-tables]`
	static func wasmCross(_ argv: [String]) throws {
		let graph = try Args.require(argv, "--graph")
		let product = try Args.require(argv, "--product")
		let obj = try Args.require(argv, "--obj")
		let out = try Args.require(argv, "--out")
		// the island's own source dir: by default the graph's
		// `Sources/<product>`, overridable when a consumer island lives in the
		// ATTACHED package rather than the graph package (the plugin passes
		// it for attached-package islands).
		let mainDir = Args.option(argv, "--main-dir") ?? (graph + "/Sources/" + product)
		let sdkID = Args.option(argv, "--sdk") ?? "swift-6.4.0-RELEASE_wasm-embedded"
		let swiftcPath = Args.option(argv, "--swiftc") ?? defaultSwiftcPath()
		let modCache = Args.option(argv, "--mod-cache") ?? (obj + "/ModuleCache")
		let noStrip = Args.has(argv, "--no-strip")
		let skipUnicode = Args.has(argv, "--skip-unicode-tables")

		// the island graph's leaf modules must be on disk (their sources are
		// declared build inputs; a missing graph is a wiring bug, not a
		// silent skip).
		let sharedDir = graph + "/Sources/WebUISharedCore"
		let islandDir = graph + "/Sources/WebUIIslandCore"
		guard FileManager.default.fileExists(atPath: sharedDir),
		      FileManager.default.fileExists(atPath: islandDir),
		      FileManager.default.fileExists(atPath: mainDir) else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cannot cross-build '\(product)': island graph not found under \(graph) (expected Sources/WebUISharedCore, Sources/WebUIIslandCore, main dir \(mainDir))")
			exit(1)
		}

		// recursion guard (backstop): the nested-build convention
		// (`WEBUI_ISLAND_NESTED=1`) aborts the cross-build instead of
		// recursing. with direct swiftc there is no nested build today, so
		// this only fires when a future mechanism reintroduces nesting.
		if ProcessInfo.processInfo.environment["WEBUI_ISLAND_NESTED"] == "1" {
			print("[WebUIAutobuild] \(product): recursion guard set (WEBUI_ISLAND_NESTED=1) — skipping")
			return
		}

		// prereq #1: the wasm-capable compiler (the swiftly-hosted toolchain
		// swiftc — NOT the Xcode frontend, which lacks swift-autolink-extract
		// and cannot read the sdk's prebuilt modules).
		guard FileManager.default.fileExists(atPath: swiftcPath) else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cannot cross-build '\(product)': no wasm-capable swiftc at \(swiftcPath). the swiftly toolchain (swift-6.4) is a one-time machine prerequisite — install it via `swiftly`, or point --swiftc at ~/.swiftly/bin/swiftc / the swiftly-hosted toolchain's swiftc.")
			exit(1)
		}

		// prereq #2: the wasm sdk artifactbundle (missing => run `swift sdk list`).
		guard let sdk = resolveWasmSDK(sdkID: sdkID) else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cannot cross-build '\(product)': no Swift SDK bundle found for query '\(sdkID)' under \(NSHomeDirectory())/Library/org.swift.swiftpm/swift-sdks. run `swiftly run swift sdk list` / install the wasm sdk bundle (one-time machine prerequisite), or pass --sdk with an installed id.")
			exit(1)
		}
		let resourceDir = sdk + "/swift.xctoolchain/usr/lib/swift"
		guard FileManager.default.fileExists(atPath: resourceDir) else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cannot cross-build '\(product)': sdk bundle at \(sdk) has no swift.xctoolchain/usr/lib/swift resource dir — is it a wasm sdk?")
			exit(1)
		}

		// writable zones: everything lands in the caller-provided dirs (the
		// plugin work dir — the sandbox's only package-adjacent writable
		// zone on a home-dir checkout).
		try FileManager.default.createDirectory(atPath: obj, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(atPath: modCache, withIntermediateDirectories: true)

		guard let sharedFiles = swiftFiles(in: sharedDir), !sharedFiles.isEmpty,
		      let islandFiles = swiftFiles(in: islandDir), !islandFiles.isEmpty,
		      let mainFiles = swiftFiles(in: mainDir), !mainFiles.isEmpty else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cannot cross-build '\(product)': no source files under \(sharedDir)/\(islandDir)/\(mainDir)")
			exit(1)
		}

		let wasiSdk = sdk + "/WASI.sdk"
		let base: [String] = [
			"-parse-as-library",
			"-package-name", "no-webui",
			"-resource-dir", resourceDir,
			"-Xcc", "-resource-dir", "-Xcc", resourceDir + "/clang",
			"-static-stdlib",
			"-enable-experimental-feature", "Embedded",
			"-sdk", wasiSdk,
			"-sysroot", wasiSdk,
			"-target", "wasm32-unknown-wasip1",
			"-swift-version", "6",
			"-module-cache-path", modCache,
			"-Osize",
			"-wmo",
		]

		// stage 1a: the zero-dep leaf.
		try runTool(swiftcPath, base + [
			"-module-name", "WebUISharedCore",
			"-emit-module", "-emit-module-path", obj + "/WebUISharedCore.swiftmodule",
			"-I", obj, "-c",
		] + sharedFiles + ["-o", obj + "/WebUISharedCore.o"])

		// stage 1b: the island core (imports the leaf).
		try runTool(swiftcPath, base + [
			"-module-name", "WebUIIslandCore",
			"-emit-module", "-emit-module-path", obj + "/WebUIIslandCore.swiftmodule",
			"-I", obj, "-c",
		] + islandFiles + ["-o", obj + "/WebUIIslandCore.o"])

		// stage 1c: the island main (imports the core; the wasi reactor).
		try runTool(swiftcPath, base + [
			"-module-name", product,
			"-I", obj, "-c",
		] + mainFiles + ["-o", obj + "/main.o"])

		// stage 2: the link line. mirror the ground-truth line exactly
		// (`-target wasm32-unknown-wasip1 -emit-executable … -static-stdlib
		// -enable-experimental-feature Embedded -wmo -Xlinker -lc++
		// -Xlinker -lswift_Concurrency …`) PLUS the embedded unicode data
		// tables archive the stock line omits (`-lswiftUnicodeDataTables`
		// from the sdk's own `embedded/wasm32-unknown-wasip1` dir).
		var link: [String] = [
			"-target", "wasm32-unknown-wasip1",
			"-emit-executable",
			"-sysroot", wasiSdk,
			"-sdk", wasiSdk,
			"-Xclang-linker", "-resource-dir", "-Xclang-linker", resourceDir + "/clang",
			"-resource-dir", resourceDir,
			"-L", obj,
			"-Xlinker", "--gc-sections",
			"-Xclang-linker", "-rdynamic",
			"-static-stdlib",
			"-enable-experimental-feature", "Embedded",
			"-wmo",
			"-Xlinker", "-lc++",
			"-Xlinker", "-lswift_Concurrency",
		]
		if let toolchainLib = swiftlyToolchainLibPath() {
			link += ["-L", toolchainLib]
		}
		link += ["-L", "/usr/lib/swift"]
		let embedLib = resourceDir + "/embedded/wasm32-unknown-wasip1"
		if !skipUnicode, FileManager.default.fileExists(atPath: embedLib + "/libswiftUnicodeDataTables.a") {
			link += ["-Xlinker", "-L" + embedLib, "-Xlinker", "-lswiftUnicodeDataTables"]
		}
		link += [obj + "/WebUISharedCore.o", obj + "/WebUIIslandCore.o", obj + "/main.o", "-o", out]
		try runTool(swiftcPath, link)

		// stage 3: validate + strip custom sections (the shipped artifact
		// drops its name table + DWARF — same transform WebUIWasmTool does,
		// replicated here so the build command is self-contained).
		guard let artifactData = FileManager.default.contents(atPath: out), !artifactData.isEmpty else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cross-build of '\(product)' produced no artifact at \(out)")
			exit(1)
		}
		let artifact = [UInt8](artifactData)
		try validateWasm(artifact, product: product, at: out)
		var finalBytes = artifact
		if !noStrip {
			finalBytes = try stripCustomSections(artifact)
			guard let _ = try? Data(finalBytes).write(to: URL(fileURLWithPath: out), options: .atomic) else {
				WebUIContinuumTool.writeError("[WebUIAutobuild] strip: cannot write stripped artifact to \(out)")
				exit(1)
			}
		}
		print("[WebUIAutobuild] \(product): cross-built \(artifact.count) -> \(finalBytes.count) bytes (embedded, \(noStrip ? "unstripped" : "custom sections stripped")) at \(out)")
	}

	// MARK: - prereq resolution

	/// the swiftc to use: default = the swiftly-hosted toolchain swiftc
	/// (globbed from ~/Library/Developer/Toolchains), falling back to the
	/// swiftly shim. mirrors what the manual verb's nested SwiftPM actually
	/// executes (`<toolchain>/usr/bin/swiftc`), never the Xcode frontend.
	static func defaultSwiftcPath() -> String {
		if let toolchainBin = swiftlyToolchainBinPath() {
			return toolchainBin
		}
		let shim = NSHomeDirectory() + "/.swiftly/bin/swiftc"
		return FileManager.default.fileExists(atPath: shim) ? shim : "/usr/bin/swiftc"
	}

	/// `~/Library/Developer/Toolchains/swift-*.xctoolchain/usr/bin/swiftc`
	/// (newest first), or nil.
	static func swiftlyToolchainBinPath() -> String? {
		guard let dir = swiftlyToolchainDirPath() else { return nil }
		let bin = dir + "/usr/bin/swiftc"
		return FileManager.default.fileExists(atPath: bin) ? bin : nil
	}

	static func swiftlyToolchainDirPath() -> String? {
		let toolchains = NSHomeDirectory() + "/Library/Developer/Toolchains"
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: toolchains) else { return nil }
		let dirs = entries.filter { $0.hasSuffix(".xctoolchain") }.sorted()
		guard let latest = dirs.last else { return nil }
		return toolchains + "/" + latest
	}

	static func swiftlyToolchainLibPath() -> String? {
		swiftlyToolchainDirPath().map { $0 + "/usr/lib/swift" }
	}

	/// resolve the `--swift-sdk` id to the sdk's per-triple resource root.
	/// the `-embedded` variant ships inside the same artifactbundle as the
	/// base id, so a bundle id is tried verbatim and with the `-embedded`
	/// suffix trimmed.
	static func resolveWasmSDK(sdkID: String) -> String? {
		let sdks = NSHomeDirectory() + "/Library/org.swift.swiftpm/swift-sdks"
		guard let bundles = try? FileManager.default.contentsOfDirectory(atPath: sdks) else { return nil }
		for candidate in [sdkID, sdkID.replacingOccurrences(of: "-embedded", with: "")] {
			guard let bundle = bundles.first(where: { $0 == candidate + ".artifactbundle" }) else { continue }
			// the bundle contains an inner directory named after the sdk.
			let root = sdks + "/" + bundle
			guard let inner = try? FileManager.default.contentsOfDirectory(atPath: root)
				.first(where: { $0.hasPrefix("swift-") }) else { continue }
			// the resource root lives under <inner>/<triple>/ — component dirs
			// holding `WASI.sdk` + `swift.xctoolchain`.
			let innerRoot = root + "/" + inner
			guard let children = try? FileManager.default.contentsOfDirectory(atPath: innerRoot) else { continue }
			if let tripleDir = children.first(where: {
				FileManager.default.fileExists(atPath: innerRoot + "/" + $0 + "/swift.xctoolchain")
			}) {
				return innerRoot + "/" + tripleDir
			}
		}
		return nil
	}

	// MARK: - process + helpers

	/// spawn a compiler step; on failure dump stderr and exit with the named
	/// step so the build error names the stage.
	static func runTool(_ swiftc: String, _ args: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: swiftc)
		process.arguments = args
		var environment = ProcessInfo.processInfo.environment
		environment["WEBUI_ISLAND_NESTED"] = "1"
		process.environment = environment
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		process.waitUntilExit()
		let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
		guard process.terminationStatus == 0 else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] cross-build stage failed (swiftc exit \(process.terminationStatus)):")
			WebUIContinuumTool.writeError(output)
			exit(1)
		}
		if !output.isEmpty {
			print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
		}
	}

	static func swiftFiles(in dir: String) -> [String]? {
		guard let enumerator = FileManager.default.enumerator(atPath: dir) else { return nil }
		var files: [String] = []
		while let relative = enumerator.nextObject() as? String {
			guard relative.hasSuffix(".swift") else { continue }
			// skip .build / hidden dirs should they ever be nested here.
			if relative.contains("/.build/") { continue }
			files.append(dir + "/" + relative)
		}
		return files.sorted()
	}

	/// structural wasm validation — magic + version v1, the same gate
	/// WebUIWasmTool applies.
	static func validateWasm(_ bytes: [UInt8], product: String, at path: String) throws {
		guard bytes.count >= 8,
		      bytes[0] == 0x00, bytes[1] == 0x61, bytes[2] == 0x73, bytes[3] == 0x6D else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] \(product): artifact at \(path) does not start with the webassembly magic bytes (\0asm)")
			exit(1)
		}
		guard bytes[4] == 0x01, bytes[5] == 0x00, bytes[6] == 0x00, bytes[7] == 0x00 else {
			WebUIContinuumTool.writeError("[WebUIAutobuild] \(product): artifact at \(path) has webassembly version != 1")
			exit(1)
		}
	}

	/// splice out every custom section (id 0): the name table, DWARF — the
	/// same transform WebUIWasmTool performs (kept here so the build command
	/// is self-contained with no second tool).
	static func stripCustomSections(_ bytes: [UInt8]) throws -> [UInt8] {
		var out = [UInt8](bytes[0 ..< 8])
		var i = 8
		while i < bytes.count {
			let sectionID = bytes[i]; i += 1
			let (size, after) = try leb128(bytes, from: i)
			i = after
			guard i + size <= bytes.count else {
				WebUIContinuumTool.writeError("[WebUIAutobuild] strip: truncated wasm section")
				exit(1)
			}
			if sectionID != 0 {
				out.append(sectionID)
				appendLeb128(&out, size)
				out.append(contentsOf: bytes[i ..< i + size])
			}
			i += size
		}
		return out
	}

	static func leb128(_ bytes: [UInt8], from start: Int) throws -> (Int, Int) {
		var result = 0
		var shift = 0
		var i = start
		while i < bytes.count {
			let b = bytes[i]; i += 1
			result |= Int(b & 0x7f) << shift
			if b & 0x80 == 0 { return (result, i) }
			shift += 7
			if shift > 63 {
				WebUIContinuumTool.writeError("[WebUIAutobuild] strip: LEB128 exceeds 64 bits")
				exit(1)
			}
		}
		WebUIContinuumTool.writeError("[WebUIAutobuild] strip: truncated LEB128")
		exit(1)
	}

	static func appendLeb128(_ out: inout [UInt8], _ value: Int) {
		var v = value
		repeat {
			var b = UInt8(v & 0x7f)
			v >>= 7
			if v != 0 { b |= 0x80 }
			out.append(b)
		} while v != 0
	}
}
