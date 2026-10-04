import Foundation
import WebUIBuild

// MARK: - the dx-8 `verify` verb (CONTINUUM_DX §4.7, W3) — the ONE consumer-facing
// island verification verb
//
// runs the FULL island verification path and prints a per-stage verdict:
//   1. build        — host `swift build` of the package (the island mains + the
//                     app compile natively; a consumer's attached
//                     WebUIAutobuildPlugin cross-builds + auto-pins during it)
//   2. cross-build  — every island product cross-compiled for wasm32 through the
//                     SAME `wasm-cross` direct swiftc the autobuild plugin
//                     emits (wasmCross is this verb, so semantics cannot
//                     diverge), into the verify work dir — a location verify
//                     OWNS; it never touches the autobuild plugin work dir
//   3. measure/pin  — `measure` over the cross-built artifacts: the DX-3 rows
//                     (name/maxBytes/maxGzipBytes EXACTLY the schema
//                     WebUIBudgetPlugin reads + additive raw/gz/sha/url,
//                     version 2) into <work>/ContinuumManifest.json
//   4. budget row   — WebUIBudgetPlugin RE-INVOKED over the verify work dir
//                     (one budget path, I5 — verify never becomes a second
//                     enforcement locus): the tightest of declared-vs-measured
//                     per island (the plugin's own containment matching);
//                     any breach = failure.
//
// the verb is belt-and-suspenders: the plain getting-started path (`swift
// build`, zero manual verbs) already runs stages 2+3 automatically via
// WebUIAutobuildPlugin. `verify` performs every stage explicitly so a package
// WITHOUT wiring still gets a complete, deterministic verdict, and it is the
// ONLY verb a getting-started path may name for island verification — `wasm-island`
// stays internal (Unchanged semantics; the ladder + acceptance keep calling it).
// this contract is the no-manual-steps audit (§4.7, audited in b-docs).
//
// surfaces:
//   swift package --disable-sandbox plugin verify [--product <Island>]...   (framework home)
//   webui-continuum verify --package-dir <app> --framework <no-webui path>  (consumer app)
//
extension WebUIContinuumTool.Run {

