import Foundation
import Testing
@testable import WebUIContinuumTool

// MARK: - the DX-8 `verify` verb (CONTINUUM_DX §4.7, W3) — unit tests
//
// the text/logic-level contract of the ONE consumer-facing island verification
// verb: discovery matches the autobuild plugin's set (a plain `swift build`
// cross-builds exactly what `verify` cross-builds), the island graph must
// resolve (wiring failure, never a silent skip), and the budget stage re-invokes
// WebUIBudgetPlugin over the verify work dir (one budget path, I5 — verify has
// no second enforcement locus). the heavy four-stage path itself (host build,
// real wasm cross-build, nested budget invocation) is proven end-to-end by
// designer/gates/scaffold-demo.sh step 7 — unit tests cover the pure surface.

var verifyToolAvailable: Bool { scaffoldToolURL() != nil }
var verifyToolUnavailableNote: Comment { "WebUIContinuumTool not built — run `swift build` first" }

@Suite("verify: discovery + graph resolution")
struct VerifyDiscoveryTests {

	/// a fixture package root (a temp dir with a `Sources/` layout).
	private func fixtureRoot(_ name: String) throws -> URL {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("verify-\(name)-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	@Test("discoverIslands finds exactly the sources whose main imports the island core", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func discoveryScan() async throws {
		let root = try fixtureRoot("discovery")
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Feed"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Empty"), withIntermediateDirectories: true)
		// an island main imports WebUIIslandCore (the house marker rule).
		try "import WebUIIslandCore\nimport WebUISharedCore\n".write(
			to: root.appendingPathComponent("Sources/Feed/main.swift"), atomically: true, encoding: .utf8)
		// a plain app target does not import the island core.
		try "print(\"app\")\n".write(
			to: root.appendingPathComponent("Sources/App/main.swift"), atomically: true, encoding: .utf8)
		// a Main.swift (capital) form is discovered too, and an empty dir has no main.
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Probe"), withIntermediateDirectories: true)
		try "import WebUISharedCore\n".write(
			to: root.appendingPathComponent("Sources/Probe/Main.swift"), atomically: true, encoding: .utf8)

		let islands = WebUIContinuumTool.Run.discoverIslands(at: root.path)
		#expect(islands == ["Feed", "Probe"], "expected exactly Feed + Probe, got \(islands)")
	}

	@Test("hasIslandGraph requires BOTH leaf modules under the framework root", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func graphPresence() async throws {
		let root = try fixtureRoot("graph")
		defer { try? FileManager.default.removeItem(at: root) }
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/WebUISharedCore"), withIntermediateDirectories: true)
		#expect(!WebUIContinuumTool.Run.hasIslandGraph(root.path), "missing WebUIIslandCore must fail the graph check")
		try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/WebUIIslandCore"), withIntermediateDirectories: true)
		#expect(WebUIContinuumTool.Run.hasIslandGraph(root.path))
	}

	@Test("declaredManifest walks the plugin-outputs tree and finds the WebUIContinuumPlugin manifest", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func declaredManifestWalk() async throws {
		let package = try fixtureRoot("declared")
		defer { try? FileManager.default.removeItem(at: package) }
		let manifestDir = package
			.appendingPathComponent(".build/plugins/outputs/hash/pkg/destination/WebUIContinuumPlugin")
		try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
		try "{\"kind\":\"continuum-engine-slice\"}".write(to: manifestDir.appendingPathComponent("ContinuumManifest.json"), atomically: true, encoding: .utf8)
		#expect(WebUIContinuumTool.Run.declaredManifest(in: package.path)?.hasSuffix("WebUIContinuumPlugin/ContinuumManifest.json") == true)
		#expect(WebUIContinuumTool.Run.declaredManifest(in: package.path + "/nonexistent") == nil)
	}

	@Test("Args.options collects every --product occurrence", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func repeatableProductFilter() async throws {
		let values = Args.options(["--product", "One", "--no-strip", "--product", "Two", "--product", "Three"], "--product")
		#expect(values == ["One", "Two", "Three"])
		#expect(Args.options(["--no-strip"], "--product").isEmpty)
	}
}

@Suite("verify: orchestration edge cases")
struct VerifyRunEdgeTests {

	@Test("a missing island graph is refused with a named diagnostic (never a silent skip)", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func refusesMissingGraph() async throws {
		let package = FileManager.default.temporaryDirectory.appendingPathComponent("verify-missing-graph-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: package) }
		// the fixture framework root has no Sources/WebUIIslandCore.
		let noGraph = package.appendingPathComponent("fw")
		try FileManager.default.createDirectory(at: noGraph.appendingPathComponent("Sources"), withIntermediateDirectories: true)

		let (status, out) = try runScaffoldTool([
			"verify", "--package-dir", package.path, "--framework", noGraph.path, "--skip-swift-build",
		])
		#expect(status != 0, "missing graph must fail, got exit \(status)")
		#expect(out.contains("no island graph"), "\(out)")
	}

	@Test("a package with no islands verifies with nothing to cross-build (host build is the only check)", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func noIslandsIsContent() async throws {
		let package = FileManager.default.temporaryDirectory.appendingPathComponent("verify-no-islands-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: package.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: package) }
		try "print(\"app\")\n".write(to: package.appendingPathComponent("Sources/App/main.swift"), atomically: true, encoding: .utf8)
		// a framework root carrying the graph dirs but no island products.
		let framework = package.appendingPathComponent("fw")
		try FileManager.default.createDirectory(at: framework.appendingPathComponent("Sources/WebUISharedCore"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: framework.appendingPathComponent("Sources/WebUIIslandCore"), withIntermediateDirectories: true)

		let (status, out) = try runScaffoldTool([
			"verify", "--package-dir", package.path, "--framework", framework.path, "--skip-swift-build",
		])
		#expect(status == 0, "exit \(status): \(out)")
		#expect(out.contains("no island products"), "\(out)")
		#expect(!out.contains("[verify] 2/4"), "must not reach the cross-build stage")
	}

	@Test("isolatedSwiftPMEnv relocates TMPDIR into the verify work dir (the re-entrancy lock fix)", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func envIsolation() async throws {
		let work = FileManager.default.temporaryDirectory.appendingPathComponent("verify-env-\(UUID().uuidString)/work")
		let env = WebUIContinuumTool.Run.isolatedSwiftPMEnv(workDir: work.path)
		defer { try? FileManager.default.removeItem(at: work) }
		#expect(env["TMPDIR"] == work.path + "/tmp")
		#expect(env["TMP"] == work.path + "/tmp")
		#expect(FileManager.default.fileExists(atPath: work.path + "/tmp"), "the isolated tmp dir must be created")
	}

	@Test("absolutePath normalizes relative and dot paths against the cwd", .enabled(if: verifyToolAvailable, verifyToolUnavailableNote))
	func pathNormalization() async throws {
		let cwd = FileManager.default.currentDirectoryPath
		#expect(WebUIContinuumTool.Run.absolutePath(".") == URL(fileURLWithPath: cwd).standardizedFileURL.path)
		#expect(WebUIContinuumTool.Run.absolutePath(cwd) == URL(fileURLWithPath: cwd).standardizedFileURL.path)
	}
}
