import Foundation
import Testing
@testable import WebUIContinuumTool

// MARK: - the DX-2 scaffold verb (CONTINUUM_DX §2.2) — unit tests
//
// the text-level contract of the scaffold: the generated island main names
// the MACRO-PRODUCED adapter type `<Type>.<Type>Island` (lane D's expansion
// emits `struct FeedIsland` nested in `extension Feed`), so the emitted string
// `IslandRuntime<Feed.FeedIsland>.run()` is pinned in BOTH suites — here and
// in WebUIContinuumMacroTests — so a rename breaks both loudly. the
// append-only anchors + refusal semantics are tested against text fixtures
// (no disk writes beyond the tool's own Package.swift patch, which is fenced
// off here; the file-level behavior is covered by designer/gates/
// scaffold-demo.sh against a home-dir scratch app).

// the shared CLI harness: the tool is a build product, so `swift test` without
// `swift build` legitimately leaves it absent; every CLI suite carries the
// `.enabled(if:)` trait like the asset-tool suites.

var scaffoldToolAvailable: Bool { scaffoldToolURL() != nil }

var scaffoldToolUnavailableNote: Comment { "WebUIContinuumTool not built — run `swift build` first" }

func scaffoldToolURL() -> URL? {
	let root = ".build/out/Products"
	if let entries = try? FileManager.default.contentsOfDirectory(atPath: root) {
		for dir in entries.sorted() {
			let candidate = root + "/" + dir + "/WebUIContinuumTool"
			if FileManager.default.isExecutableFile(atPath: candidate) {
				return URL(fileURLWithPath: candidate)
			}
		}
	}
	for legacy in [".build/debug/WebUIContinuumTool", ".build/release/WebUIContinuumTool"] {
		if FileManager.default.isExecutableFile(atPath: legacy) {
			return URL(fileURLWithPath: legacy)
		}
	}
	return nil
}

