import Foundation
import WebUICore

@main
enum WebUIAssetTool {

    static func main() throws {
        let args = ProcessInfo.processInfo.arguments.dropFirst()

        var cssInput: String?
        var jsInput: String?
        var engineInput: String?
        var shellInput: String?
        var outputPath: String?
        var tokensOutputPath: String?
        var manifestOutputPath: String?
        var usedTokensPath: String?
        var guardCSSPaths: [String] = []

        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--css-input":
                cssInput = iterator.next()
            case "--js-input":
                jsInput = iterator.next()
            case "--engine-input":
                engineInput = iterator.next()
            case "--shell-input":
                shellInput = iterator.next()
            case "--output":
                outputPath = iterator.next()
            case "--tokens-output":
                tokensOutputPath = iterator.next()
            case "--manifest-output":
                manifestOutputPath = iterator.next()
            case "--used-tokens":
                usedTokensPath = iterator.next()
            case "--guard-css":
                if let path = iterator.next() { guardCSSPaths.append(path) }
            default:
                break
            }
        }

        guard outputPath != nil || tokensOutputPath != nil else {
            print("usage: WebUIAssetTool --css-input <path> --js-input <path> --engine-input <path> --shell-input <path> --output <path> [--tokens-output <path>] [--manifest-output <path>] [--used-tokens <path>] [--guard-css <path>]…")
            exit(1)
        }

        var cssContent = ""
        if let cssInput {
            cssContent = try String(contentsOfFile: cssInput, encoding: .utf8)
        }

        var jsContent = ""
        if let jsInput {
            jsContent = try String(contentsOfFile: jsInput, encoding: .utf8)
        }

        var engineContent = ""
        if let engineInput {
            engineContent = try String(contentsOfFile: engineInput, encoding: .utf8)
        }

        var shellContent = ""
        if let shellInput {
            shellContent = try String(contentsOfFile: shellInput, encoding: .utf8)
        }

        // the token vocabulary is written to its own output so the wasm-clean
        // design-system core can embed it without the server-bound WebUI target
        // (p5-t7: `DesignToken` is a client-reachable core surface).
        if let tokensOutputPath {
            guard cssInput != nil else {
                print("usage: --tokens-output requires --css-input")
                exit(1)
            }
            let tokenCount = try rootTokens(in: cssContent).count
            let tokensSource = try designTokenSource(from: cssContent)
            try tokensSource.write(toFile: tokensOutputPath, atomically: true, encoding: .utf8)
            print("generated \(tokensOutputPath) (\(tokenCount) tokens)")
        }

        if let outputPath {
            // T9: prune the `:root` token surface to the reachable set *before* anything is
            // minified, compressed or embedded — see TokenPruning. With no `--used-tokens`
            // there is no oracle to prune against and the sheet ships whole, byte-identical
            // to every build before this step existed.
            var pruning: TokenPruning.Outcome?
            if let usedTokensPath {
                guard cssInput != nil else {
                    print("usage: --used-tokens requires --css-input")
                    exit(1)
                }
                do {
                    let outcome = try TokenPruning.performing(
                        css: cssContent,
                        usedTokensPath: usedTokensPath,
                        guardPaths: guardCSSPaths
                    )
                    cssContent = outcome.css
                    pruning = outcome
                    print("pruned \(outcome.dropped.count) of \(outcome.dropped.count + outcome.kept.count) distinct tokens (\(outcome.emittedTokens) kept, \(outcome.declarations) :root declarations)")
                } catch {
                    print("error: \(error)")
                    exit(1)
                }
            }

            // the layout primitives are the framework's utility layer: above the
            // sheet's component rules, below anything unlayered. the order
            // statement is repeated here because layer order is set by first
            // mention and this block is prepended to the sheet (which declares the
            // same order — a repeat is a no-op).
            let cssMinified = minifyCSS(
                "@layer webui, webui.utilities;\n\n@layer webui.utilities {\n"
                    + CSSStylesheet(LayoutStyles.complete).render()
                    + "\n}\n\n" + cssContent
            )
            let cssGz = cssGzipData(of: cssMinified)
            let jsGz = jsInput.flatMap { gzipData(of: $0) }
            let engineGz = engineInput.flatMap { gzipData(of: $0) }
            let shellGz = shellInput.flatMap { gzipData(of: $0) }

            // the first law, enforced where the payloads are fixed: prose never
            // reaches a client. the working sheet may carry designer notes —
            // `minifyCSS` strips them before embedding — but the js assets have no
            // strip step, so their source must be clean. a comment in any payload
            // below fails the build here, naming file, line and text, rather than
            // shipping (a prose-filled release is exactly what nobody notices).
            let payloads: [(label: String, text: String, language: ProseGuard.Language)] = [
                (jsInput ?? "webui-runtime.js", jsContent, .javaScript),
                (engineInput ?? "webui-engine.js", engineContent, .javaScript),
                (shellInput ?? "webui-shell.js", shellContent, .javaScript),
                ("design-system.css (minified)", cssMinified, .css),
            ]
            var proseFound = false
            for payload in payloads {
                let findings = ProseGuard.findings(in: payload.text, language: payload.language)
                guard !findings.isEmpty else { continue }
                proseFound = true
                print("error: \(payload.label) would ship \(findings.count) comment(s) to clients:")
                for finding in findings.prefix(12) {
                    print("  \(payload.label):\(finding.line): \(finding.text)")
                }
            }
            if proseFound {
                print("  the shipped bytes are the client's — keep the note in Documentation/*.md, or in the css working file, which is minified before embedding.")
                exit(1)
            }

            let generated = try generateAssetsSource(
                css: cssContent, js: jsContent, engine: engineContent, shell: shellContent,
                cssMinified: cssMinified,
                cssGzip: cssGz?.base64EncodedString() ?? "",
                jsGzip: jsGz?.base64EncodedString() ?? "",
                engineGzip: engineGz?.base64EncodedString() ?? "",
                shellGzip: shellGz?.base64EncodedString() ?? ""
            )

            try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)

            let cssBytes = cssContent.utf8.count
            let jsBytes = jsContent.utf8.count
            let engineBytes = engineContent.utf8.count
            let shellBytes = shellContent.utf8.count
            print("generated \(outputPath) (\(cssBytes) bytes CSS, \(jsBytes) bytes JS, \(engineBytes) bytes engine, \(shellBytes) bytes shell)")

            // the SERVED numbers, for the budget gate. `plugin budget` otherwise has to
            // measure the working files, and the sheet differs from what ships by ~15%
            // (it is minified) — a budget on the wrong number is a false sense of safety.
            if let manifestOutputPath {
                var served: [String: Any] = [
                    "sheet": ["raw": cssMinified.utf8.count, "gz": cssGz?.count ?? 0,
                              "workingRaw": cssBytes],
                    "engine": ["raw": engineBytes, "gz": engineGz?.count ?? 0],
                    "shell": ["raw": shellBytes, "gz": shellGz?.count ?? 0],
                    "webui-runtime.js": ["raw": jsBytes, "gz": jsGz?.count ?? 0],
                ]
                // pruning is a build-time decision, so its effect belongs in the build-time
                // record: a sheet that quietly stopped declaring 134 tokens should be
                // visible in the manifest a budget gate reads, not inferred from byte counts.
                if let pruning {
                    served["tokens"] = [
                        "emitted": pruning.emittedTokens,
                        "pruned": pruning.dropped.count,
                        "declarations": pruning.declarations,
                    ]
                }
                let payload: [String: Any] = ["served": served]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: manifestOutputPath))
                }
            }
        }
    }

    /// gzip a file with the host `gzip`, base64-encoded, or "" when unavailable.
    ///
    /// compression happens at BUILD time on purpose. no-webui takes no
    /// dependencies and has no runtime compressor: Foundation's `compression`
    /// API is Darwin-only and linking zlib would be a dependency. the runtime
    /// therefore never compresses anything — it serves bytes prepared here.
    static func gzipData(of path: String) -> Data? {
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

    /// gzip an in-memory string (the minified sheet has no file on disk).
    static func cssGzipData(of text: String) -> Data? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("webui-css-min-\(ProcessInfo.processInfo.processIdentifier).css")
        guard (try? text.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return gzipData(of: tmp.path)
    }

    static func generateAssetsSource(
        css: String, js: String, engine: String, shell: String,
        cssMinified: String,
        cssGzip: String, jsGzip: String, engineGzip: String, shellGzip: String
    ) throws -> String {
        let escapedCSS = css.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedEngine = engine.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedShell = shell.replacingOccurrences(of: "\\", with: "\\\\")

        let indentedCSS = escapedCSS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedJS = escapedJS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedEngine = escapedEngine
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedShell = escapedShell
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let escapedMinified = cssMinified.replacingOccurrences(of: "\\", with: "\\\\")
        let indentedMinified = escapedMinified
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let assets = """
        import Foundation
        import WebUICore
        public enum WebUIAssets {
            public static let css: String = \"\"\"
        \(indentedCSS)
            \"\"\"
            public static let js: String = \"\"\"
        \(indentedJS)
            \"\"\"
            public static let engine: String = \"\"\"
        \(indentedEngine)
            \"\"\"
            public static let shell: String = \"\"\"
        \(indentedShell)
            \"\"\"
            /// the sheet exactly as it ships: minified at BUILD time, so the served
            /// bytes are build-time-known and therefore compressible at build time.
            public static let cssMinified: String = \"\"\"
        \(indentedMinified)
            \"\"\"
            /// pre-compressed variants, base64 (a 52k-element `[UInt8]` literal is
            /// slow to type-check). `nil` means the build host had no `gzip`; the
            /// server then falls back to the raw bytes rather than serving nothing.
            private static let cssGzipBase64 = "\(cssGzip)"
            private static let jsGzipBase64 = "\(jsGzip)"
            private static let engineGzipBase64 = "\(engineGzip)"
            private static let shellGzipBase64 = "\(shellGzip)"
            public static let cssGzip: [UInt8]? = decodeGzip(cssGzipBase64)
            public static let jsGzip: [UInt8]? = decodeGzip(jsGzipBase64)
            public static let engineGzip: [UInt8]? = decodeGzip(engineGzipBase64)
            public static let shellGzip: [UInt8]? = decodeGzip(shellGzipBase64)
            private static func decodeGzip(_ text: String) -> [UInt8]? {
                guard !text.isEmpty, let bytes = Base64.decode(text), !bytes.isEmpty else { return nil }
                return bytes
            }
        }
        """

        return assets
    }

    // MARK: - DesignToken generation
    //
    // enumerates the custom properties that appear inside a `:root` block
    // (at any nesting, so `@media (prefers-color-scheme: dark) { :root { ... } }`
    // counts too). only `:root`-scoped tokens respond to a later `:root`
    // override, so component-scoped custom properties (`.btn { --btn-bg: ... }`)
    // are deliberately excluded — they are restyled through theme rules, not
    // token overrides.

    /// custom properties declared inside any `:root` block, first-declaration
    /// order, deduplicated.
    static func rootTokens(in css: String) throws -> [String] {
        let clean = stripCSSComments(css)
        var stack: [String] = []
        var names: [String] = []
        var seen = Set<String>()
        var pending = ""
        var i = clean.startIndex
        while i < clean.endIndex {
            let c = clean[i]
            if c == "{" {
                stack.append(pending.trimmingCharacters(in: .whitespacesAndNewlines))
                pending = ""
                i = clean.index(after: i)
            } else if c == "}" {
                if !stack.isEmpty { stack.removeLast() }
                pending = ""
                i = clean.index(after: i)
            } else if c == ";", !stack.isEmpty {
                pending = ""
                i = clean.index(after: i)
            } else if c == "-", isStartOfTokenDecl(clean, at: i) {
                guard let (name, end) = parseTokenName(clean, from: i) else {
                    pending.append(c)
                    i = clean.index(after: i)
                    continue
                }
                if stack.contains(":root"), !seen.contains(name) {
                    seen.insert(name)
                    names.append(name)
                }
                i = end
            } else {
                pending.append(c)
                i = clean.index(after: i)
            }
        }
        return names
    }

    static func stripCSSComments(_ css: String) -> String {
        var out = ""
        out.reserveCapacity(css.utf8.count)
        var i = css.startIndex
        while i < css.endIndex {
            let c = css[i]
            if c == "/", css.index(after: i) != css.endIndex, css[css.index(after: i)] == "*" {
                var j = css.index(after: i)
                j = css.index(after: j)
                var closed = false
                while j != css.endIndex {
                    if css[j] == "*", css.index(after: j) != css.endIndex, css[css.index(after: j)] == "/" {
                        closed = true
                        j = css.index(after: j)
                        j = css.index(after: j)
                        break
                    }
                    j = css.index(after: j)
                }
                i = j
                if closed { continue }
            }
            out.append(c)
            i = css.index(after: i)
        }
        return out
    }

    /// true when `css[i]` begins a custom property declaration (`--name:`) as
    /// opposed to a `var(--name)` reference.
    static func isStartOfTokenDecl(_ css: String, at i: String.Index) -> Bool {
        // the char before must not be a letter/digit/hyphen (a `var(--x)`
        // reference has `(` before; `--x` inside a value's `var(...)` is not a
        // declaration). a declaration appears right after `{`, `;`, or `}` +
        // whitespace.
        guard i != css.startIndex else { return true }
        let prev = css[css.index(before: i)]
        return !(prev.isLetter || prev.isNumber || prev == "-")
    }

    /// parses `--name` and the following optional whitespace + `:`. returns
    /// the name and the index just past the colon when a `:` follows; returns
    /// nil when the `--` is a `var(--name)` reference or other non-declaration
    /// (so the caller falls back to character-by-character scanning).
    static func parseTokenName(_ css: String, from i: String.Index) -> (name: String, end: String.Index)? {
        var j = css.index(after: i) // skip first '-'
        j = css.index(after: j)     // skip second '-'
        var name = ""
        while j != css.endIndex, isNameChar(css[j]) {
            name.append(css[j])
            j = css.index(after: j)
        }
        guard !name.isEmpty else { return nil }
        var k = j
        while k != css.endIndex, css[k] == " " || css[k] == "\t" {
            k = css.index(after: k)
        }
        guard k != css.endIndex, css[k] == ":" else { return nil }
        return (name, css.index(after: k))
    }

    static func isNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_"
    }

    /// maps `color-primary-solid` → `colorPrimarySolid`. deterministic and
    /// collision-checked; Swift keywords are backticked; a leading digit gets
    /// a `token` prefix so every case name is a legal identifier.
    static func camelCase(_ name: String) -> String {
        let parts = name.split(separator: "-", omittingEmptySubsequences: true)
        guard let first = parts.first else { return name }
        var result = String(first)
        for part in parts.dropFirst() {
            result += part.prefix(1).uppercased() + part.dropFirst()
        }
        if let digit = result.first, digit.isNumber {
            result = "token" + result
        }
        if swiftKeywords.contains(result) {
            return "`\(result)`"
        }
        return result
    }

    static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "protocol", "public", "rethrows", "static", "struct",
        "subscript", "typealias", "var", "break", "case", "continue", "default",
        "defer", "do", "else", "fallthrough", "for", "guard", "if", "in",
        "repeat", "return", "switch", "where", "while", "as", "any", "catch",
        "false", "is", "nil", "super", "self", "Self", "throw", "throws", "true",
        "try", "await", "actor", "async", "borrowing", "consuming", "distributed",
        "each", "macro", "nonisolated", "package", "some", "sending", "then",
        "isolated",
    ]

    static func designTokenSource(from css: String) throws -> String {
        let names = try rootTokens(in: css)
        var caseLines: [String] = []
        var seenCaseNames = Set<String>()
        for name in names {
            let caseName = camelCase(name)
            guard seenCaseNames.insert(caseName).inserted else {
                throw TokenGenerationError.camelCaseCollision(name)
            }
            caseLines.append("\tcase \(caseName) = \"\(name)\"")
        }
        let cases = caseLines.joined(separator: "\n")
        let count = names.count
        return """
        /// design tokens declared on `:root` in `design-system.css`, generated
        /// by `WebUIAssetPlugin`. exactly the custom properties that respond to
        /// a later `:root` override — the theme surface. component-scoped custom
        /// properties are excluded by construction.
        public enum DesignToken: String, CaseIterable, Hashable, Sendable {
        \(cases)

        \t/// the css custom property name, including the leading `--`.
        \tpublic var cssVariable: String { "--\\(rawValue)" }
        \t/// number of tokens enumerated from the shipped stylesheet.
        \tpublic static let tokenCount = \(count)
        }
        """
    }
}

enum TokenGenerationError: Error, CustomStringConvertible {
    case camelCaseCollision(String)

    var description: String {
        switch self {
        case .camelCaseCollision(let name):
            return "camelCased token name collides for '\(name)' — two css custom properties map to the same swift identifier"
        }
    }
}
