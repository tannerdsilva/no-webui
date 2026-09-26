import Foundation
import RAW_sha256

// generated metadata carrier for the prebuilt wasm client artifact.
//
// the plugin runs this tool during the host build with the artifact as an
// input file; the tool validates the webassembly structure (magic + version)
// and emits a presence/sha256/byteCount carrier that the island routes and the
// serving seam consume — so the content-addressed url is known at build time,
// not re-derived per request, and a stale/corrupt artifact fails the host
// build instead of shipping wrong bytes.

enum WebUIWasmToolError: Error, CustomStringConvertible {
    case badWasmMagic
    case badWasmVersion
    case emptyArtifact
    case readFailed(String)
    case truncatedSection
    case truncatedLeb128
    case badLeb128
    var description: String {
        switch self {
        case .badWasmMagic: return "artifact does not start with the webassembly magic bytes (\\0asm)"
        case .badWasmVersion: return "artifact webassembly version is not 1"
        case .emptyArtifact: return "wasm artifact is empty"
        case .readFailed(let path): return "cannot read artifact at \(path)"
        case .truncatedSection: return "wasm section extends past end of file"
        case .truncatedLeb128: return "truncated LEB128 in wasm section size"
        case .badLeb128: return "LEB128 encoding exceeds 64 bits"
        }
    }
}

@main
enum WebUIWasmTool {
    static func main() throws {
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        var wasmInput: String?
        var outputPath: String?
        var stripInput: String?
        var stripOutput: String?
        var missing = false
        var sdkHint = "swift-6.4.0-RELEASE_wasm"
        var productName = "WebUIClient"

        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--wasm-input":
                wasmInput = iterator.next()
            case "--output":
                outputPath = iterator.next()
            case "--strip-input":
                stripInput = iterator.next()
            case "--strip-output":
                stripOutput = iterator.next()
            case "--missing":
                missing = true
            case "--sdk":
                sdkHint = iterator.next() ?? sdkHint
            case "--product":
                productName = iterator.next() ?? productName
            default:
                break
            }
        }

        // strip mode: splice out custom sections (id 0 — the wasm name table
        // and DWARF debug sections) so the shipped artifact drops ~15% of its
        // bytes with no behavior change. distinct output keeps the input
        // untouched (the build system may still reference it).
        if let stripInput, let stripOutput {
            let bytes = try readArtifact(at: stripInput)
            let stripped = try stripCustomSections(from: bytes)
            try Data(stripped).write(to: URL(fileURLWithPath: stripOutput))
            let saved = bytes.count - stripped.count
            print("WebUIWasmTool: stripped \(saved) bytes custom sections (\(bytes.count) → \(stripped.count) bytes, \(100 * saved / max(1, bytes.count))%) → \(stripOutput)")
            exit(0)
        }

        guard let outputPath else {
            print("usage: WebUIWasmTool --wasm-input <path> [--missing] --output <path> [--sdk <id>] [--product <name>] | --strip-input <wasm> --strip-output <wasm>")
            exit(2)
        }

        if missing {
            let carrier = """
            /// wasm client artifact metadata, generated for the island build.
            /// the artifact was absent at build time — run
            /// the `wasm-island` verb produces it.
            public enum WebUIWasmInfo {
            \t/// whether a prebuilt client artifact was present at build time.
            \tpublic static let present = false
            \t/// sha-256 (lowercase hex) of the artifact bytes (empty when absent).
            \tpublic static let sha256 = ""
            \t/// artifact byte count (0 when absent).
            \tpublic static let byteCount = 0
            \t/// the swift sdk the artifact was produced for (advisory).
            \tpublic static let sdk = "\(sdkHint)"
            \t/// the product name the artifact was built from (advisory).
            \tpublic static let product = "\(productName)"
            }
            """
            try carrier.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("WebUIWasmTool: wrote absent carrier → \(outputPath)")
            exit(0)
        }

        guard let wasmInput else {
            print("usage: WebUIWasmTool --wasm-input <path> --output <path> [--sdk <id>] [--product <name>]")
            exit(2)
        }

        let bytes = try readArtifact(at: wasmInput)

        let sha = sha256Hex(of: bytes)
        let carrier = """
        /// wasm client artifact metadata, generated for the island build.
        /// the tool validates webassembly structure and records the sha-256
        /// that content-addresses the served artifact (immutable-cached route).
        public enum WebUIWasmInfo {
        \t/// whether a prebuilt client artifact was present at build time.
        \tpublic static let present = true
        \t/// sha-256 (lowercase hex) of the artifact bytes — the content-addressed url suffix.
        \tpublic static let sha256 = "\(sha)"
        \t/// artifact byte count.
        \tpublic static let byteCount = \(bytes.count)
        \t/// the swift sdk the artifact was produced for (advisory).
        \tpublic static let sdk = "\(sdkHint)"
        \t/// the product name the artifact was built from (advisory).
        \tpublic static let product = "\(productName)"
        }
        """
        try carrier.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("WebUIWasmTool: validated + hashed \(wasmInput) (\(bytes.count) bytes, sha \(sha.prefix(12))…) → \(outputPath)")
    }

    /// read + structurally validate a wasm artifact.
    static func readArtifact(at path: String) throws -> [UInt8] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw WebUIWasmToolError.readFailed(path)
        }
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw WebUIWasmToolError.emptyArtifact }
        guard bytes.count >= 8,
              bytes[0] == 0x00, bytes[1] == 0x61, bytes[2] == 0x73, bytes[3] == 0x6D
        else {
            throw WebUIWasmToolError.badWasmMagic
        }
        guard bytes[4] == 0x01, bytes[5] == 0x00, bytes[6] == 0x00, bytes[7] == 0x00 else {
            throw WebUIWasmToolError.badWasmVersion
        }
        return bytes
    }

    /// splice out every custom section (id 0). custom sections — the name
    /// table browsers use for stack traces, DWARF, producers — are advisory;
    /// removing them shrinks the artifact and changes no execution semantics.
    /// non-custom sections are re-emitted verbatim, so all internal offsets
    /// (function/memory/type indices) stay valid.
    static func stripCustomSections(from bytes: [UInt8]) throws -> [UInt8] {
        var out = [UInt8](bytes[0 ..< 8])  // header: magic + version
        var i = 8
        while i < bytes.count {
            let sectionID = bytes[i]; i += 1
            let (size, afterSize) = try leb128(bytes, from: i)
            i = afterSize
            guard i + size <= bytes.count else {
                throw WebUIWasmToolError.truncatedSection
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

    /// decode an unsigned LEB128 from `bytes` at `from`; returns (value, index past the encoding).
    static func leb128(_ bytes: [UInt8], from start: Int) throws -> (Int, Int) {
        var result = 0
        var shift = 0
        var i = start
        while i < bytes.count {
            let b = bytes[i]; i += 1
            result |= Int(b & 0x7f) << shift
            if b & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { throw WebUIWasmToolError.badLeb128 }
        }
        throw WebUIWasmToolError.truncatedLeb128
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

    /// lowercase hex sha-256 over the artifact bytes.
    static func sha256Hex(of bytes: [UInt8]) -> String {
        var hasher = RAW_sha256.Hasher()
        bytes.withUnsafeBytes { hasher.update($0) }
        var digest = [UInt8](repeating: 0, count: 32)
        do {
            try digest.withUnsafeMutableBytes { buffer in
                try hasher.finish(into: buffer.baseAddress!)
            }
        } catch {
            return ""
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
