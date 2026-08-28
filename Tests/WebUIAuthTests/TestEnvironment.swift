import Foundation

// MARK: - LMDB test environment helpers

/// helpers for tests that exercise real LMDB environments: unique temp
/// directories per test, deterministic cleanup after the store goes out of
/// scope (the environment closes in its deinit, so tests scope the store in a
/// `do {}` block and remove the directory afterwards).
enum LMDBTestEnvironment {
	static func makeTempDirectory() throws -> String {
		let dir = NSTemporaryDirectory() + "webuiauth-lmdb-" + UUID().uuidString
		try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		return dir
	}

	static func remove(_ path: String) {
		try? FileManager.default.removeItem(atPath: path)
	}
}