	static func verify(_ argv: [String]) throws {
		let packageDir = absolutePath(Args.option(argv, "--package-dir") ?? ".")
		let framework = Args.option(argv, "--framework").map { absolutePath($0) } ?? packageDir
		let workDir = absolutePath(Args.option(argv, "--work-dir")
			?? (packageDir + "/.build/continuum-verify"))
		let swiftc = Args.option(argv, "--swiftc") ?? defaultSwiftcPath()
		let noStrip = Args.has(argv, "--no-strip")
		let skipHostBuild = Args.has(argv, "--skip-swift-build")
		let productFilters = Args.options(argv, "--product")

		print("── webui-continuum verify ─────────────────────────────────────")
		print("  package: \(packageDir)")
		print("  framework: \(framework)")

		// the island graph must resolve (mirror WebUIAutobuildPlugin's wiring
		// failure — a missing graph is a bug, never a silent skip).
		guard hasIslandGraph(framework) else {
			WebUIContinuumTool.writeError("verify: no island graph found under the framework at \(framework) (expected Sources/WebUIIslandCore + Sources/WebUISharedCore) — pass --framework <no-webui path>")
			exit(1)
		}

		// islands = the framework's islands + the package's own (dedup, sorted);
		// --product filters the set. discovery is the SAME imports text-scan the
		// autobuild plugin uses, so what a plain `swift build` would cross-build
		// is exactly what verify cross-builds.
		var islands = discoverIslands(at: framework)
		if packageDir != framework {
			for name in discoverIslands(at: packageDir) where !islands.contains(name) {
				islands.append(name)
			}
		}
		islands.sort()
		if !productFilters.isEmpty {
			islands = productFilters.filter { islands.contains($0) }
		}
		guard !islands.isEmpty else {
			print("verify: no island products discovered under \(packageDir) or \(framework) — nothing to cross-build (a package with no islands verifies on its host build alone)")
			print("── verify: done (no islands) ────────────────────────────────")
			return
		}

		// stage 1: host build — the island mains + the app compile natively.
		// the build runs into ITS OWN root under the verify work dir: verify is
		// re-entrancy-safe (it can run as `plugin verify` INSIDE the framework,
		// where a nested `swift build` on the package's own `.build` would
		// deadlock on the lock the outer plugin invocation holds — the
		// verified mechanism: separate build roots, exactly like wasm-island's
		// scratch root).
		if skipHostBuild {
			print("[verify] 1/4 build: skipped (--skip-swift-build)")
		} else {
			let (status, out) = runProcess(executable: "/usr/bin/env", args: [
				"swift", "build",
				"--package-path", packageDir,
				"--build-path", workDir + "/host-build",
			], env: isolatedSwiftPMEnv(workDir: workDir))
			if status != 0 {
				print(out, terminator: out.hasSuffix("\n") ? "" : "\n")
				WebUIContinuumTool.writeError("verify: stage 1/4 (host `swift build`) failed with exit \(status) — the package does not compile natively")
				exit(1)
			}
			print("[verify] 1/4 build: host `swift build` OK")
		}

		// stage 2: cross-build every island into the verify work dir (never the
		// autobuild work dir — verify owns this path).
		try? FileManager.default.createDirectory(atPath: workDir, withIntermediateDirectories: true)
		for island in islands {
			let packageMain = packageDir + "/Sources/" + island
			let mainDir = FileManager.default.fileExists(atPath: packageMain)
				? packageMain
				: framework + "/Sources/" + island
			print("[verify] 2/4 cross-build: \(island) → \(workDir)/\(island).wasm")
			try wasmCross([
				"--graph", framework,
				"--product", island,
				"--main-dir", mainDir,
				"--obj", workDir + "/" + island + ".obj",
				"--out", workDir + "/" + island + ".wasm",
				"--swiftc", swiftc,
			] + (noStrip ? ["--no-strip"] : []))
		}
		print("[verify] 2/4 cross-build: \(islands.count) island(s) cross-built OK")

		// stage 3: measure/pin (DX-3) over the verify work dir.
		try measure(["--work-dir", workDir, "--manifest", workDir + "/ContinuumManifest.json"])

		// stage 4: the budget row — WebUIBudgetPlugin re-invoked over the verify
		// work dir, so the rows written in stage 3 are what get enforced. one
		// budget path (I5); verify adds no second enforcement locus.
		var budgetArgs = [
			"swift", "package", "--package-path", framework, "--disable-sandbox", "plugin", "budget",
			// a build root verify OWNS: the inner plugin invocation must not
			// contend for the package `.build` lock (re-entrancy-safe when
			// verify itself runs as `plugin verify` inside the framework).
			"--build-path", workDir + "/swiftpm-build",
			"--island-dir", workDir,
			"--autobuild-manifest", workDir + "/ContinuumManifest.json",
		]
		if let declared = declaredManifest(in: packageDir) {
			budgetArgs += ["--island-manifest", declared]
		}
		print("[verify] 4/4 budget: WebUIBudgetPlugin over \(workDir)")
		let (budgetStatus, budgetOut) = runProcess(executable: "/usr/bin/env", args: budgetArgs, env: isolatedSwiftPMEnv(workDir: workDir))
		print(budgetOut, terminator: budgetOut.hasSuffix("\n") ? "" : "\n")
		guard budgetStatus == 0 else {
			WebUIContinuumTool.writeError("verify: stage 4/4 (budget) FAILED — every shipped surface must be within its pinned ceiling (see the budget table above)")
			exit(1)
		}
		print("── verify: PASS — build → cross-build → measure/pin → budget row all green ──")
	}

	// MARK: - discovery + helpers

	/// the island graph root: the two leaf modules must exist under it.
	static func hasIslandGraph(_ root: String) -> Bool {
		FileManager.default.fileExists(atPath: root + "/Sources/WebUIIslandCore")
			&& FileManager.default.fileExists(atPath: root + "/Sources/WebUISharedCore")
	}

