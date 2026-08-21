import Foundation

// MARK: - HTMLDocument
public struct HTMLDocument: Sendable {
    public let title: String
    public let body: String
    public let styles: CSSStylesheet
    public let rawStyles: [String]
    public let scripts: String
    public let head: String
    public let bodyAttributes: String
    public let devMode: Bool
    public let lang: String
    public let includeRuntime: Bool
    public let contentSecurityPolicy: String?
    public let nonce: String
    private static func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
    private func effectiveCSP(nonce: String) -> String? {
        if let csp = contentSecurityPolicy {
            return csp.isEmpty ? nil : csp
        }
        if devMode {
            return "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"
        }
        return "default-src 'self'; script-src 'nonce-\(nonce)'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ws: wss:;"
    }
    public init(
        title: String = "WebUI UI",
        body: String,
        styles: CSSStylesheet = CSSStylesheet([]),
        rawStyles: [String] = [],
        scripts: String = "",
        head: String = "",
        bodyAttributes: String = "",
        devMode: Bool = false,
        lang: String = "en",
        includeRuntime: Bool = true,
        contentSecurityPolicy: String? = nil
    ) {
        self.title = title
        self.body = body
        self.styles = styles
        self.rawStyles = rawStyles
        self.scripts = scripts
        self.head = head
        self.bodyAttributes = bodyAttributes
        self.devMode = devMode
        self.lang = lang
        self.includeRuntime = includeRuntime
        self.contentSecurityPolicy = contentSecurityPolicy
        self.nonce = Self.generateNonce()
    }
    public func render() -> String {
        let styleTag: String
        let scriptTag: String
        let cspValue = effectiveCSP(nonce: nonce)

        if devMode {
            styleTag = "<link rel=\"stylesheet\" href=\"/ui/styles.css\">"
            let runtimeSrc = includeRuntime ? "<script src=\"/ui/scripts.js\"></script>" : ""
            let appSrc = scripts.isEmpty ? "" : "<script src=\"/ui/app.js\"></script>"
            scriptTag = [runtimeSrc, appSrc].filter { !$0.isEmpty }.joined(separator: "\n          ")
        } else {
            var cssParts: [String] = []
            let cssContent = styles.render()
            if !cssContent.isEmpty { cssParts.append(cssContent) }
            cssParts.append(contentsOf: rawStyles)
            let allCSS = cssParts.joined(separator: "\n\n")
            styleTag = allCSS.isEmpty ? "" : "<style>\n\(allCSS)\n</style>"

            var jsParts: [String] = []
            if includeRuntime {
                jsParts.append(WebUIRuntime.source)
                jsParts.append(WebUIRuntime.bootstrap)
            }
            if !scripts.isEmpty {
                jsParts.append(scripts)
            }
            let jsContent = jsParts.joined(separator: "\n\n")
            scriptTag = jsContent.isEmpty ? "" : "<script nonce=\"\(nonce)\">\n\(jsContent)\n</script>"
        }

        let bodyAttr = bodyAttributes.isEmpty ? "" : " \(bodyAttributes)"
        let cspTag: String
        if let csp = cspValue {
            cspTag = "\n          <meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\">"
        } else {
            cspTag = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="\(lang)">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">\(cspTag)
          <title>\(htmlEscape(title))</title>
          \(head)
          \(styleTag)
        </head>
        <body\(bodyAttr)>
          \(body)
          \(scriptTag)
        </body>
        </html>
        """
    }
}