func runScaffoldTool(_ args: [String], cwd: String? = nil) throws -> (status: Int32, out: String) {
	let url = try #require(scaffoldToolURL(), "\(scaffoldToolUnavailableNote)")
	let process = Process()
	process.executableURL = url
	process.arguments = args
	if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
	let pipe = Pipe()
	process.standardOutput = pipe
	process.standardError = pipe
	try process.run()
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: - the generated-main contract (the D-coordinated adapter pin)

@Suite("scaffold: generated main")
struct ScaffoldMainTests {

	@Test("the generated main names the macro-produced adapter IslandRuntime<Feed.FeedIsland>", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func adapterPin() async throws {
		let (status, out) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--print"])
		#expect(status == 0)
		// the pin string: lane D's expansion emits `struct FeedIsland` nested
		// in `extension Feed` (islandQualifiedName "<Type>.<Type>Island"); the
		// scaffold's generated main binds exactly that adapter. a rename on
		// either side fails this assertion loudly.
		#expect(out.contains("IslandRuntime<Feed.FeedIsland>.run()"), "\(out)")
		#expect(!out.contains("IslandRuntime<FeedIsland>.run()"), "must use the QUALIFIED adapter name (D's pin)")
	}

	@Test("the generated main carries the generated header and the runtime form", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func headerAndForm() async throws {
		let (status, out) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--print"])
		#expect(status == 0)
		#expect(out.contains("GENERATED FILE — do not edit"), "\(out)")
		#expect(out.contains("@_silgen_name(\"webui_island_bind\")"), "\(out)")
		#expect(out.contains("#if os(WASI)"), "\(out)")
		#expect(out.contains("import WebUIIslandCore"), "\(out)")
		#expect(out.contains("import WebUISharedCore"), "\(out)")
	}

	@Test("--print does not write (no Package.swift edit, no Sources dir)", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func printIsDryRun() async throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("scaffold-print-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		try minimalManifest.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		let (status, _) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--package-dir", dir.path, "--print"])
		#expect(status == 0)
		#expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Sources/Feed/main.swift").path))
		let patched = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(!patched.contains("executable(name: \"Feed\""))
	}
}

// MARK: - the append-only anchor + refusal contract

@Suite("scaffold: anchors and refusal")
struct ScaffoldAnchorTests {

	@Test("add-island appends product+target beside siblings (append-only)", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func addIslandAppends() async throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("scaffold-add-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		try minimalManifest.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

		let (status, out) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--package-dir", dir.path])
		#expect(status == 0, "\(out)")

		let patched = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(patched.contains(".executable(name: \"Feed\""), "\(patched)")
		#expect(patched.contains("name: \"Feed\""), "\(patched)")
		#expect(patched.contains(".product(name: \"WebUIIslandCore\", package: \"no-webui\")"), "\(patched)")
		// the original sibling block is untouched.
		#expect(patched.contains(".executable(name: \"App\", targets: [\"App\"])"), "sibling preserved")
		// the generated main exists.
		let main = try String(contentsOf: dir.appendingPathComponent("Sources/Feed/main.swift"), encoding: .utf8)
		#expect(main.contains("IslandRuntime<Feed.FeedIsland>.run()"))
	}

	@Test("add-island is idempotent: a re-run appends nothing", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func addIslandIdempotent() async throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("scaffold-idem-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		try minimalManifest.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		let (s1, _) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--package-dir", dir.path])
		#expect(s1 == 0)
		let afterFirst = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		let (s2, _) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--package-dir", dir.path])
		#expect(s2 == 0)
		let afterSecond = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(afterFirst.filter { $0 == "\"" }.count == afterSecond.filter { $0 == "\"" }.count, "no duplicate product/target entries")
	}

	@Test("bootstrap inserts the once-per-app block (dependency + plugin) and is idempotent", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func bootstrapInserts() async throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("scaffold-boot-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		try minimalManifest.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

		let (status, out) = try runScaffoldTool(["scaffold", "--bootstrap", "--name", "App", "--framework", "/tmp/framework", "--package-dir", dir.path])
		#expect(status == 0, "\(out)")
		let patched = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(patched.contains(".package(name: \"no-webui\", path: \"/tmp/framework\")"), "\(patched)")
		#expect(patched.contains(".plugin(name: \"WebUIAutobuildPlugin\", package: \"no-webui\")"), "\(patched)")
		// the plugin is attached to the App target ONLY (not the island).
		let appTarget = patched.range(of: "name: \"App\",")!
		let snippet = patched[appTarget.upperBound...].prefix(400)
		#expect(snippet.contains("WebUIAutobuildPlugin"), "\(snippet)")

		// idempotent re-run.
		let before = patched
		let (s2, _) = try runScaffoldTool(["scaffold", "--bootstrap", "--name", "App", "--framework", "/tmp/framework", "--package-dir", dir.path])
		#expect(s2 == 0)
		let after = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(after == before, "bootstrap must be idempotent")
	}

	@Test("a manifest without products/targets is refused (never partially patched)", .enabled(if: scaffoldToolAvailable, scaffoldToolUnavailableNote))
	func refusesUnanchorable() async throws {
		let dir = FileManager.default.temporaryDirectory
			.appendingPathComponent("scaffold-refuse-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: dir) }
		let broken = """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "bare")
		"""
		try broken.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

		let (status, out) = try runScaffoldTool(["scaffold", "--add-island", "Feed", "--package-dir", dir.path])
		#expect(status != 0, "must refuse")
		#expect(out.contains("cannot anchor"), "\(out)")
		// nothing was written.
		let after = try String(contentsOf: dir.appendingPathComponent("Package.swift"), encoding: .utf8)
		#expect(after == broken)
	}
}

// a minimal consumer manifest the anchor tests patch.
private let minimalManifest = """
	// swift-tools-version: 6.0
	import PackageDescription

	let package = Package(
	    name: "scaffold-test",
	    platforms: [.macOS(.v15)],
	    products: [
	        .executable(name: "App", targets: ["App"]),
	    ],
	    dependencies: [
	    ],
	    targets: [
	        .executableTarget(
	            name: "App",
	            dependencies: [
	                .product(name: "Logging", package: "swift-log"),
	            ]
	        ),
	    ]
	)
	"""