	/// island products = `Sources/<Name>/` dirs whose main (main.swift /
	/// Main.swift) imports `WebUIIslandCore` (or `WebUISharedCore`) — the SAME
	/// text scan WebUIAutobuildPlugin.discoverIslands performs, so verify's set
	/// matches what a plain `swift build` cross-builds.
	static func discoverIslands(at root: String) -> [String] {
		let sources = root + "/Sources"
		guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sources) else { return [] }
		var islands: [String] = []
		for name in entries.sorted() where !name.hasPrefix(".") {
			let dir = sources + "/" + name
			var isDir: ObjCBool = false
			guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
			for mainName in ["main.swift", "Main.swift"] {
				guard let text = try? String(contentsOfFile: dir + "/" + mainName, encoding: .utf8) else { continue }
				if text.contains("import WebUIIslandCore") || text.contains("import WebUISharedCore") {
					islands.append(name)
				}
				break
			}
		}
		return islands
	}

	/// a package's declared-pins manifest (the WebUIContinuumPlugin work-dir
	/// ContinuumManifest.json), found by the same plugin-outputs walk the
	/// budget plugin uses. consumers today carry only the DX-3 auto-pins; when
	/// a declared manifest exists it is passed through so the budget stage
	/// enforces the tightest of both.
	static func declaredManifest(in packageDir: String) -> String? {
		let outputs = packageDir + "/.build/plugins/outputs"
		guard let packages = try? FileManager.default.contentsOfDirectory(atPath: outputs) else { return nil }
		for package in packages.sorted() {
			guard let targets = try? FileManager.default.contentsOfDirectory(atPath: outputs + "/" + package) else { continue }
			for target in targets.sorted() {
				let manifest = outputs + "/" + package + "/" + target
					+ "/destination/WebUIContinuumPlugin/ContinuumManifest.json"
				if FileManager.default.fileExists(atPath: manifest) {
					return manifest
				}
			}
		}
		return nil
	}

	/// absolute + normalized path (the spawned swift commands need one).
	static func absolutePath(_ path: String) -> String {
		let url = path.hasPrefix("/")
			? URL(fileURLWithPath: path)
			: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
		return url.standardizedFileURL.path
	}

	/// the environment for verify's NESTED SwiftPM children (host build +
	/// budget plugin). SwiftPM keys a per-package build lock under $TMPDIR
	/// (e.g. …/T/_private_tmp_…_lane-b_.build.lock) and holds it for the whole
	/// OUTER `plugin verify` invocation — so a nested `swift build` /
	/// `swift package plugin` on the same package would block on it forever
	/// (the deadlock this verb hit on its first framework-home run). pointing
	/// TMPDIR at a directory verify OWNS (its work dir) gives every nested
	/// SwiftPM a lock key only it touches — plus, together with --build-path,
	/// a fully self-contained build surface that never contends with the
	/// package's own `.build`. verified: the nested budget completes in ~7 s.
	static func isolatedSwiftPMEnv(workDir: String) -> [String: String] {
		try? FileManager.default.createDirectory(atPath: workDir + "/tmp", withIntermediateDirectories: true)
		var env = ProcessInfo.processInfo.environment
		env["TMPDIR"] = workDir + "/tmp"
		env["TMP"] = workDir + "/tmp"
		env["TEMP"] = workDir + "/tmp"
		return env
	}

	/// spawn + capture (stdout+stderr merged); returns (exit status, output).
	static func runProcess(executable: String, args: [String], env: [String: String]? = nil) -> (Int32, String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = args
		if let env {
			process.environment = env
		}
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		do {
			try process.run()
		} catch {
			return (1, "verify: cannot spawn \(executable) \(args.joined(separator: " ")): \(error)")
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}
}

// MARK: - repeatable option support (the --product filter)

extension Args {
	/// every value of a repeatable option, in occurrence order.
	static func options(_ argv: [String], _ flag: String) -> [String] {
		var values: [String] = []
		var iterator = argv.makeIterator()
		while let current = iterator.next() {
			if current == flag, let next = iterator.next() {
				values.append(next)
			}
		}
		return values
	}
}
