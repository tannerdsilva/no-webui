import Foundation
import PackagePlugin

/// `swift package --disable-sandbox plugin wasm-client`
///
/// cross-builds the wasm client product with the official wasm sdk, then
/// copies the artifact to the canonical `.build/out/Products/…` location the
/// host serving seam reads — so a subsequent plain `swift build`/`swift run`
/// serves client-mode pages with zero extra steps.
///
/// why `--disable-sandbox`: the nested `swift build` must re-enter its own
/// sandbox at manifest evaluation (`sandbox-exec`), which the plugin sandbox
/// forbids (`sandbox_apply: Operation not permitted`) — same class of
/// constraint as `serve`/`smoke`.
///
/// why a scratch `--build-path` under `.build/wasm-client-scratch`: the
/// plugin invocation itself holds the package `.build` lock, so building into
/// the package's own `.build` deadlocks ("Another instance of SwiftPM is
/// already running"). an isolated sub-directory build root is lock-free and
/// keeps the artifact inside the package.
///
/// why `~/.swiftly/bin/swift` directly: the Xcode frontend cannot read the
/// wasm sdk's prebuilt modules (`compiled module was created by a different
/// version of the compiler`) and lacks `swift-autolink-extract`; the swiftly
/// shim is PATH-order-independent in spawn contexts.
@main
struct WebUIWasmClientPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) throws {
        // parse --product / --sdk / --output / --no-strip overrides
        var product = "WebUIClient"
        var sdk = "swift-6.4.0-RELEASE_wasm"
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
        let scratch = packageDir + "/.build/wasm-client-scratch"

        print("WebUIClient: cross-building '\(product)' with \(sdk) (via \(swiftBin))")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: swiftBin)
        build.arguments = [
            "build",
            "-c", "release",
            "--swift-sdk", sdk,
            "--build-path", scratch,
            "--package-path", packageDir,
            "--product", product,
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
            print("WebUIClient: cross-build failed (\(build.terminationStatus))")
            throw WebUIWasmClientError.buildFailed(build.terminationStatus)
        }

        // copy the artifact to the canonical serving location (no-store alias
        // + the content hash feed the immutable route at startup). by default
        // the artifact is stripped first (custom sections — the wasm name
        // table + DWARF — are advisory; dropping them cuts ~15% of the bytes
        // the browser downloads with no behavior change). `--no-strip` keeps
        // the name table for readable stack traces in devtools.
        let builtArtifact = scratch + "/out/Products/Release-webassembly-wasm32/" + product + ".wasm"
        guard FileManager.default.fileExists(atPath: builtArtifact) else {
            print(out)
            print("WebUIClient: artifact not found at \(builtArtifact)")
            throw WebUIWasmClientError.artifactMissing(builtArtifact)
        }
        let destination = outputOverride
            ?? packageDir + "/.build/out/Products/Release-webassembly-wasm32/" + product + ".wasm"

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
                throw WebUIWasmClientError.stripFailed
            }
            try Self.copyFile(from: stripped, to: destination)
            if let _ = try? FileManager.default.removeItem(atPath: stripped) {}
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: destination)[.size] as? Int) ?? 0
        print("WebUIClient: artifact ready at \(destination) (\(size) bytes\(noStrip ? ", unstripped" : ", custom-sections stripped"))")
        print("WebUIClient: next: `swift build` picks up the generated Wasm+Generated.swift (hash = content-addressed route)")
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

enum WebUIWasmClientError: Error, CustomStringConvertible {
    case buildFailed(Int32)
    case artifactMissing(String)
    case stripFailed
    var description: String {
        switch self {
        case .buildFailed(let code): return "wasm client cross-build failed with exit \(code)"
        case .artifactMissing(let path): return "built wasm artifact missing at \(path)"
        case .stripFailed: return "custom-section strip of the wasm artifact failed"
        }
    }
}
