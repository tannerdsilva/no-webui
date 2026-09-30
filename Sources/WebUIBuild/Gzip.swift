import Foundation

// MARK: - build-time gzip

// compression happens at BUILD time on purpose. no-webui takes no dependencies and links no
// runtime compressor (Foundation's `compression` is Darwin-only; linking zlib would be a
// dependency), so a compressed variant is always a build product — this is where the
// framework's own tool and a consumer's tool produce them, through one implementation.
//
// `-n` is the determinism rule: no timestamp and no original name land in the header, so
// identical input yields identical bytes and a content-addressed url is reproducible.

/// gzip *data* deterministically (`gzip -n -9 -c`), or `nil` when the build host has no
/// working `gzip` — in which case the caller ships the raw bytes rather than nothing.
///
/// the payload round-trips through a temporary file: a stdin/stdout two-pipe dance
/// deadlocks once the compressed output outgrows the pipe buffer, and the host `gzip` is
/// happiest with a path.
public func gzip(_ data: Data) -> Data? {
	let tmp = FileManager.default.temporaryDirectory
		.appendingPathComponent("webui-gzip-\(UUID().uuidString)")
	guard (try? data.write(to: tmp, options: .atomic)) != nil else { return nil }
	defer { try? FileManager.default.removeItem(at: tmp) }
	return gzipFile(at: tmp.path)
}

/// gzip a utf-8 string — the minified sheet has no file on disk.
public func gzip(_ text: String) -> Data? {
	gzip(Data(text.utf8))
}

/// the process boundary: one `gzip` invocation, output captured whole.
private func gzipFile(at path: String) -> Data? {
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = ["gzip", "-n", "-9", "-c", path]
	let pipe = Pipe()
	process.standardOutput = pipe
	process.standardError = Pipe()
	do {
		try process.run()
	} catch {
		return nil
	}
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	guard process.terminationStatus == 0, !data.isEmpty else { return nil }
	return data
}