import Foundation
import Testing

// integrity + import-surface pins for the release `WebUIClient.wasm` product.
// the artifact is built by a separate wasm-sdk invocation, so these tests
// skip (not fail) when it is absent — the host suite stays green on a fresh
// clone without the wasm sdk.
struct WasmIntegrityTests {
	private static let artifactPath = ".build/out/Products/Release-webassembly-wasm32/WebUIClient.wasm"

	private static func readArtifact() throws -> [UInt8] {
		let fd = open(artifactPath, O_RDONLY)
		if fd < 0 { return [] }
		defer { close(fd) }
		var st = stat()
		guard fstat(fd, &st) == 0, st.st_size > 0 else { return [] }
		let size = Int(st.st_size)
		var bytes = [UInt8](repeating: 0, count: size)
		let n = bytes.withUnsafeMutableBytes { buf in
			read(fd, buf.baseAddress, size)
		}
		return n == size ? bytes : []
	}

	/// the artifact is built by a separate wasm-sdk invocation; when it is
	/// absent (fresh clone without the wasm sdk) the pins record a warning and
	/// pass, keeping the host suite green.
	private static func requireArtifact(_ bytes: [UInt8]) -> Bool {
		guard bytes.isEmpty else { return true }
		Issue.record(
			"WebUIClient.wasm not built — run: swift build -c release --swift-sdk swift-6.4.0-RELEASE_wasm --product WebUIClient",
			severity: .warning
		)
		return false
	}

	// the documented p2 import surface (WASM_BOOTSTRAP.md) — the module's real
	// import list must match it exactly, so a new import is a deliberate change.
	private static let documentedImports: Set<String> = {
		var set: Set<String> = [
			"wasi_snapshot_preview1.args_get", "wasi_snapshot_preview1.args_sizes_get",
			"wasi_snapshot_preview1.environ_get", "wasi_snapshot_preview1.environ_sizes_get",
			"wasi_snapshot_preview1.clock_res_get", "wasi_snapshot_preview1.clock_time_get",
			"wasi_snapshot_preview1.fd_close", "wasi_snapshot_preview1.fd_fdstat_get",
			"wasi_snapshot_preview1.fd_fdstat_set_flags", "wasi_snapshot_preview1.fd_filestat_get",
			"wasi_snapshot_preview1.fd_filestat_set_size", "wasi_snapshot_preview1.fd_filestat_set_times",
			"wasi_snapshot_preview1.fd_pread", "wasi_snapshot_preview1.fd_prestat_get",
			"wasi_snapshot_preview1.fd_prestat_dir_name", "wasi_snapshot_preview1.fd_read",
			"wasi_snapshot_preview1.fd_readdir", "wasi_snapshot_preview1.fd_seek",
			"wasi_snapshot_preview1.fd_sync", "wasi_snapshot_preview1.fd_tell",
			"wasi_snapshot_preview1.fd_write", "wasi_snapshot_preview1.path_create_directory",
			"wasi_snapshot_preview1.path_filestat_get", "wasi_snapshot_preview1.path_filestat_set_times",
			"wasi_snapshot_preview1.path_link", "wasi_snapshot_preview1.path_open",
			"wasi_snapshot_preview1.path_readlink", "wasi_snapshot_preview1.path_remove_directory",
			"wasi_snapshot_preview1.path_rename", "wasi_snapshot_preview1.path_symlink",
			"wasi_snapshot_preview1.path_unlink_file", "wasi_snapshot_preview1.poll_oneoff",
			"wasi_snapshot_preview1.proc_exit", "wasi_snapshot_preview1.random_get",
			"env.setInnerHTML", "env.removeElement", "env.getElementValue",
			"env.setElementValue", "env.setCustomValidity", "env.wsSend", "env.now", "env.log",
		]
		return set
	}()

	@Test("wasm magic and version are present")
	func magicAndVersion() throws {
		let bytes = try Self.readArtifact()
		guard Self.requireArtifact(bytes) else { return }
		#expect(bytes.count > 8)
		#expect(Array(bytes[0 ..< 4]) == [0x00, 0x61, 0x73, 0x6D])  // "\0asm"
		#expect(bytes[4] == 0x01 && bytes[5] == 0x00 && bytes[6] == 0x00 && bytes[7] == 0x00)  // version 1
	}

	@Test("a section walk stays in bounds and finds an import + export section")
	func sectionWalkBounds() throws {
		let bytes = try Self.readArtifact()
		guard Self.requireArtifact(bytes) else { return }
		let (imports, exports) = Self.scan(bytes)
		#expect(!imports.isEmpty)
		#expect(!exports.isEmpty)
		#expect(exports.contains("webui_render_page"))
		#expect(exports.contains("webui_frame_ptr"))
		#expect(exports.contains("webui_frame_len"))
	}

	@Test("the import surface matches the documented set exactly")
	func importSurfaceMatchesDocumentation() throws {
		let bytes = try Self.readArtifact()
		guard Self.requireArtifact(bytes) else { return }
		let (imports, _) = Self.scan(bytes)
		#expect(imports.count == Self.documentedImports.count)
		for name in imports {
			#expect(Self.documentedImports.contains(name), "undocumented import: \(name)")
		}
	}

	// MARK: - minimal wasm binary scanner (magic, version, section walk)

	private static func scan(_ bytes: [UInt8]) -> (imports: [String], exports: [String]) {
		var i = 8
		var imports: [String] = []
		var exports: [String] = []
		while i < bytes.count {
			let sectionID = bytes[i]; i += 1
			var size = 0
			var shift = 0
			while true {
				let b = bytes[i]; i += 1
				size |= Int(b & 0x7f) << shift
				if b & 0x80 == 0 { break }
				shift += 7
			}
			let end = i + size
			if end > bytes.count { break }
			if sectionID == 2 {
				var count = 0
				var sc = 0
				while true {
					let b = bytes[i]; i += 1
					count |= Int(b & 0x7f) << sc
					if b & 0x80 == 0 { break }
					sc += 7
				}
				for _ in 0 ..< count {
					let importModule = name(bytes, &i)
					let importName = name(bytes, &i)
					imports.append(importModule + "." + importName)
					i += 1  // kind byte
					if bytes[i - 1] == 0 { _ = leb(bytes, &i) }        // func type index
					else if bytes[i - 1] == 1 { i += 1 }               // table reftype
					else if bytes[i - 1] == 2 { i += 3 }               // memory limits
					else { i += 2 }                                    // global valtype+mut
				}
			} else if sectionID == 7 {
				var count = 0
				var sc = 0
				while true {
					let b = bytes[i]; i += 1
					count |= Int(b & 0x7f) << sc
					if b & 0x80 == 0 { break }
					sc += 7
				}
				for _ in 0 ..< count {
					let exportName = name(bytes, &i)
					exports.append(exportName)
					i += 1  // kind
					_ = leb(bytes, &i)  // index
				}
			}
			i = end
		}
		return (imports, exports)
	}

	private static func name(_ bytes: [UInt8], _ i: inout Int) -> String {
		let n = leb(bytes, &i)
		let out = String(decoding: bytes[i ..< i + n], as: UTF8.self)
		i += n
		return out
	}

	private static func leb(_ bytes: [UInt8], _ i: inout Int) -> Int {
		var result = 0
		var shift = 0
		while true {
			let b = bytes[i]; i += 1
			result |= Int(b & 0x7f) << shift
			if b & 0x80 == 0 { break }
			shift += 7
		}
		return result
	}
}
