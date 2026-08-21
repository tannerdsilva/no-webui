import Foundation
@main
enum WebUIAssetTool {

    static func main() throws {
        let args = ProcessInfo.processInfo.arguments.dropFirst()

        var cssInput: String?
        var jsInput: String?
        var outputPath: String?

        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--css-input":
                cssInput = iterator.next()
            case "--js-input":
                jsInput = iterator.next()
            case "--output":
                outputPath = iterator.next()
            default:
                break
            }
        }

        guard let outputPath else {
            print("usage: WebUIAssetTool --css-input <path> --js-input <path> --output <path>")
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

        let generated = generateSwiftSource(css: cssContent, js: jsContent)

        try generated.write(toFile: outputPath, atomically: true, encoding: .utf8)

        let cssBytes = cssContent.utf8.count
        let jsBytes = jsContent.utf8.count
        print("generated \(outputPath) (\(cssBytes) bytes CSS, \(jsBytes) bytes JS)")
    }
    static func generateSwiftSource(css: String, js: String) -> String {
        let escapedCSS = css.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")

        let indentedCSS = escapedCSS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        let indentedJS = escapedJS
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")

        return """
        import Foundation
        public enum WebUIAssets {
            public static let css: String = \"\"\"
        \(indentedCSS)
            \"\"\"
            public static let js: String = \"\"\"
        \(indentedJS)
            \"\"\"
        }
        """
    }
}
