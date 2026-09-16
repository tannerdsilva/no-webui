import Foundation

@main
enum WebUIAssetTool {

    static func main() throws {
        let args = ProcessInfo.processInfo.arguments.dropFirst()

        var cssInput: String?
        var jsInput: String?
        var clientInput: String?
        var clientBootInput: String?
        var clientSearchBootInput: String?
        var outputPath: String?

        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--css-input":
                cssInput = iterator.next()
            case "--js-input":
                jsInput = iterator.next()
            case "--client-input":
                clientInput = iterator.next()
            case "--client-boot-input":
                clientBootInput = iterator.next()
            case "--client-search-boot-input":
                clientSearchBootInput = iterator.next()
            case "--output":
                outputPath = iterator.next()
            default:
                break
            }
        }

        guard let outputPath else {
            print("usage: WebUIAssetTool --css-input <path> --js-input <path> --client-input <path> --client-boot-input <path> --client-search-boot-input <path> --output <path>")
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

        var clientContent = ""
        if let clientInput {
            clientContent = try String(contentsOfFile: clientInput, encoding: .utf8)
        }

        var clientBootContent = ""
        if let clientBootInput {
            clientBootContent = try String(contentsOfFile: clientBootInput, encoding: .utf8)
        }

        var clientSearchBootContent = ""
        if let clientSearchBootInput {
            clientSearchBootContent = try String(contentsOfFile: clientSearchBootInput, encoding: .utf8)
        }

        let generated = try generateSwiftSource(
            css: cssContent, js: jsContent, client: clientContent,
            clientBoot: clientBootContent, clientSearchBoot: clientSearchBootContent
        )

        try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)

        let cssBytes = cssContent.utf8.count
        let jsBytes = jsContent.utf8.count
        let clientBytes = clientContent.utf8.count
        let bootBytes = clientBootContent.utf8.count
        let searchBytes = clientSearchBootContent.utf8.count
        print("generated \(outputPath) (\(cssBytes) bytes CSS, \(jsBytes) bytes JS, \(clientBytes) bytes client, \(bootBytes) bytes boot, \(searchBytes) bytes search boot)")
    }

    static func generateSwiftSource(css: String, js: String, client: String, clientBoot: String, clientSearchBoot: String) throws -> String {
        let escapedCSS = css.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedClient = client.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedBoot = clientBoot.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedSearchBoot = clientSearchBoot.replacingOccurrences(of: "\\", with: "\\\\")

        let indentedCSS = escapedCSS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedJS = escapedJS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedClient = escapedClient
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedBoot = escapedBoot
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedSearchBoot = escapedSearchBoot
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let assets = """
        import Foundation
        public enum WebUIAssets {
            public static let css: String = \"\"\"
        \(indentedCSS)
            \"\"\"
            public static let js: String = \"\"\"
        \(indentedJS)
            \"\"\"
            public static let client: String = \"\"\"
        \(indentedClient)
            \"\"\"
            public static let clientBoot: String = \"\"\"
        \(indentedBoot)
            \"\"\"
            public static let clientSearchBoot: String = \"\"\"
        \(indentedSearchBoot)
            \"\"\"
        }
        """

        return assets + "\n\n" + (try designTokenSource(from: css))
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
